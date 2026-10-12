#!/usr/bin/env python3
"""Bootstrap a *verifiable* copy of the catalogue this app bundles (PD-10).

What this produces, and from what
--------------------------------
The catalogue FeedMine V2 ships has two layers, and this script builds the lower one from evidence only:

  1. the **public inventory** `manifest.json` published by `wawasoft/feed-repository@main` — `revision`,
     `schemaVersion`, `fileCount`, `sourceCount` and one `{path, bytes, sha256}` per OPML (118 files);
  2. the **compiled catalogue** `catalog.sqlite`, produced by the legacy V1 compiler
     (`feedmine/scripts/build_catalog.py`) from exactly those OPMLs;
  3. the **bundled descriptor** `catalog.manifest.json`, the public manifest's shape plus one entry for
     `catalog.sqlite` itself, so the snapshot the app opens is covered by the same checksums as the OPMLs it was
     built from (`CatalogManifest.catalogueEntry`).

The descriptor this script writes is **not** a copy of the public manifest: it repeats the published inventory
(the 118 OPML entries, which prove the *inputs*) and adds the compiled catalogue the channel does not publish
(the `.sqlite` entry, which proves the *derived artefact*), so the two roles are marked in the file itself
(`"role": "opml"` / `"role": "catalogue"`) and the derivation is stated beside the totals
(`derivedFrom.manifest`, its real `manifestSha256`, its `revision` and its OPML count) rather than left to be
deduced from a 119-entry list that looks like the published one. Unknown keys are ignored by the V2 decoder
(`CatalogManifest`), which is what makes the marker safe to carry.

Every step refuses instead of repairing, and nothing is written into the staging tree until the step it belongs
to has passed — a failure leaves a previous, already-published result exactly as it was:

  * the published `revision` is **pinned** (default 5, `--revision`): a published revision that moved is a
    different decision, never a silent upgrade, so it is refused;
  * `schemaVersion` must be the manifest format this build understands (1; `CatalogManifest.supportedSchemaVersion`);
  * every OPML is verified by `bytes` **and** `sha256` against the manifest, in manifest order, and the first
    divergence is refused by name before anything is written;
  * the build report's `file_count`/`source_count` must equal the manifest's `fileCount`/`sourceCount`;
  * no number in the descriptor is invented: each comes from the manifest or from the artefact just built.

Vocabulary used below
---------------------
*payload root*   the directory the manifest's paths are relative to (`<staging>/payload` here).
*feeds tree*     the OPMLs under `<payload root>/Feeds`, i.e. `--feeds-root` for the compiler.
*tree identity*  sha256 over `"<path>\\t<bytes>\\t<sha256>\\n"` for every OPML in manifest order — one value that
                 changes if the inventory, or any declared byte count or checksum, changes.

Idempotence (PD-10)
-------------------
An OPML already on disk that still matches its declaration is re-verified, never re-downloaded. The compiler is
not re-run when its inputs are unchanged (feeds tree identity, manifest bytes, compiler bytes) and its outputs
still match what was recorded — the compiler stamps a wall-clock `catalog_version`, so an unnecessary rebuild
would mint a new `.sqlite` checksum for identical inputs.

Usage
-----
    python3 scripts/bootstrap_catalog.py [--revision 5] [--staging-root build/catalog-bootstrap]
                                         [--public-base URL] [--compiler PATH] [--refetch] [--rebuild]

Exit codes: 0 success, 2 refused (a mismatch, per the contract), 1 operational failure (network, tooling).
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# The channel the app itself reads (`CatalogUpdateChannel.publicManifestURL`).
DEFAULT_PUBLIC_BASE = "https://raw.githubusercontent.com/wawasoft/feed-repository/main"
DEFAULT_REVISION = 5
SUPPORTED_MANIFEST_SCHEMA = 1
DEFAULT_COMPILER = Path("/Users/wagnermontes/Documents/GitHub/feedmine/scripts/build_catalog.py")
REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_STAGING = REPO_ROOT / "build" / "catalog-bootstrap"

SQLITE_NAME = "catalog.sqlite"
DESCRIPTOR_NAME = "catalog.manifest.json"
REPORT_NAME = "build-report.json"
PROVENANCE_NAME = "provenance.json"
STATE_NAME = "state.json"
PAYLOAD_DIR = "payload"
# What the compiler produces, and therefore what the reuse gate may look at. The descriptor is deliberately not
# part of the gate: it is derived from these artefacts and regenerated deterministically on every run, so a
# change to its shape must never force a recompile — the compiler stamps a wall-clock `catalog_version`, so a
# needless rebuild would mint a new catalogue checksum for identical inputs.
BUILD_ARTIFACTS = (SQLITE_NAME, REPORT_NAME)
OPML_ROLE = "opml"
CATALOGUE_ROLE = "catalogue"
FEEDS_PREFIX = "Feeds/"
DOWNLOAD_WORKERS = 8
USER_AGENT = "feedmine-v2-catalog-bootstrap/1"


class Refusal(Exception):
    """A mismatch: the inputs are not what this build was told to expect. Never repaired."""


class Failure(Exception):
    """Operational failure: network, missing tool, unreadable artefact."""


# --------------------------------------------------------------------------------------------------
# Hashing, fetching, printing


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path, chunk_size: int = 1 << 20) -> str:
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            hasher.update(chunk)
    return hasher.hexdigest()


def tree_identity(entries: list[dict]) -> str:
    """The one digest that stands for the whole feeds tree, as declared (see module docstring)."""
    hasher = hashlib.sha256()
    for entry in entries:
        hasher.update(f"{entry['path']}\t{entry['bytes']}\t{entry['sha256']}\n".encode("utf-8"))
    return hasher.hexdigest()


def http_get(url: str, timeout: float = 120.0) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status = getattr(response, "status", 200)
            if status != 200:
                raise Failure(f"{url} answered HTTP {status}")
            return response.read()
    except urllib.error.HTTPError as error:
        raise Failure(f"{url} answered HTTP {error.code}") from None
    except urllib.error.URLError as error:
        raise Failure(f"{url} is unreachable: {error.reason}") from None


def raw_url(base: str, path: str) -> str:
    return f"{base.rstrip('/')}/{urllib.parse.quote(path, safe='/')}"


def say(line: str = "") -> None:
    print(line, flush=True)


def step(number: int, title: str) -> None:
    say()
    say(f"[{number}/6] {title}")


def detail(line: str) -> None:
    say(f"       {line}")


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    incoming = path.with_name(path.name + ".incoming")
    incoming.write_bytes(data)
    os.replace(incoming, path)


def write_json(path: Path, value: object) -> bytes:
    data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")
    write_atomic(path, data)
    return data


def is_sha256(value: object) -> bool:
    return isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value)


def is_safe_relative_path(path: object) -> bool:
    if not isinstance(path, str) or not path or path.startswith(("/", "~", "\\")) or "\\" in path:
        return False
    return all(part not in ("", ".", "..") for part in path.split("/"))


# --------------------------------------------------------------------------------------------------
# 1. The public manifest


def validate_manifest(manifest: object, raw: bytes, url: str, expected_revision: int) -> dict:
    """The structural validation `CatalogManifest.validate(_:)` performs, plus this bootstrap's pin.

    Anything this build does not understand is refused here, before a single OPML is fetched.
    """
    if not isinstance(manifest, dict):
        raise Refusal(f"{url} is not a JSON object")
    for key in ("revision", "schemaVersion", "sourceCount", "fileCount", "files"):
        if key not in manifest:
            raise Refusal(f"{url} declares no {key}")

    revision, schema_version = manifest["revision"], manifest["schemaVersion"]
    if schema_version != SUPPORTED_MANIFEST_SCHEMA:
        raise Refusal(
            f"{url} declares schemaVersion {schema_version}; this build understands "
            f"{SUPPORTED_MANIFEST_SCHEMA} (CatalogManifest.supportedSchemaVersion)"
        )
    if not isinstance(revision, int) or revision <= 0:
        raise Refusal(f"{url} declares a non-positive revision {revision!r}")
    if revision != expected_revision:
        raise Refusal(
            f"published revision moved: {url} declares revision {revision}, this bootstrap is pinned to "
            f"{expected_revision} — a later revision is a different decision, not a silent upgrade"
        )
    if not isinstance(manifest["sourceCount"], int) or manifest["sourceCount"] <= 0:
        raise Refusal(f"{url} declares a non-positive sourceCount {manifest['sourceCount']!r}")
    files = manifest["files"]
    if not isinstance(files, list) or not files:
        raise Refusal(f"{url} declares an empty inventory")
    if manifest["fileCount"] != len(files):
        raise Refusal(
            f"{url} declares fileCount {manifest['fileCount']} but lists {len(files)} files"
        )

    seen: set[str] = set()
    for entry in files:
        if not isinstance(entry, dict) or not {"path", "bytes", "sha256"} <= set(entry):
            raise Refusal(f"{url} has a malformed inventory entry: {entry!r}")
        path = entry["path"]
        if not is_safe_relative_path(path):
            raise Refusal(f"{url} declares an unsafe path: {path!r}")
        if path in seen:
            raise Refusal(f"{url} declares {path} twice")
        seen.add(path)
        if not isinstance(entry["bytes"], int) or entry["bytes"] <= 0:
            raise Refusal(f"{path}: declared bytes {entry['bytes']!r} (entries must be non-empty)")
        if not is_sha256(entry["sha256"]):
            raise Refusal(f"{path}: malformed sha256 {entry['sha256']!r}")
        if path.lower().endswith(".sqlite"):
            raise Refusal(
                f"{url} now declares a compiled catalogue ({path}); the public channel's inventory is OPML-only "
                "and this bootstrap compiles the .sqlite itself — refuse rather than guess which one ships"
            )
        if not path.startswith(FEEDS_PREFIX):
            raise Refusal(
                f"{url} declares {path}, which is outside {FEEDS_PREFIX!r}: this bootstrap compiles with "
                f"--feeds-root <payload>/{FEEDS_PREFIX.rstrip('/')} and will not guess a different tree"
            )

    say(f"       revision {revision}, schemaVersion {schema_version}, "
        f"fileCount {manifest['fileCount']}, sourceCount {manifest['sourceCount']}")
    say(f"       generatedAt {manifest.get('generatedAt')!r} (carried into the descriptor)")
    say(f"       manifest sha256 {sha256_bytes(raw)} ({len(raw)} bytes)")
    return manifest


# --------------------------------------------------------------------------------------------------
# 2. The OPML inventory


def file_matches(path: Path, declared_bytes: int, declared_sha256: str) -> bool:
    try:
        status = path.stat()
    except OSError:
        return False
    if not stat.S_ISREG(status.st_mode) or status.st_size != declared_bytes:
        return False
    return sha256_file(path) == declared_sha256


def verify_payload(entries: list[dict], payload_root: Path, base: str, refetch: bool) -> dict:
    """Re-verifies what is already on disk, fetches what is not, and refuses on the first divergence.

    Nothing is written under `payload_root` until every declared file has been verified: a refusal here leaves a
    previous bootstrap untouched.
    """
    started = time.monotonic()
    reused, stale = 0, []
    for entry in entries:
        if not refetch and file_matches(payload_root / entry["path"], entry["bytes"], entry["sha256"]):
            reused += 1
        else:
            stale.append(entry)

    fetched: dict[str, bytes] = {}
    if stale:
        say(f"       fetching {len(stale)} of {len(entries)} OPMLs from {base}")
        with concurrent.futures.ThreadPoolExecutor(max_workers=DOWNLOAD_WORKERS) as pool:
            futures = {pool.submit(http_get, raw_url(base, e["path"])): e for e in stale}
            done = 0
            for future in concurrent.futures.as_completed(futures):
                entry = futures[future]
                fetched[entry["path"]] = future.result()
                done += 1
                if done % 25 == 0 or done == len(stale):
                    say(f"         {done}/{len(stale)} fetched")

    # Verified in manifest order, so "the first divergence" is a property of the manifest and not of the network.
    for entry in entries:
        data = fetched.get(entry["path"])
        if data is None:
            continue
        if len(data) != entry["bytes"]:
            raise Refusal(
                f"{entry['path']}: declared {entry['bytes']} bytes, {base} served {len(data)}"
            )
        digest = sha256_bytes(data)
        if digest != entry["sha256"]:
            raise Refusal(
                f"{entry['path']}: declared sha256 {entry['sha256']}, {base} served {digest}"
            )

    written = 0
    for entry in entries:
        data = fetched.get(entry["path"])
        if data is None:
            continue
        was_cached = (payload_root / entry["path"]).exists()
        write_atomic(payload_root / entry["path"], data)
        written += 1
        if was_cached:
            say(f"       re-fetched {entry['path']}: the local copy did not match the declaration")

    declared_bytes = sum(e["bytes"] for e in entries)
    say(f"       inventory {len(entries)}/{len(entries)} verified by size and SHA-256 "
        f"({reused} reused from disk, {len(stale)} downloaded, {declared_bytes} bytes declared)")
    say(f"       tree identity {tree_identity(entries)} ({time.monotonic() - started:.1f}s)")
    return {"reused": reused, "downloaded": len(stale), "written": written,
        "bytes": declared_bytes, "tree_sha256": tree_identity(entries)}


# --------------------------------------------------------------------------------------------------
# 3-4. The compiler, and its report


def compiler_command(compiler: Path, feeds_root: Path, output: Path, report: Path) -> list[str]:
    return [sys.executable, str(compiler), "--feeds-root", str(feeds_root), "--output", str(output),
        "--manifest-output", str(report), "--json"]


def compiler_identity(compiler: Path) -> dict:
    if not compiler.is_file():
        raise Failure(f"compiler not found: {compiler}")
    return {"path": str(compiler), "sha256": sha256_file(compiler), "python": sys.version.split()[0]}


def reuse_state(staging: Path, state: dict, identity: dict, revision: int, manifest_sha: str,
        feed_tree_sha: str) -> dict | None:
    """The previous run's result, when every input identity and every compiler output still agrees.

    Only `BUILD_ARTIFACTS` are consulted: the descriptor is derived from them and rewritten on every run, so it
    can neither force nor prevent a recompile.
    """
    if state.get("revision") != revision or state.get("manifestSha256") != manifest_sha:
        return None
    if state.get("feedTreeSha256") != feed_tree_sha or state.get("compiler") != identity:
        return None
    recorded_artifacts = state.get("artifacts")
    if not isinstance(recorded_artifacts, dict):
        return None
    for name in BUILD_ARTIFACTS:
        recorded = recorded_artifacts.get(name)
        path = staging / name
        if not isinstance(recorded, dict) or not isinstance(recorded.get("bytes"), int):
            return None
        try:
            if not path.is_file() or path.stat().st_size != recorded["bytes"]:
                return None
        except OSError:
            return None
        if sha256_file(path) != recorded.get("sha256"):
            return None
    return state


def build(compiler_cmd: list[str], work: Path) -> tuple[Path, Path, float]:
    work.mkdir(parents=True, exist_ok=True)
    catalogue, report = work / SQLITE_NAME, work / REPORT_NAME
    for stale in (catalogue, report):
        if stale.exists():
            stale.unlink()
    started = time.monotonic()
    completed = subprocess.run(compiler_cmd, capture_output=True, text=True, cwd=str(work))
    seconds = time.monotonic() - started
    if completed.returncode != 0:
        tail = (completed.stderr or completed.stdout or "").strip().splitlines()[-8:]
        raise Failure(f"compiler exited {completed.returncode}: " + " / ".join(tail))
    if not catalogue.is_file() or not report.is_file():
        raise Failure(f"compiler exited 0 but did not write {catalogue.name}/{report.name}")
    return catalogue, report, seconds


def validate_report(report: dict, manifest: dict) -> None:
    for key in ("file_count", "source_count", "failed_file_count", "invalid_source_count",
                "node_count", "placement_count", "duplicate_occurrence_count", "size_bytes"):
        if key not in report:
            raise Refusal(f"build report declares no {key}")
    if report["file_count"] != manifest["fileCount"]:
        raise Refusal(
            f"build report compiled {report['file_count']} files, but the manifest declares "
            f"fileCount {manifest['fileCount']}"
        )
    if report["source_count"] != manifest["sourceCount"]:
        raise Refusal(
            f"build report found {report['source_count']} sources, but the manifest declares "
            f"sourceCount {manifest['sourceCount']}"
        )


# --------------------------------------------------------------------------------------------------
# 5. The bundled descriptor


def descriptor_from(manifest: dict, entries: list[dict], catalogue: dict, manifest_url: str,
        manifest_sha: str) -> dict:
    """The public manifest's shape, its inventory verbatim, plus the compiled catalogue's own entry.

    Not a copy of the public manifest: `derivedFrom` states what the inventory was read from (with the real
    sha256 of the bytes fetched), `role` marks which entries prove the inputs and which proves the derived
    artefact, and the catalogue entry carries the compiled file's own size and checksum.
    """
    files = [{"role": OPML_ROLE, "path": e["path"], "bytes": e["bytes"], "sha256": e["sha256"]}
        for e in entries]
    files.append({"role": CATALOGUE_ROLE, "path": SQLITE_NAME, "bytes": catalogue["bytes"],
        "sha256": catalogue["sha256"]})
    return {
        "revision": manifest["revision"],
        "schemaVersion": manifest["schemaVersion"],
        "generatedAt": manifest.get("generatedAt"),
        "sourceCount": manifest["sourceCount"],
        "fileCount": len(files),
        "derivedFrom": {
            "manifest": manifest_url,
            "manifestSha256": manifest_sha,
            "revision": manifest["revision"],
            "opmlEntries": len(entries),
        },
        "files": files,
    }


def validate_descriptor(descriptor: dict) -> None:
    """Self-check against `CatalogManifest.validate(_:)`, so the staged pair is one the app can accept."""
    if descriptor["fileCount"] != len(descriptor["files"]):
        raise Refusal("descriptor fileCount does not match its own files")
    paths = [f["path"] for f in descriptor["files"]]
    if len(set(paths)) != len(paths):
        raise Refusal("descriptor repeats a path")
    for entry in descriptor["files"]:
        if not is_safe_relative_path(entry["path"]) or entry["bytes"] <= 0 or not is_sha256(entry["sha256"]):
            raise Refusal(f"descriptor entry is not valid: {entry!r}")
        if entry.get("role") not in (OPML_ROLE, CATALOGUE_ROLE):
            raise Refusal(f"descriptor entry carries no known role: {entry!r}")
        if (entry["role"] == CATALOGUE_ROLE) != entry["path"].lower().endswith(".sqlite"):
            raise Refusal(f"descriptor role disagrees with the path it marks: {entry!r}")
    # `CatalogManifest.catalogueEntry` finds the catalogue by its path; both predicates must name the same entry.
    catalogues = [f for f in descriptor["files"] if f["role"] == CATALOGUE_ROLE]
    sqlites = [f for f in descriptor["files"] if f["path"].lower().endswith(".sqlite")]
    if len(catalogues) != 1 or [f["path"] for f in catalogues] != [f["path"] for f in sqlites]:
        raise Refusal("descriptor must name exactly one compiled catalogue")
    derived = descriptor.get("derivedFrom")
    opmls = [f for f in descriptor["files"] if f["role"] == OPML_ROLE]
    if not isinstance(derived, dict) or derived.get("opmlEntries") != len(opmls):
        raise Refusal("descriptor's derivedFrom.opmlEntries does not match its OPML entries")
    if derived.get("revision") != descriptor["revision"] or not is_sha256(derived.get("manifestSha256")):
        raise Refusal(f"descriptor's derivedFrom block is not valid: {derived!r}")


# --------------------------------------------------------------------------------------------------
# Run


def run(args: argparse.Namespace) -> int:
    staging = args.staging_root.expanduser().resolve()
    payload_root = staging / PAYLOAD_DIR
    base = args.public_base.rstrip("/")

    step(1, "public manifest (pinned)")
    manifest_url = f"{base}/manifest.json"
    say(f"       {manifest_url}")
    raw_manifest = http_get(manifest_url)
    try:
        manifest = json.loads(raw_manifest)
    except ValueError as error:
        raise Refusal(f"{manifest_url} is not JSON: {error}") from None
    manifest = validate_manifest(manifest, raw_manifest, manifest_url, args.revision)
    entries = manifest["files"]
    manifest_sha = sha256_bytes(raw_manifest)

    step(2, "OPML inventory")
    tally = verify_payload(entries, payload_root, base, args.refetch)

    step(3, "compile (legacy V1 compiler)")
    identity = compiler_identity(args.compiler)
    feeds_root = payload_root / FEEDS_PREFIX.rstrip("/")
    work = staging / ".work"
    command = compiler_command(args.compiler, feeds_root, work / SQLITE_NAME, work / REPORT_NAME)
    say(f"       {' '.join(command)}")
    state_path = staging / STATE_NAME
    previous = {}
    if state_path.is_file():
        try:
            previous = json.loads(state_path.read_text("utf-8"))
        except (OSError, ValueError):
            previous = {}
    state = None if args.rebuild else reuse_state(
        staging, previous, identity, manifest["revision"], manifest_sha, tally["tree_sha256"])

    if state is not None:
        say(f"       reused: build inputs unchanged (tree identity {tally['tree_sha256']}, "
            f"compiler sha256 {identity['sha256']})")
        say(f"       reused: {SQLITE_NAME} compiled at {state.get('builtAt')} — not re-run, so its checksum "
            f"is unchanged")
        report = json.loads((staging / REPORT_NAME).read_text("utf-8"))
        build_seconds = state.get("buildSeconds")
        built_at = state.get("builtAt")
    else:
        catalogue, report_path, build_seconds = build(command, work)
        report = json.loads(report_path.read_text("utf-8"))
        validate_report(report, manifest)
        os.replace(catalogue, staging / SQLITE_NAME)
        os.replace(report_path, staging / REPORT_NAME)
        built_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        say(f"       compiled in {build_seconds:.1f}s, moved into place only after the report agreed")

    step(4, "build report")
    validate_report(report, manifest)
    for line in json.dumps(report, indent=2, sort_keys=True).splitlines():
        say(f"       {line}")
    say(f"       file_count {report['file_count']} == manifest fileCount {manifest['fileCount']}; "
        f"source_count {report['source_count']} == manifest sourceCount {manifest['sourceCount']}")

    step(5, "bundled descriptor")
    catalogue_path = staging / SQLITE_NAME
    if not catalogue_path.is_file():
        raise Failure(f"{catalogue_path} is missing after the build step")
    catalogue = {"path": SQLITE_NAME, "bytes": catalogue_path.stat().st_size,
        "sha256": sha256_file(catalogue_path)}
    descriptor = descriptor_from(manifest, entries, catalogue, manifest_url, manifest_sha)
    validate_descriptor(descriptor)
    descriptor_path = staging / DESCRIPTOR_NAME
    descriptor_bytes = (json.dumps(descriptor, indent=2) + "\n").encode("utf-8")
    unchanged = descriptor_path.is_file() and descriptor_path.read_bytes() == descriptor_bytes
    write_atomic(descriptor_path, descriptor_bytes)
    say(f"       {descriptor_path}{' (unchanged)' if unchanged else ''}")
    say(f"       not a copy of the public manifest: the {descriptor['derivedFrom']['opmlEntries']} "
        "role=opml entries prove the inputs, the role=catalogue entry proves the artefact derived from them")
    say(f"       derivedFrom: {json.dumps(descriptor['derivedFrom'])}")
    say(f"       totals: fileCount {descriptor['fileCount']} "
        f"({len(entries)} OPML + 1 catalogue), sourceCount {descriptor['sourceCount']}")
    say(f"       totals: {tally['bytes']} OPML bytes + {catalogue['bytes']} catalogue bytes = "
        f"{tally['bytes'] + catalogue['bytes']} bytes")
    say(f"       first OPML entry: {json.dumps(descriptor['files'][0])}")
    say(f"       catalogue entry:  {json.dumps(descriptor['files'][-1])}")

    step(6, "staging")
    report_identity = {"bytes": (staging / REPORT_NAME).stat().st_size,
        "sha256": sha256_file(staging / REPORT_NAME)}
    descriptor_identity = {"bytes": len(descriptor_bytes), "sha256": sha256_bytes(descriptor_bytes)}
    new_state = {
        "revision": manifest["revision"],
        "manifestSha256": manifest_sha,
        "feedTreeSha256": tally["tree_sha256"],
        "compiler": identity,
        "builtAt": built_at,
        "buildSeconds": build_seconds,
        # What a recompile is gated on: the compiler's own outputs. Everything else here is recorded, not gating.
        "gate": list(BUILD_ARTIFACTS),
        "artifacts": {
            SQLITE_NAME: {"bytes": catalogue["bytes"], "sha256": catalogue["sha256"]},
            REPORT_NAME: report_identity,
            DESCRIPTOR_NAME: descriptor_identity,
        },
    }
    write_json(state_path, new_state)

    provenance = {
        "publicBase": base,
        "manifest": {"url": manifest_url, "bytes": len(raw_manifest), "sha256": manifest_sha,
            "revision": manifest["revision"], "schemaVersion": manifest["schemaVersion"],
            "generatedAt": manifest.get("generatedAt"), "sourceCount": manifest["sourceCount"],
            "fileCount": manifest["fileCount"]},
        "payload": {"root": str(payload_root), "opmlCount": len(entries), "bytes": tally["bytes"],
            "treeSha256": tally["tree_sha256"], "downloadedThisRun": tally["downloaded"],
            "reusedThisRun": tally["reused"]},
        "compiler": {**identity, "command": command, "reused": state is not None,
            "seconds": build_seconds, "builtAt": built_at},
        "buildReport": report,
        "descriptor": {"path": str(descriptor_path), "bytes": descriptor_identity["bytes"],
            "sha256": descriptor_identity["sha256"], "fileCount": descriptor["fileCount"],
            "sourceCount": descriptor["sourceCount"],
            "generatedAtSource": "public manifest.json (carried, not invented)",
            "derivedFrom": descriptor["derivedFrom"],
            "roles": f"{descriptor['derivedFrom']['opmlEntries']} {OPML_ROLE} entries (the inputs) + "
                f"1 {CATALOGUE_ROLE} entry (the derived artefact)",
            "catalogue": catalogue},
        "provenance": "every value above is read from the artefacts this run fetched, verified or built; the "
            "descriptor is not a copy of the public manifest — it repeats the published inventory and adds the "
            "compiled catalogue the channel does not publish",
    }
    write_json(staging / PROVENANCE_NAME, provenance)

    say(f"       payload     {payload_root}  ({len(entries)} OPML, paths exactly as declared)")
    say(f"       catalogue   {catalogue_path}  ({catalogue['bytes']} bytes, sha256 {catalogue['sha256']})")
    say(f"       descriptor  {descriptor_path}  ({descriptor['fileCount']} entries)")
    say(f"       report      {staging / REPORT_NAME}")
    say(f"       provenance  {staging / PROVENANCE_NAME}")
    say(f"       state       {state_path}")
    say()
    say("       This build wrote nothing outside its staging tree and nothing into the Xcode project.")
    say("       The descriptor and the catalogue it declares are one pair: installing one without the other "
        "fails verification.")
    say("       The release asset currently in FeedMineApp/FeedMineApp/Resources (117940224 bytes, "
        "sha256 c2ae483a7525fd2b6797855149eb6fb312abbed788549a90a7754121eb5c8629) is *not* described by this "
        "descriptor.")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--revision", type=int, default=DEFAULT_REVISION,
        help=f"the published revision this bootstrap is pinned to (default {DEFAULT_REVISION})")
    parser.add_argument("--staging-root", type=Path, default=DEFAULT_STAGING,
        help=f"where the payload, catalogue, descriptor and provenance are written (default {DEFAULT_STAGING})")
    parser.add_argument("--public-base", default=DEFAULT_PUBLIC_BASE,
        help="base URL of the public channel (manifest.json and the declared paths resolve against it)")
    parser.add_argument("--compiler", type=Path, default=DEFAULT_COMPILER,
        help=f"the legacy V1 compiler (default {DEFAULT_COMPILER})")
    parser.add_argument("--refetch", action="store_true",
        help="download every OPML again instead of reusing what is already verified on disk")
    parser.add_argument("--rebuild", action="store_true",
        help="re-run the compiler even when its inputs and outputs are unchanged")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    try:
        return run(parse_args(sys.argv[1:] if argv is None else argv))
    except Refusal as refusal:
        say()
        say(f"REFUSED: {refusal}")
        return 2
    except Failure as failure:
        say()
        say(f"ERROR: {failure}")
        return 1
    except KeyboardInterrupt:
        say()
        say("ERROR: interrupted — the staging tree was not modified by the interrupted step")
        return 1


if __name__ == "__main__":
    sys.exit(main())
