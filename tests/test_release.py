"""Offline tests for release validation, ZIP contents and safe uploads."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from package_release import ROOT, manifest, package
from publish_release import publish


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "source"
        self.root.mkdir()
        self.output = Path(self.temp.name) / "output"
        self.write("ARC.toc", "## Version: 2.3.4\nARC_Core.lua\nARC_PlayerCheck.lua\nARC.lua\n")
        self.write("ARC_Core.lua", 'ARC.VERSION = "2.3.4"\n')
        self.write("ARC_PlayerCheck.lua", "-- detail\n")
        self.write("ARC.lua", "-- events\n")
        self.write("README.md", "Current version: **2.3.4**\n")
        self.write("changelog.txt", "v2.3.4 CHANGES\n  - Current change\n\nv2.3.3 CHANGES\n  - Old change\n")
        self.write("LICENSE", "MIT\n")

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def build(self, tag="v2.3.4"):
        return package(self.root, self.output, tag)

    def test_install_zip_has_only_manifest_modules_toc_changelog_license(self):
        for name in ("docs/example.md", "tests/test.lua", ".git/config", "secret.lua", "old.zip"):
            self.write(name, "must not ship")
        archive = self.build()
        with zipfile.ZipFile(archive) as opened:
            self.assertEqual(set(opened.namelist()), {
                "ARC/ARC.toc", "ARC/ARC_Core.lua", "ARC/ARC_PlayerCheck.lua",
                "ARC/ARC.lua", "ARC/changelog.txt", "ARC/LICENSE",
            })
            self.assertIsNone(opened.testzip())
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.assertEqual(archive.with_suffix(".zip.sha256").read_text(), f"{digest}  ARC-2.3.4.zip\n")
        notes = (self.output / "release-notes.md").read_text(encoding="utf-8")
        self.assertIn("Current change", notes)
        self.assertNotIn("Old change", notes)
        self.assertIn("restart WoW", notes)

    def test_tag_mismatch_or_injection_fails_without_a_package(self):
        for tag in ("v2.3.5", "2.3.4", "v2.3.4;echo bad", "../2.3.4"):
            with self.assertRaises(ValueError):
                self.build(tag)
        self.assertFalse(self.output.exists())

    def test_core_readme_and_changelog_versions_are_checked(self):
        for file in ("ARC_Core.lua", "README.md", "changelog.txt"):
            original = (self.root / file).read_text()
            self.write(file, original.replace("2.3.4", "2.3.5"))
            with self.assertRaises(ValueError):
                self.build()
            self.write(file, original)

    def test_missing_and_duplicate_or_traversing_modules_fail(self):
        original = (self.root / "ARC.toc").read_text()
        for extra in ("ARC_Missing.lua", "ARC_Core.lua", "../evil.lua"):
            self.write("ARC.toc", original.replace("ARC.lua\n", extra + "\nARC.lua\n"))
            with self.assertRaises(ValueError):
                self.build()

    def test_same_sources_have_deterministic_bytes_and_normalized_newlines(self):
        first = self.build().read_bytes()
        self.assertEqual(first, self.build().read_bytes())
        for path in self.root.iterdir():
            path.write_bytes(path.read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
        self.assertEqual(first, self.build().read_bytes())

    def test_current_repo_package_is_minimal(self):
        version, names, _ = manifest(ROOT)
        archive = package(ROOT, self.output, "v" + version)
        self.assertEqual(len(names), 10)  # 7 runtime Lua modules + TOC + changelog + license
        with zipfile.ZipFile(archive) as opened:
            self.assertNotIn("ARC/README.md", opened.namelist())
            self.assertFalse(any("/docs/" in name or "/tests/" in name for name in opened.namelist()))
            self.assertIn("Permission is hereby granted", opened.read("ARC/ARC_Gear.lua").decode("utf-8"))

    def run_publish(self, release):
        with patch.dict(os.environ, {"GH_REPO": "owner/repo"}), patch("publish_release.gh", return_value=json.dumps(release)) as api:
            publish("v2.3.4", self.output)
            return api.call_args_list

    def test_uploads_both_assets_and_fills_blank_notes(self):
        self.build()
        calls = self.run_publish({"tag_name": "v2.3.4", "draft": False, "assets": [], "body": ""})
        self.assertEqual(sum(call.args[:2] == ("release", "upload") for call in calls), 2)
        self.assertEqual(calls[-1].args[:2], ("release", "edit"))
        self.assertFalse(any("--clobber" in call.args for call in calls))

    def test_rerun_preserves_identical_assets_and_custom_notes(self):
        archive = self.build()
        assets = [{"name": path.name, "digest": "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()}
                  for path in (archive, archive.with_suffix(".zip.sha256"))]
        calls = self.run_publish({"tag_name": "v2.3.4", "assets": assets, "body": "My release notes"})
        self.assertEqual(len(calls), 1)

    def test_draft_wrong_tag_and_conflicting_assets_stop_before_any_write(self):
        self.build()
        for data in ({"tag_name": "v2.3.4", "draft": True}, {"tag_name": "v1.0.0"},
                     {"tag_name": "v2.3.4", "assets": [{"name": "ARC-2.3.4.zip", "digest": "sha256:other"}]}):
            with patch.dict(os.environ, {"GH_REPO": "owner/repo"}), patch("publish_release.gh", return_value=json.dumps(data)) as api:
                with self.assertRaises(ValueError):
                    publish("v2.3.4", self.output)
                self.assertEqual(api.call_count, 1)


if __name__ == "__main__":
    unittest.main()
