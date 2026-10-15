#!/usr/bin/env python3
"""Prepare a new public feed-repository snapshot without commits, pushes or app-resource writes.

The existing V1 compiler is the only source of a *computed* sourceCount. Manifest
publication is separate from the app's release/bootstrap. By default this tool
is a read-only inspection; --apply updates only the provided public checkout.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import bootstrap_catalog as catalog


class PublishRefusal(Exception):
    pass


def need(ok: bool, message: str) -> None:
    if not ok:
        raise PublishRefusal(message)


def inventory(root: Path) -> list[dict]:
    feeds = root / "Feeds"
    need(feeds.is_dir(), f"missing Feeds directory in {root}")
    entries = []
    for path in sorted(feeds.rglob("*")):
        if path.is_dir():
            continue
        need(path.is_file() and not path.is_symlink(), f"unsafe or symlinked feed path: {path}")
        relative = path.relative_to(root).as_posix()
        need(relative.endswith(".opml") and catalog.is_safe_relative_path(relative),
             f"unexpected non-OPML input: {relative}")
        data = path.read_bytes()
        need(bool(data), f"empty OPML: {relative}")
        try:
            element = ET.fromstring(data)
        except ET.ParseError as error:
            raise PublishRefusal(f"invalid OPML {relative}: {error}") from error
        need(element.tag.lower() == "opml", f"not an OPML document: {relative}")
        entries.append({"path": relative, "bytes": len(data), "sha256": catalog.sha256_bytes(data)})
    need(entries, f"no OPML files in {feeds}")
    return entries


def load_existing(destination: Path) -> tuple[dict | None, list[dict]]:
    path = destination / "manifest.json"
    if not path.exists():
        need(not (destination / "Feeds").exists(), "destination has Feeds but no manifest; refuse")
        return None, []
    raw = path.read_bytes()
    try:
        manifest = catalog.validate_manifest(json.loads(raw), raw, str(path), None)
    except (ValueError, catalog.Refusal) as error:
        raise PublishRefusal(f"invalid destination public manifest: {error}") from error
    need(all(str(f["path"]).endswith(".opml") for f in manifest["files"]),
         "public manifest contains non-OPML entries")
    actual = inventory(destination)
    need(sorted(actual, key=lambda x: x["path"]) ==
         sorted(manifest["files"], key=lambda x: x["path"]),
         "destination Feeds bytes/inventory differ from published manifest; repair independently")
    return manifest, manifest["files"]


def run(args: argparse.Namespace) -> int:
    source, destination = args.source.resolve(), args.destination.resolve()
    need(source != destination, "source and destination must be different checkouts")
    need(not (source in destination.parents or destination in source.parents),
         "source and destination directories must not be nested")
    need(destination.is_dir(), f"destination checkout missing: {destination}")
    entries = inventory(source)
    previous, old_entries = load_existing(destination)
    old_by_path = {e["path"]: e for e in old_entries}
    new_by_path = {e["path"]: e for e in entries}
    added = sorted(new_by_path.keys() - old_by_path.keys())
    removed = sorted(old_by_path.keys() - new_by_path.keys())
    changed = sorted(p for p in old_by_path.keys() & new_by_path.keys()
                     if old_by_path[p] != new_by_path[p])
    dirty = bool(added or removed or changed)
    prior_revision = previous["revision"] if previous else 0
    if dirty:
        need(args.revision is not None and args.revision > prior_revision,
             f"catalogue changed; revision must increase beyond {prior_revision} (same revision forbidden)")
    else:
        need(previous is not None, "new catalogue must have a first revision")
        need(args.revision is None or args.revision == prior_revision,
             "no byte changes: refuse unrelated revision change")
        print(f"UNCHANGED: public revision {prior_revision}; no manifest or files rewritten")
        return 0
    need(args.revision > 0, "revision must be positive")

    need(args.compiler and args.compiler_sha256 and args.identity_sha256,
         "changed inventory requires --compiler, --compiler-sha256 and --identity-sha256")
    try:
        compiler = catalog.compiler_identity(args.compiler, args.compiler_sha256, args.identity_sha256)
    except (catalog.Refusal, catalog.Failure) as error:
        raise PublishRefusal(f"compiler unverified: {error}") from error
    with tempfile.TemporaryDirectory(prefix="feedmine-publish-") as temporary:
        workspace = Path(temporary)
        # Compiler owns source normalization/dedupe; no publisher-side approximation.
        shutil.copytree(source / "Feeds", workspace / "Feeds")
        command = catalog.compiler_command(Path(compiler["path"]), workspace / "Feeds",
                                           workspace / catalog.SQLITE_NAME,
                                           workspace / catalog.REPORT_NAME)
        try:
            _, report_path, _ = catalog.build(command, workspace)
        except catalog.Failure as error:
            raise PublishRefusal(str(error)) from error
        report = json.loads(report_path.read_text("utf-8"))
        need(report.get("file_count") == len(entries),
             f"compiler file_count {report.get('file_count')} != inventory {len(entries)}")
        need(isinstance(report.get("source_count"), int) and report["source_count"] > 0,
             "compiler returned no valid source_count")
        manifest = {
            "revision": args.revision, "schemaVersion": catalog.SUPPORTED_MANIFEST_SCHEMA,
            "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "sourceCount": report["source_count"], "fileCount": len(entries),
            "files": entries,
        }
        raw = (json.dumps(manifest, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
        try:
            catalog.validate_manifest(manifest, raw, str(destination / "manifest.json"), args.revision)
            catalog.validate_report(report, manifest)
        except catalog.Refusal as error:
            raise PublishRefusal(str(error)) from error
        print(f"revision {prior_revision} -> {args.revision}, {len(entries)} OPML, "
              f"{report['source_count']} compiled sources")
        print(f"added={len(added)} removed={len(removed)} changed={len(changed)}")
        for kind, paths in (("ADD", added), ("REMOVE", removed), ("CHANGE", changed)):
            for path in paths:
                print(f"  {kind} {path}")
        print(f"public manifest SHA-256 (prepared): {catalog.sha256_bytes(raw)}")
        print(f"compiler SHA-256: {compiler['sha256']}; dependency: {compiler['dependency']['sha256']}")
        if not args.apply:
            print("DRY RUN: public checkout and app Resources unchanged; use --apply explicitly")
            return 0
        # Only a local public checkout is modified; never a Git ref or an app resource.
        for entry in entries:
            target = destination / entry["path"]
            if target.is_symlink():
                raise PublishRefusal(f"refuse overwriting symlink: {target}")
            if not catalog.file_matches(target, entry["bytes"], entry["sha256"]):
                catalog.write_atomic(target, (source / entry["path"]).read_bytes())
        for relative in removed:
            path = destination / relative
            need(path.is_file() and not path.is_symlink(), f"cannot remove old OPML safely: {path}")
            path.unlink()
        # Manifest goes last; validate the complete new tree before publishing its declaration.
        need(inventory(destination) == entries, "destination inventory mismatch after local copy")
        catalog.write_atomic(destination / "manifest.json", raw)
        print(f"PREPARED: {destination}/manifest.json; inspect/validate/commit/push separately")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="editorial checkout containing Feeds/")
    parser.add_argument("--destination", required=True, type=Path,
                        help="existing local public feed-repository checkout")
    parser.add_argument("--revision", type=int, help="new monotonic revision (mandatory if bytes change)")
    parser.add_argument("--compiler", type=Path, help="explicit legacy V1 build_catalog.py")
    parser.add_argument("--compiler-sha256", help="expected SHA-256 of build_catalog.py")
    parser.add_argument("--identity-sha256", help="expected SHA-256 of adjacent catalog_identity.py")
    parser.add_argument("--apply", action="store_true", help="write to local destination (never commit/push)")
    args = parser.parse_args()
    try:
        return run(args)
    except (PublishRefusal, OSError, ValueError, TypeError, KeyError) as error:
        print(f"REFUSED P0C publish: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
