"""Release pre-archive failures must never reach xcodebuild or tag creation.

The fixture owns the layout `scripts/release-testflight.sh` demands, including both export-options
plists (the export-only one with destination=export). Two cases assert that the fixture still is
that contract and that the script refuses to export when the export-only plist is missing or would
upload — otherwise a green suite could mean a stale tree rather than working refusals.
"""
from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="p0c-release-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "scripts").mkdir()
        (self.root / "FeedMineApp/FeedMineApp/Resources").mkdir(parents=True)
        # A syntactically valid plist is required: release-testflight reads
        # CFBundleVersion/CFBundleShortVersionString *before* any preflight.
        with (self.root / "FeedMineApp/FeedMineApp/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleVersion": "46", "CFBundleShortVersionString": "1.0"}, stream)
        shutil.copy2(ROOT / "scripts/release-testflight.sh", self.root / "scripts/release-testflight.sh")
        shutil.copy2(ROOT / "scripts/verify_product_catalogue.sh", self.root / "scripts/verify_product_catalogue.sh")
        # release/export-without-upload made the export-options plists mandatory: the script refuses
        # to run without scripts/ExportOptions.plist, and `--no-upload` additionally requires
        # scripts/ExportOptions-export-only.plist to say destination=export. This fixture shipped the
        # older layout (no plists at all), so every case aborted at "plist de export ausente" before
        # reaching the failure under test. It now builds the layout the script actually demands.
        with (self.root / "scripts/ExportOptions.plist").open("wb") as stream:
            plistlib.dump({"method": "app-store-connect", "destination": "upload",
                           "teamID": "TESTTEAM"}, stream)
        shutil.copy2(ROOT / "scripts/ExportOptions-export-only.plist",
                     self.root / "scripts/ExportOptions-export-only.plist")
        (self.root / "scripts/release-testflight.sh").chmod(0o755)
        (self.root / "scripts/verify_product_catalogue.sh").chmod(0o755)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "xcodebuild").write_text(
            '#!/bin/sh\necho "ARCHIVE_OR_UPLOAD_CALLED" >> "$P0C_MARKER"\nexit 0\n')
        (self.bin / "xcodebuild").chmod(0o755)
        self.marker = self.root / "called.log"
        self.git("init", "-q")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "P0C Test")
        self.commit()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True).strip()

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def run_script(self, *flags):
        env = dict(os.environ)
        for key in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
            env.pop(key, None)
        env["PATH"] = str(self.bin) + os.pathsep + env.get("PATH", "")
        env["P0C_MARKER"] = str(self.marker)
        return subprocess.run(
            ["bash", str(self.root / "scripts/release-testflight.sh"), *(flags or ("--dry-run",))],
            cwd=self.root, capture_output=True, text=True, env=env)

    def release(self, *flags):
        """Run a release expected to abort before xcodebuild and before any tag."""
        result = self.run_script(*flags)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists(), "xcodebuild archive/upload must not run")
        self.assertEqual(self.git("tag", "--list"), "", "failed release must not create tag")
        self.assertNotIn("ASC_KEY_ID ausente", result.stdout + result.stderr)
        return result.stdout + result.stderr

    def test_fixture_is_the_layout_the_script_mandates(self):
        """Control: the fixture carries both plists and the export-only one says destination=export."""
        export_only = self.root / "scripts/ExportOptions-export-only.plist"
        self.assertTrue((self.root / "scripts/ExportOptions.plist").is_file())
        self.assertTrue(export_only.is_file())
        with export_only.open("rb") as stream:
            self.assertEqual(plistlib.load(stream)["destination"], "export")

    def test_no_upload_resolves_the_export_only_plist(self):
        result = self.run_script("--print-export-options", "--no-upload")
        log = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, log)
        self.assertIn("EXPORT_OPTS=scripts/ExportOptions-export-only.plist", log)
        self.assertIn("destination=export", log)
        self.assertIn("upload=no", log)
        self.assertFalse(self.marker.exists(), "xcodebuild archive/upload must not run")

    def test_no_upload_refuses_missing_export_only_plist(self):
        (self.root / "scripts/ExportOptions-export-only.plist").unlink()
        self.commit()
        log = self.release("--print-export-options", "--no-upload")
        self.assertIn("scripts/ExportOptions-export-only.plist", log)
        self.assertIn("não existe", log)

    def test_no_upload_refuses_export_only_plist_that_uploads(self):
        shutil.copy2(self.root / "scripts/ExportOptions.plist",
                     self.root / "scripts/ExportOptions-export-only.plist")
        self.commit()
        log = self.release("--print-export-options", "--no-upload")
        self.assertIn("destination=upload", log)
        self.assertIn("destination precisa ser 'export'", log)

    def test_missing_sqlite_stops_before_archive(self):
        log = self.release()
        self.assertIn("catalog.sqlite + catalog.manifest.json", log)

    def test_missing_descriptor_stops_before_archive(self):
        (self.root / "FeedMineApp/FeedMineApp/Resources/catalog.sqlite").write_bytes(b"SQLite")
        self.commit()
        log = self.release()
        self.assertIn("catalog.sqlite + catalog.manifest.json", log)

    @unittest.skipUnless(Path("/usr/libexec/PlistBuddy").exists(), "requires macOS PlistBuddy")
    def test_archive_verifier_refusal_prevents_export_and_tag(self):
        """Simulate successful preflight + archive, then fail the final byte gate."""
        resources = self.root / "FeedMineApp/FeedMineApp/Resources"
        (resources / "catalog.sqlite").write_bytes(b"fake valid preflight bytes")
        (resources / "catalog.manifest.json").write_text('{"revision": 11}')
        with (self.root / "FeedMineApp/FeedMineApp/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleVersion": "46", "CFBundleShortVersionString": "1.0"}, stream)
        with (self.root / "mock-archive.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "com.feedmine.app",
                           "CFBundleVersion": "46", "CFBundleShortVersionString": "1.0",
                           "FeedmineGitSHA": "placeholder"}, stream)
        (self.root / "scripts/verify_product_catalogue.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.root / "scripts/verify_catalog_release.py").write_text(
            'import sys\n'
            'if sys.argv[1] == "archive":\n'
            '  print("REFUSED: simulated archive byte drift", file=sys.stderr)\n'
            '  sys.exit(2)\n')
        (self.bin / "xcodebuild").write_text(
            '#!/bin/sh\n'
            'if [ "$1" = "archive" ]; then\n'
            ' echo ARCHIVE >> "$P0C_MARKER"\n'
            ' APP="$P0C_REPO/.build/feedmine-v2.xcarchive/Products/Applications/FeedMine.app"\n'
            ' mkdir -p "$APP"\n'
            ' cp "$P0C_REPO/mock-archive.plist" "$APP/Info.plist"\n'
            ' SHORT=$(git -C "$P0C_REPO" rev-parse --short HEAD)\n'
            ' /usr/libexec/PlistBuddy -c "Set :FeedmineGitSHA $SHORT" "$APP/Info.plist"\n'
            ' cp "$P0C_REPO/FeedMineApp/FeedMineApp/Resources/catalog.sqlite" "$APP/catalog.sqlite"\n'
            ' cp "$P0C_REPO/FeedMineApp/FeedMineApp/Resources/catalog.manifest.json" "$APP/catalog.manifest.json"\n'
            'else echo EXPORT >> "$P0C_MARKER"; fi\n'
            'exit 0\n')
        (self.bin / "xcodebuild").chmod(0o755)
        self.commit()
        env = dict(os.environ)
        for key in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
            env.pop(key, None)
        env["PATH"] = str(self.bin) + os.pathsep + env.get("PATH", "")
        env["P0C_MARKER"] = str(self.marker)
        env["P0C_REPO"] = str(self.root)
        result = subprocess.run(["bash", str(self.root / "scripts/release-testflight.sh"), "--dry-run"],
                                cwd=self.root, capture_output=True, text=True, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("archive bytes/provenance differ", result.stdout + result.stderr)
        self.assertEqual(self.marker.read_text().strip(), "ARCHIVE")
        self.assertEqual(self.git("tag", "--list"), "")

    def test_corrupt_preflight_stops_before_archive(self):
        resources = self.root / "FeedMineApp/FeedMineApp/Resources"
        (resources / "catalog.sqlite").write_bytes(b"NOT SQLITE")
        (resources / "catalog.manifest.json").write_text("{}")
        self.commit()
        log = self.release()
        self.assertIn("product catalogue verification failed before archive", log)


if __name__ == "__main__":
    unittest.main()
