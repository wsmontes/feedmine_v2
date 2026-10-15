#!/usr/bin/env python3
"""Fail-closed release provenance gate. Reuses bootstrap_catalog's identity rules.

This script never downloads or changes Resources; only bootstrap prepares content.
Preflight and archive use the same verify_chain(), including a fresh public read.
"""
from __future__ import annotations

import argparse
import json
import plistlib
import sys
from pathlib import Path

import bootstrap_catalog as catalog

RESOURCE = Path("FeedMineApp/FeedMineApp/Resources")
PUBLIC_URL = catalog.DEFAULT_PUBLIC_BASE + "/manifest.json"


class Refused(Exception):
    pass


def need(condition: bool, message: str) -> None:
    if not condition:
        raise Refused(message)


def load_json(path: Path) -> dict:
    need(path.is_file(), f"missing {path}")
    try:
        result = json.loads(path.read_bytes())
    except (OSError, ValueError) as error:
        raise Refused(f"invalid {path}: {error}") from error
    need(isinstance(result, dict), f"expected JSON object: {path}")
    return result


def digest(path: Path) -> dict:
    need(path.is_file(), f"missing {path}")
    return {"bytes": path.stat().st_size, "sha256": catalog.sha256_file(path)}


def verify_chain(resources: Path, staging: Path, public_manifest: Path | None) -> dict:
    """Current public declaration -> verified OPML bytes -> compiler -> exact staged pair."""
    url = PUBLIC_URL if public_manifest is None else public_manifest.resolve().as_uri()
    try:
        raw = catalog.http_get(url) if public_manifest is None else public_manifest.read_bytes()
    except (OSError, catalog.Failure) as error:
        raise Refused(f"public manifest unavailable; freshness unverified: {error}") from error
    public_sha = catalog.sha256_bytes(raw)
    try:
        public = catalog.validate_manifest(json.loads(raw), raw, url, None)
    except (ValueError, catalog.Refusal) as error:
        raise Refused(f"public manifest refused: {error}") from error

    db = resources / catalog.SQLITE_NAME
    descriptor_path = resources / catalog.DESCRIPTOR_NAME
    descriptor = load_json(descriptor_path)
    try:
        catalog.validate_descriptor(descriptor)
    except (ValueError, KeyError, TypeError, catalog.Refusal) as error:
        raise Refused(f"invalid bundled descriptor: {error}") from error
    provenance = load_json(staging / catalog.PROVENANCE_NAME)
    state = load_json(staging / catalog.STATE_NAME)
    report = load_json(staging / catalog.REPORT_NAME)
    staged_db = staging / catalog.SQLITE_NAME
    staged_descriptor = staging / catalog.DESCRIPTOR_NAME

    need(descriptor.get("revision") == public["revision"],
         f"bundled revision {descriptor.get('revision')} != latest public revision {public['revision']}")
    need(descriptor.get("schemaVersion") == public["schemaVersion"], "descriptor schemaVersion differs from public")
    need(descriptor.get("sourceCount") == public["sourceCount"], "descriptor sourceCount differs from public")
    need(descriptor.get("generatedAt") == public.get("generatedAt"), "public generatedAt differs")
    derived = descriptor["derivedFrom"]
    need(derived.get("manifest") == PUBLIC_URL, "descriptor authority URL is not the public channel")
    need(derived.get("manifestSha256") == public_sha,
         "same revision with different public manifest bytes (manifestSha256 mismatch)")
    need(derived.get("revision") == public["revision"] and
         derived.get("opmlEntries") == public["fileCount"], "descriptor derivedFrom inventory differs")
    expected = [{"role": "opml", "path": e["path"], "bytes": e["bytes"], "sha256": e["sha256"]}
                for e in public["files"]]
    need(descriptor["files"][:-1] == expected, "complete public OPML inventory differs from bundle")
    need(descriptor["fileCount"] == len(expected) + 1, "descriptor fileCount differs")
    need(descriptor["files"][-1]["role"] == "catalogue" and
         descriptor["files"][-1]["path"] == catalog.SQLITE_NAME, "catalogue entry is not last")

    for entry in public["files"]:
        path = staging / catalog.PAYLOAD_DIR / entry["path"]
        need(catalog.file_matches(path, entry["bytes"], entry["sha256"]),
             f"OPML absent or changed: {entry['path']} (size/SHA-256)")

    need(provenance.get("manifest", {}).get("sha256") == public_sha,
         "bootstrap provenance manifest hash differs")
    need(provenance["manifest"]["url"] == PUBLIC_URL and
         provenance["manifest"]["revision"] == public["revision"], "bootstrap provenance authority/revision differs")
    need(provenance["payload"]["treeSha256"] == catalog.tree_identity(public["files"]),
         "bootstrap feed tree fingerprint differs")
    need(state.get("manifestSha256") == public_sha and
         state.get("revision") == public["revision"], "bootstrap state differs from public manifest")
    need(state.get("feedTreeSha256") == catalog.tree_identity(public["files"]),
         "bootstrap state feed inventory differs")
    try:
        catalog.validate_report(report, public)
    except catalog.Refusal as error:
        raise Refused(f"incompatible compiler report: {error}") from error
    need(provenance.get("buildReport") == report, "compiler report differs from provenance")
    need(state.get("artifacts", {}).get(catalog.REPORT_NAME) ==
         digest(staging / catalog.REPORT_NAME), "bootstrap state build report SHA-256 differs")
    compiler = provenance.get("compiler", {})
    dependency = compiler.get("dependency", {})
    need(compiler.get("path") and dependency.get("path"),
         "compiler identity must name build_catalog.py and catalog_identity.py")
    need(Path(compiler["path"]).resolve().with_name("catalog_identity.py") ==
         Path(dependency["path"]).resolve(), "compiler identity dependency path differs")
    try:
        actual_compiler = catalog.compiler_identity(
            Path(compiler["path"]), compiler.get("sha256", ""), dependency.get("sha256", ""))
    except (catalog.Failure, catalog.Refusal) as error:
        raise Refused(f"compiler unverified: {error}") from error
    need(actual_compiler["dependency"] == dependency, "compiler dependency identity differs")
    need(state.get("compiler") == {k: compiler[k] for k in
         ("path", "sha256", "dependency", "gitCommit", "python")},
         "compiler identity differs from recorded reuse state")
    command = compiler.get("command")
    need(isinstance(command, list) and len(command) >= 8 and
         command[1] == compiler["path"] and
         command[2:4] == ["--feeds-root", str(staging / "payload" / "Feeds")] and
         command[4:6] == ["--output", str(staging / ".work" / catalog.SQLITE_NAME)] and
         command[6:8] == ["--manifest-output", str(staging / ".work" / catalog.REPORT_NAME)],
         "recorded compiler command does not describe verified inputs/outputs")
    need(compiler.get("python"), "compiler Python version missing")

    actual_db = digest(db)
    need(descriptor["files"][-1]["bytes"] == actual_db["bytes"] and
         descriptor["files"][-1]["sha256"] == actual_db["sha256"],
         "resource SQLite bytes/SHA-256 differ from descriptor")
    need(actual_db == digest(staged_db), "resource SQLite differs from verified staged compiler output")
    actual_descriptor = digest(descriptor_path)
    need(actual_descriptor == digest(staged_descriptor), "resource descriptor differs from verified staging")
    need(state.get("artifacts", {}).get(catalog.SQLITE_NAME) == actual_db,
         "bootstrap state SQLite hash differs")
    need(state.get("artifacts", {}).get(catalog.DESCRIPTOR_NAME) == actual_descriptor,
         "bootstrap state descriptor hash differs")
    need(provenance.get("descriptor", {}).get("sha256") == actual_descriptor["sha256"],
         "bootstrap descriptor provenance differs")
    return {
        "publicManifest": {"url": PUBLIC_URL, "revision": public["revision"],
                           "sha256": public_sha, "bytes": len(raw),
                           "opmlCount": public["fileCount"], "sourceCount": public["sourceCount"],
                           "treeSha256": catalog.tree_identity(public["files"])},
        "compiler": {k: compiler[k] for k in ("path", "sha256", "dependency", "gitCommit", "python", "command")},
        "buildReport": {"sha256": digest(staging / catalog.REPORT_NAME)["sha256"],
                        "fileCount": report["file_count"], "sourceCount": report["source_count"]},
        "resources": {"sqlite": actual_db, "descriptor": actual_descriptor},
        "checks": ["fresh public manifest", "full inventory and OPML bytes", "compiler and dependency",
                   "compiler command and report", "staging and resource bytes"],
    }


