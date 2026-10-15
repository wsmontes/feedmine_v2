"""P0C positive/negative fixtures: hermetic public manifest, compiler and archive bytes."""
from __future__ import annotations

import argparse
import copy
import json
import plistlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import bootstrap_catalog as catalog
import verify_catalog_release as release


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="p0c-fixture-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.resources = self.root / "Resources"
        self.staging = self.root / "staging"
        self.resources.mkdir()
        self.staging.mkdir()
        self.compiler_dir = self.root / "legacy" / "scripts"
        self.compiler_dir.mkdir(parents=True)
        self.compiler = self.compiler_dir / "build_catalog.py"
        self.dependency = self.compiler_dir / "catalog_identity.py"
        self.compiler.write_text("# simulated V1 compiler source\n", encoding="utf-8")
        self.dependency.write_text("# simulated V1 dependency\n", encoding="utf-8")
        self.identity = catalog.compiler_identity(
            self.compiler, catalog.sha256_file(self.compiler),
            catalog.sha256_file(self.dependency))
        self.opml = b'<opml version="2.0"><body><outline type="rss" xmlUrl="https://example.org/rss"/></body></opml>'
        self.entry = {"path": "Feeds/A.opml", "bytes": len(self.opml),
                      "sha256": catalog.sha256_bytes(self.opml)}
        self.manifest = {"revision": 11, "schemaVersion": 1, "generatedAt": "2026-10-15T00:00:00Z",
                         "fileCount": 1, "sourceCount": 1, "files": [self.entry]}
        self.manifest_path = self.root / "manifest.json"
        self.write_manifest()
        (self.staging / "payload" / "Feeds").mkdir(parents=True)
        self.opml_path = self.staging / "payload" / self.entry["path"]
        self.opml_path.write_bytes(self.opml)
        self.sqlite = b"SQLite exact binary fixture"
        self.report = {"file_count": 1, "source_count": 1, "failed_file_count": 0,
                       "invalid_source_count": 0, "node_count": 1, "placement_count": 1,
                       "duplicate_occurrence_count": 0, "size_bytes": len(self.sqlite)}
        catalog.write_json(self.staging / "build-report.json", self.report)
        for directory in (self.staging, self.resources):
            (directory / "catalog.sqlite").write_bytes(self.sqlite)
        self.descriptor = catalog.descriptor_from(
            self.manifest, [self.entry], {"bytes": len(self.sqlite),
            "sha256": catalog.sha256_bytes(self.sqlite)},
            release.PUBLIC_URL, catalog.sha256_file(self.manifest_path))
        for directory in (self.staging, self.resources):
            catalog.write_json(directory / "catalog.manifest.json", self.descriptor)
        command = catalog.compiler_command(self.compiler, self.staging / "payload" / "Feeds",
                                           self.staging / ".work" / "catalog.sqlite",
                                           self.staging / ".work" / "build-report.json")
        self.provenance = {
            "manifest": {"url": release.PUBLIC_URL, "revision": 11,
                         "sha256": catalog.sha256_file(self.manifest_path)},
            "payload": {"treeSha256": catalog.tree_identity([self.entry])},
            "compiler": {**self.identity, "command": command},
            "buildReport": self.report,
            "descriptor": {"sha256": catalog.sha256_file(self.resources / "catalog.manifest.json")},
        }
        self.state = {
            "manifestSha256": catalog.sha256_file(self.manifest_path),
            "feedTreeSha256": catalog.tree_identity([self.entry]), "revision": 11,
            "compiler": self.identity,
            "artifacts": {name: self.file_id(self.staging / name)
                          for name in ("catalog.sqlite", "catalog.manifest.json", "build-report.json")},
        }
        self.save_evidence()

    @staticmethod
    def file_id(path):
        return {"bytes": path.stat().st_size, "sha256": catalog.sha256_file(path)}

    def write_manifest(self):
        catalog.write_json(self.manifest_path, self.manifest)

    def save_evidence(self):
        catalog.write_json(self.staging / "provenance.json", self.provenance)
        catalog.write_json(self.staging / "state.json", self.state)

    def chain(self):
        return release.verify_chain(self.resources, self.staging, self.manifest_path)

    def refuse(self, message):
        with self.assertRaisesRegex(release.Refused, message):
            self.chain()

    def test_valid_chain_and_idempotent_identity(self):
        first = self.chain()
        self.assertEqual(first["publicManifest"]["revision"], 11)
        self.assertEqual(first["publicManifest"]["sha256"], catalog.sha256_file(self.manifest_path))
        self.assertEqual(first, self.chain())

    def test_bootstrap_reuses_exact_verified_compiler_outputs(self):
        reused = catalog.reuse_state(
            self.staging, self.state, self.identity, 11,
            catalog.sha256_file(self.manifest_path), catalog.tree_identity([self.entry]))
        self.assertIsNotNone(reused, "unchanged compile should reuse SQLite bytes")
        (self.staging / "build-report.json").write_text("{}")
        self.assertIsNone(catalog.reuse_state(
            self.staging, self.state, self.identity, 11,
            catalog.sha256_file(self.manifest_path), catalog.tree_identity([self.entry])))

    def test_bootstrap_refuses_wrong_compiler_sha_and_missing_dependency(self):
        with self.assertRaises(catalog.Refusal):
            catalog.compiler_identity(self.compiler, "0" * 64,
                                      catalog.sha256_file(self.dependency))
        self.dependency.unlink()
        with self.assertRaises(catalog.Failure):
            catalog.compiler_identity(self.compiler, catalog.sha256_file(self.compiler),
                                      "0" * 64)

    def test_manifest_pinning_is_optional_but_strict(self):
        raw = self.manifest_path.read_bytes()
        self.assertEqual(catalog.validate_manifest(self.manifest, raw, "fixture", None)["revision"], 11)
        with self.assertRaisesRegex(catalog.Refusal, "published revision moved"):
            catalog.validate_manifest(self.manifest, raw, "fixture", 10)

    def test_sqlite_absent(self):
        (self.resources / "catalog.sqlite").unlink()
        self.refuse("missing")

    def test_descriptor_absent(self):
        (self.resources / "catalog.manifest.json").unlink()
        self.refuse("missing")

    def test_sqlite_byte_mutation(self):
        (self.resources / "catalog.sqlite").write_bytes(b"SQLite altered fixture")
        self.refuse("resource SQLite")

    def test_sqlite_size_mutation(self):
        (self.resources / "catalog.sqlite").write_bytes(self.sqlite + b"x")
        self.refuse("resource SQLite")

    def test_descriptor_mutation(self):
        descriptor = copy.deepcopy(self.descriptor)
        descriptor["files"][-1]["sha256"] = "0" * 64
        catalog.write_json(self.resources / "catalog.manifest.json", descriptor)
        self.refuse("resource SQLite")

    def test_full_inventory_detects_last_opml_change(self):
        descriptor = copy.deepcopy(self.descriptor)
        descriptor["files"][0]["sha256"] = "0" * 64
        catalog.write_json(self.resources / "catalog.manifest.json", descriptor)
        self.refuse("complete public OPML")

    def test_public_manifest_changed_at_same_revision(self):
        self.manifest["generatedAt"] = "2026-10-16T00:00:00Z"
        self.write_manifest()
        self.refuse("public generatedAt differs")

    def test_public_revision_newer_than_bundle(self):
        self.manifest["revision"] = 12
        self.write_manifest()
        self.refuse("bundled revision")

    def test_public_inventory_diverges(self):
        self.manifest["files"][0]["sha256"] = "a" * 64
        self.write_manifest()
        self.refuse("manifestSha256 mismatch")

    def test_opml_changed_without_manifest(self):
        self.opml_path.write_bytes(self.opml + b" ")
        self.refuse("OPML absent or changed")

    def test_compiler_missing(self):
        self.compiler.unlink()
        self.refuse("compiler unverified")

    def test_compiler_dependency_drift(self):
        self.dependency.write_bytes(b"bad")
        self.refuse("compiler unverified")

    def test_compiler_report_mismatch(self):
        report = dict(self.report, source_count=2)
        catalog.write_json(self.staging / "build-report.json", report)
        self.refuse("incompatible compiler report")

    def test_public_revision_change_between_preflight_and_archive_refused(self):
        evidence = self.root / "evidence"
        arguments = argparse.Namespace(
            command="preflight", resources=self.resources, staging=self.staging,
            public_manifest=self.manifest_path, evidence_dir=evidence,
            head="c" * 40, archive=None, version=None, build=None)
        release.run(arguments)
        self.assertTrue((evidence / "pd10-p0c-preflight.json").is_file())
        self.manifest["revision"] = 12
        self.write_manifest()
        arguments.command = "archive"
        arguments.archive = self.root / "fake.xcarchive"
        arguments.version, arguments.build = "1.0", "46"
        with self.assertRaisesRegex(release.Refused, "bundled revision"):
            release.run(arguments)
        self.assertFalse(list(evidence.glob("pd10-p0c-1.0-build-46-*.json")))

    def test_archive_exact_and_corruption(self):
        chain = self.chain()
        archive = self.root / "x.xcarchive"
        app = archive / "Products/Applications/FeedMine.app"
        app.mkdir(parents=True)
        for name in ("catalog.sqlite", "catalog.manifest.json"):
            shutil.copy2(self.resources / name, app / name)
        full_sha = "c" * 40
        info = {"CFBundleIdentifier": "com.feedmine.app", "CFBundleShortVersionString": "1.0",
                "CFBundleVersion": "46", "FeedmineGitSHA": full_sha[:7]}
        with (app / "Info.plist").open("wb") as target:
            plistlib.dump(info, target)
        result = release.verify_archive(archive, self.resources, chain, full_sha, "1.0", "46")
        self.assertEqual(result["gitSHA"], full_sha[:7])
        (app / "catalog.sqlite").write_bytes(b"tampered SQLite")
        with self.assertRaisesRegex(release.Refused, "archive SQLite differs"):
            release.verify_archive(archive, self.resources, chain, full_sha, "1.0", "46")
        shutil.copy2(self.resources / "catalog.sqlite", app / "catalog.sqlite")
        (app / "catalog.manifest.json").write_bytes(b"{}")
        with self.assertRaisesRegex(release.Refused, "archive descriptor differs"):
            release.verify_archive(archive, self.resources, chain, full_sha, "1.0", "46")

    @unittest.skipUnless(shutil.which("sqlite3"), "requires system sqlite3 CLI (Mac)")
    def test_benchmark_marker_is_rejected_by_canonical_verifier(self):
        fixture = self.root / "verification"
        resources = fixture / "FeedMineApp/FeedMineApp/Resources"
        scripts = fixture / "scripts"
        app = fixture / "FeedMine.app"
        for directory in (resources, scripts, app):
            directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "scripts/verify_product_catalogue.sh",
                     scripts / "verify_product_catalogue.sh")
        db = app / "catalog.sqlite"
        connection = sqlite3.connect(db)
        connection.execute("CREATE TABLE catalog_metadata (key TEXT PRIMARY KEY, value TEXT)")
        connection.executemany("INSERT INTO catalog_metadata VALUES (?, ?)", [
            ("schema_version", "2"), ("catalog_version", "1791736083355950"),
            ("source_count", "1"), ("bench_corpus", "injected"),
        ])
        connection.commit()
        connection.close()
        descriptor = catalog.descriptor_from(
            self.manifest, [self.entry], self.file_id(db),
            release.PUBLIC_URL, catalog.sha256_file(self.manifest_path))
        catalog.write_json(resources / "catalog.manifest.json", descriptor)
        catalog.write_json(app / "catalog.manifest.json", descriptor)
        completed = subprocess.run(["bash", str(scripts / "verify_product_catalogue.sh"), str(app)],
                                   text=True, capture_output=True)
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("benchmark corpus", completed.stdout + completed.stderr)

    def test_archive_git_pairing(self):
        chain = self.chain()
        app = self.root / "a.xcarchive" / "Products/Applications/FeedMine.app"
        app.mkdir(parents=True)
        for name in ("catalog.sqlite", "catalog.manifest.json"):
            shutil.copy2(self.resources / name, app / name)
        with (app / "Info.plist").open("wb") as target:
            plistlib.dump({"CFBundleIdentifier": "com.feedmine.app",
                "CFBundleShortVersionString": "1.0", "CFBundleVersion": "46",
                "FeedmineGitSHA": "fffffff"}, target)
        with self.assertRaisesRegex(release.Refused, "archive Git SHA"):
            release.verify_archive(app.parents[2], self.resources, chain, "c" * 40, "1.0", "46")


if __name__ == "__main__":
    unittest.main()
