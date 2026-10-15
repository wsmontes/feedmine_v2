"""Publisher regressions use a simulated compiler executable only inside fixtures."""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import bootstrap_catalog as cat
import publish_catalog_update as publish


FAKE_COMPILER = """#!/usr/bin/env python3
import argparse, json, pathlib, xml.etree.ElementTree as ET
p = argparse.ArgumentParser()
p.add_argument('--feeds-root')
p.add_argument('--output')
p.add_argument('--manifest-output')
p.add_argument('--json', action='store_true')
a = p.parse_args()
files = list(pathlib.Path(a.feeds_root).rglob('*.opml'))
urls = set()
for file in files:
    for outline in ET.parse(file).iter('outline'):
        if outline.get('xmlUrl'):
            urls.add(outline.get('xmlUrl'))
pathlib.Path(a.output).write_bytes(b'fake SQLite: test only')
result = {'file_count': len(files), 'source_count': len(urls), 'failed_file_count': 0,
          'invalid_source_count': 0, 'node_count': 1, 'placement_count': len(urls),
          'duplicate_occurrence_count': 0, 'size_bytes': 22}
pathlib.Path(a.manifest_output).write_text(json.dumps(result))
"""


class PublishingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="p0c-publisher-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "editorial"
        self.destination = root / "public"
        self.destination.mkdir()
        (self.source / "Feeds").mkdir(parents=True)
        self.compiler = root / "compiler" / "build_catalog.py"
        self.compiler.parent.mkdir()
        self.compiler.write_text(FAKE_COMPILER)
        self.identity = self.compiler.with_name("catalog_identity.py")
        self.identity.write_text("# test-only simulated identity")
        self.write_opml("a.opml", "https://a.example/feed")

    def write_opml(self, name, url):
        (self.source / "Feeds" / name).write_text(
            f'<opml version="2.0"><body><outline type="rss" xmlUrl="{url}"/></body></opml>')

    def args(self, revision=1, apply=False):
        return argparse.Namespace(source=self.source, destination=self.destination,
            revision=revision, compiler=self.compiler,
            compiler_sha256=cat.sha256_file(self.compiler),
            identity_sha256=cat.sha256_file(self.identity), apply=apply)

    def test_prepare_dry_run_does_not_write_checkout(self):
        self.assertEqual(publish.run(self.args(apply=False)), 0)
        self.assertFalse((self.destination / "manifest.json").exists())
        self.assertFalse((self.destination / "Feeds").exists())

    def test_apply_generates_bootstrap_compatible_manifest(self):
        self.assertEqual(publish.run(self.args(apply=True)), 0)
        data = (self.destination / "manifest.json").read_bytes()
        manifest = cat.validate_manifest(json.loads(data), data, "local", 1)
        self.assertEqual(manifest["fileCount"], 1)
        self.assertEqual(manifest["sourceCount"], 1)
        self.assertEqual(publish.inventory(self.destination), manifest["files"])
        before = cat.sha256_bytes(data)
        self.assertEqual(publish.run(self.args(revision=1, apply=True)), 0)
        self.assertEqual(before, cat.sha256_file(self.destination / "manifest.json"))

    def test_changed_bytes_need_strictly_higher_revision(self):
        self.assertEqual(publish.run(self.args(apply=True)), 0)
        self.write_opml("a.opml", "https://b.example/feed")
        with self.assertRaisesRegex(publish.PublishRefusal, "revision must increase"):
            publish.run(self.args(revision=1, apply=True))
        self.assertEqual(publish.run(self.args(revision=2, apply=True)), 0)
        self.assertEqual(json.loads((self.destination / "manifest.json").read_text())["revision"], 2)

    def test_remove_and_add_detected(self):
        self.assertEqual(publish.run(self.args(apply=True)), 0)
        (self.source / "Feeds" / "a.opml").unlink()
        self.write_opml("new.opml", "https://new.example/feed")
        self.assertEqual(publish.run(self.args(revision=2, apply=True)), 0)
        self.assertFalse((self.destination / "Feeds" / "a.opml").exists())
        self.assertTrue((self.destination / "Feeds" / "new.opml").is_file())

    def test_corrupted_destination_refused(self):
        self.assertEqual(publish.run(self.args(apply=True)), 0)
        (self.destination / "Feeds" / "a.opml").write_bytes(b"tampered")
        with self.assertRaisesRegex(publish.PublishRefusal, "invalid OPML|destination Feeds"):
            publish.run(self.args(revision=2, apply=True))

    def test_compiler_change_rejected(self):
        self.assertEqual(publish.run(self.args(apply=True)), 0)
        self.write_opml("b.opml", "https://b.example/feed")
        args = self.args(revision=2, apply=True)
        self.compiler.write_text(FAKE_COMPILER + "\n# tampered\n")
        with self.assertRaisesRegex(publish.PublishRefusal, "compiler unverified"):
            publish.run(args)

    def test_bad_opml_refused_without_mutation(self):
        (self.source / "Feeds" / "a.opml").write_bytes(b"<opml")
        with self.assertRaisesRegex(publish.PublishRefusal, "invalid OPML"):
            publish.run(self.args())
        self.assertFalse((self.destination / "manifest.json").exists())


if __name__ == "__main__":
    unittest.main()
