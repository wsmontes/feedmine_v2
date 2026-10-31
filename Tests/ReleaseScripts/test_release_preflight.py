"""Release pre-archive failures must never reach xcodebuild or tag creation."""
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
        shutil.copy2(ROOT / "scripts/ExportOptions.plist", self.root / "scripts/ExportOptions.plist")
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

    def release(self):
        env = dict(os.environ)
        for key in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
            env.pop(key, None)
        env["PATH"] = str(self.bin) + os.pathsep + env.get("PATH", "")
        env["P0C_MARKER"] = str(self.marker)
        result = subprocess.run(["bash", str(self.root / "scripts/release-testflight.sh"), "--dry-run"],
                                cwd=self.root, capture_output=True, text=True, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists(), "xcodebuild archive/upload must not run")
        self.assertEqual(self.git("tag", "--list"), "", "failed release must not create tag")
        self.assertNotIn("ASC_KEY_ID ausente", result.stdout + result.stderr)
        return result.stdout + result.stderr

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
        self.identity_archive_fixture()
        (self.root / "scripts/verify_catalog_release.py").write_text(
            'import sys\n'
            'if sys.argv[1] == "archive":\n'
            '  print("REFUSED: simulated archive byte drift", file=sys.stderr)\n'
            '  sys.exit(2)\n')
        self.commit()
        result = self.run_identity_archive(self.root / "archive-args.log")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("archive bytes/provenance differ", result.stdout + result.stderr)
        self.assertEqual(self.marker.read_text().strip(), "ARCHIVE")
        self.assertEqual(self.git("tag", "--list"), "")

    @unittest.skipUnless(Path("/usr/libexec/PlistBuddy").exists(),
                         "requires macOS PlistBuddy to reach the catalogue gate")
    def test_corrupt_preflight_stops_before_archive(self):
        resources = self.root / "FeedMineApp/FeedMineApp/Resources"
        (resources / "catalog.sqlite").write_bytes(b"NOT SQLITE")
        (resources / "catalog.manifest.json").write_text("{}")
        self.commit()
        log = self.release()
        self.assertIn("product catalogue verification failed before archive", log)

    @unittest.skipUnless(Path("/usr/libexec/PlistBuddy").exists(), "requires macOS PlistBuddy")
    def test_archive_gets_identity_as_build_settings_and_checks_them(self):
        """The archive command must carry HEAD/branch/date as build settings, and the script must
        reject a product whose plist carries different values (the old stamp race)."""
        args_path = self.root / "archive-args.log"
        self.identity_archive_fixture()
        result = self.run_identity_archive(args_path)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PAIRING OK", result.stdout)
        short = self.git("rev-parse", "--short", "HEAD")
        branch = self.git("rev-parse", "--abbrev-ref", "HEAD")
        args = args_path.read_text().splitlines()
        self.assertIn(f"FEEDMINE_GIT_SHA={short}", args)
        self.assertIn(f"FEEDMINE_GIT_BRANCH={branch}", args)
        dates = [arg for arg in args if arg.startswith("FEEDMINE_BUILD_DATE=")]
        self.assertEqual(len(dates), 1)
        self.assertRegex(dates[0], r"^FEEDMINE_BUILD_DATE=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")

    @unittest.skipUnless(Path("/usr/libexec/PlistBuddy").exists(), "requires macOS PlistBuddy")
    def test_archive_with_foreign_branch_is_refused_before_export(self):
        args_path = self.root / "archive-args.log"
        self.identity_archive_fixture()
        result = self.run_identity_archive(args_path, force_branch="stale-branch")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("carries branch 'stale-branch'", result.stdout + result.stderr)
        self.assertEqual(self.marker.read_text().strip(), "ARCHIVE")
        self.assertEqual(self.git("tag", "--list"), "")

    def identity_archive_fixture(self):
        resources = self.root / "FeedMineApp/FeedMineApp/Resources"
        (resources / "catalog.sqlite").write_bytes(b"fake valid preflight bytes")
        (resources / "catalog.manifest.json").write_text('{"revision": 11}')
        with (self.root / "mock-archive.plist").open("wb") as stream:
            plistlib.dump({"CFBundleIdentifier": "com.feedmine.app",
                           "CFBundleVersion": "46", "CFBundleShortVersionString": "1.0",
                           "FeedmineGitSHA": "unknown", "FeedmineGitBranch": "unknown",
                           "FeedmineBuildDate": "unknown"}, stream)
        (self.root / "scripts/verify_product_catalogue.sh").write_text("#!/bin/sh\nexit 0\n")
        (self.root / "scripts/verify_catalog_release.py").write_text(
            'import sys\nsys.exit(0)\n')
        (self.bin / "xcodebuild").write_text(
            '#!/bin/sh\n'
            'if [ "$1" = "archive" ]; then\n'
            ' echo ARCHIVE >> "$P0C_MARKER"\n'
            ' printf "%s\\n" "$@" > "$P0C_ARGS"\n'
            ' APP="$P0C_REPO/.build/feedmine-v2.xcarchive/Products/Applications/FeedMine.app"\n'
            ' mkdir -p "$APP"\n'
            ' cp "$P0C_REPO/mock-archive.plist" "$APP/Info.plist"\n'
            ' SHA=; BRANCH=; DATE=\n'
            ' for arg in "$@"; do\n'
            '  case "$arg" in\n'
            '   FEEDMINE_GIT_SHA=*) SHA="${arg#*=}" ;;\n'
            '   FEEDMINE_GIT_BRANCH=*) BRANCH="${arg#*=}" ;;\n'
            '   FEEDMINE_BUILD_DATE=*) DATE="${arg#*=}" ;;\n'
            '  esac\n'
            ' done\n'
            ' if [ -n "${P0C_FORCE_BRANCH:-}" ]; then BRANCH="$P0C_FORCE_BRANCH"; fi\n'
            ' /usr/libexec/PlistBuddy -c "Set :FeedmineGitSHA $SHA" "$APP/Info.plist"\n'
            ' /usr/libexec/PlistBuddy -c "Set :FeedmineGitBranch $BRANCH" "$APP/Info.plist"\n'
            ' /usr/libexec/PlistBuddy -c "Set :FeedmineBuildDate $DATE" "$APP/Info.plist"\n'
            ' cp "$P0C_REPO/FeedMineApp/FeedMineApp/Resources/catalog.sqlite" "$APP/catalog.sqlite"\n'
            ' cp "$P0C_REPO/FeedMineApp/FeedMineApp/Resources/catalog.manifest.json" "$APP/catalog.manifest.json"\n'
            'else echo EXPORT >> "$P0C_MARKER"; fi\n'
            'exit 0\n')
        (self.bin / "xcodebuild").chmod(0o755)
        self.commit()

    def run_identity_archive(self, args_path, force_branch=None):
        env = dict(os.environ)
        for key in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
            env.pop(key, None)
        env["PATH"] = str(self.bin) + os.pathsep + env.get("PATH", "")
        env["P0C_MARKER"] = str(self.marker)
        env["P0C_REPO"] = str(self.root)
        env["P0C_ARGS"] = str(args_path)
        if force_branch is not None:
            env["P0C_FORCE_BRANCH"] = force_branch
        return subprocess.run(["bash", str(self.root / "scripts/release-testflight.sh"), "--dry-run"],
                              cwd=self.root, capture_output=True, text=True, env=env)


if __name__ == "__main__":
    unittest.main()