def verify_archive(archive: Path, resources: Path, chain: dict, head: str,
                   version: str, build: str) -> dict:
    app = archive / "Products/Applications/FeedMine.app"
    need(app.is_dir(), f"missing archived application: {app}")
    archived_db = digest(app / catalog.SQLITE_NAME)
    archived_manifest = digest(app / catalog.DESCRIPTOR_NAME)
    need(archived_db == chain["resources"]["sqlite"], "archive SQLite differs from preflight bytes/SHA-256")
    need(archived_manifest == chain["resources"]["descriptor"], "archive descriptor differs from preflight bytes/SHA-256")
    need((app / catalog.DESCRIPTOR_NAME).read_bytes() ==
         (resources / catalog.DESCRIPTOR_NAME).read_bytes(), "archive descriptor bytes differ from resources")
    try:
        with (app / "Info.plist").open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, ValueError, TypeError) as error:
        raise Refused(f"archive Info.plist unreadable: {error}") from error
    need(info.get("CFBundleIdentifier") == "com.feedmine.app", "archive bundle identifier differs")
    need(str(info.get("CFBundleVersion")) == build, "archive build number differs")
    need(str(info.get("CFBundleShortVersionString")) == version, "archive version differs")
    need(info.get("FeedmineGitSHA") == head[:7] or
         (isinstance(info.get("FeedmineGitSHA"), str) and
          head.startswith(info["FeedmineGitSHA"]) and len(info["FeedmineGitSHA"]) >= 7),
         "archive Git SHA differs from release HEAD")
    return {"bundleID": info["CFBundleIdentifier"], "version": version, "build": build,
            "gitSHA": info["FeedmineGitSHA"], "sqlite": archived_db,
            "descriptor": archived_manifest,
            "checks": ["archive resource bytes", "archive descriptor", "archive Info.plist Git/version/bundle"]}


