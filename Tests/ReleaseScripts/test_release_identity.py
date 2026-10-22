"""Build identity must be written by ProcessInfoPlistFile, never by a racing script phase.

The defect this pins: a "Stamp build identity" run-script phase wrote the identity into the built
Info.plist, but ProcessInfoPlistFile could run afterwards and replace that plist from the source
one, dropping FeedmineGitSHA/FeedmineBuildDate (observed in incremental builds). The fix makes the
source Info.plist carry build-setting placeholders and makes release-testflight.sh pass the values
as command-line settings, so the plist writer itself owns the identity. Project defaults stay
"unknown", which the archive gate refuses rather than mislabelling a build.

This is the cheap contract half of the proof. It does not claim an archive was built; the archive
gate must run scripts/release-testflight.sh and inspect the real product.
"""
from __future__ import annotations

import json
import plistlib
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "FeedMineApp/FeedMineApp.xcodeproj/project.pbxproj"
INFO_PLIST = ROOT / "FeedMineApp/FeedMineApp/Info.plist"
APP_TARGET = "00000000000000000000002D"
PLACEHOLDERS = {
    "FeedmineGitSHA": "$(FEEDMINE_GIT_SHA)",
    "FeedmineGitBranch": "$(FEEDMINE_GIT_BRANCH)",
    "FeedmineBuildDate": "$(FEEDMINE_BUILD_DATE)",
}


class BuildIdentityContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("plutil") is None:
            raise unittest.SkipTest("requires macOS plutil to read the OpenStep project")
        cls.objects = json.loads(
            subprocess.check_output(
                ["plutil", "-convert", "json", "-o", "-", str(PROJECT)], text=True
            )
        )["objects"]

    def target_build_settings(self):
        target = self.objects[APP_TARGET]
        config_list = self.objects[target["buildConfigurationList"]]
        settings = {}
        for config_id in config_list["buildConfigurations"]:
            config = self.objects[config_id]
            settings[config["name"]] = config["buildSettings"]
        return settings

    def test_info_plist_uses_build_setting_placeholders(self):
        info = plistlib.loads(INFO_PLIST.read_bytes())
        for key, placeholder in PLACEHOLDERS.items():
            self.assertEqual(info.get(key), placeholder, key)

    def test_app_target_has_no_script_phase_writing_the_product_plist(self):
        target = self.objects[APP_TARGET]
        self.assertEqual(target["buildPhases"], [
            "000000000000000000000027",  # Sources
            "000000000000000000000028",  # Frameworks
            "000000000000000000000029",  # Resources
        ])
        for phase_id in target["buildPhases"]:
            phase = self.objects[phase_id]
            self.assertNotEqual(phase.get("isa"), "PBXShellScriptBuildPhase")
            self.assertNotIn("generate_build_info.sh", phase.get("shellScript", ""))

    def test_both_configurations_default_to_unknown_not_a_stale_sha(self):
        settings = self.target_build_settings()
        self.assertEqual(set(settings), {"Debug", "Release"})
        for name, build_settings in settings.items():
            self.assertEqual(build_settings.get("FEEDMINE_GIT_SHA"), "unknown", name)
            self.assertEqual(build_settings.get("FEEDMINE_GIT_BRANCH"), "unknown", name)
            self.assertEqual(build_settings.get("FEEDMINE_BUILD_DATE"), "unknown", name)


if __name__ == "__main__":
    unittest.main()