def run(args: argparse.Namespace) -> None:
    resources = args.resources.resolve()
    staging = args.staging.resolve()
    evidence_dir = args.evidence_dir.resolve()
    chain = verify_chain(resources, staging, args.public_manifest)
    need(len(args.head) == 40 and all(c in "0123456789abcdef" for c in args.head),
         "release HEAD must be a full Git SHA")
    evidence_dir.mkdir(parents=True, exist_ok=True)
    preflight_path = evidence_dir / "pd10-p0c-preflight.json"
    if args.command == "preflight":
        record = {"git": {"sha": args.head}, **chain, "preflight": "PASS"}
        catalog.write_json(preflight_path, record)
        print(f"P0C preflight verified: revision {chain['publicManifest']['revision']} / "
              f"manifest {chain['publicManifest']['sha256']} / sqlite {chain['resources']['sqlite']['sha256']}")
        return
    previous = load_json(preflight_path)
    need(previous.get("git", {}).get("sha") == args.head, "preflight Git SHA differs")
    need(previous.get("preflight") == "PASS" and
         all(previous.get(key) == chain[key] for key in
             ("publicManifest", "compiler", "buildReport", "resources")),
         "preflight stale: public declaration or resource/derivation changed during archive")
    result = verify_archive(args.archive.resolve(), resources, chain, args.head, args.version, args.build)
    evidence = {"format": "feedmine-pd10-p0c-release-v1", "git": {"sha": args.head},
                **chain, "archive": result, "preflight": "PASS", "archiveVerification": "PASS"}
    output = evidence_dir / f"pd10-p0c-{args.version}-build-{args.build}-{args.head[:12]}.json"
    catalog.write_json(output, evidence)
    print(f"P0C archive verified; build evidence: {output}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("preflight", "archive"))
    parser.add_argument("--resources", type=Path, default=RESOURCE)
    parser.add_argument("--staging", type=Path, default=catalog.DEFAULT_STAGING)
    parser.add_argument("--evidence-dir", type=Path, default=Path(".build"))
    parser.add_argument("--head", required=True)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--build")
    parser.add_argument("--public-manifest", type=Path,
                        help="local manifest fixture only; never set by release-testflight.sh")
    args = parser.parse_args()
    if args.command == "archive" and (args.archive is None or not args.version or not args.build):
        parser.error("archive requires --archive, --version, --build")
    try:
        run(args)
    except (Refused, catalog.Refusal, catalog.Failure, OSError, KeyError, TypeError) as error:
        print(f"REFUSED P0C: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
