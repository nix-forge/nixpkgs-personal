"""Exercise selection and upstream license-change boundaries with small fixtures."""

import tempfile
import unittest
from pathlib import Path

from catalog import inspect, install, validate, verify


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        for name in ("example", "restricted"):
            skill = self.source / "skills" / name
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(
                f"---\nname: {name}\n---\nUseful content.\n"
            )
            (skill / "LICENSE.TXT").write_text(f"{name} terms\n")
            (skill / "helper.py").write_text("print('original')\n")
        skills = inspect(self.source, "skills")
        skills["example"]["licenses"] = ["asl20"]
        skills["restricted"]["licenses"] = ["unfree"]
        self.manifest = {
            "prefix": "provider",
            "root": "skills",
            "skills": skills,
            "rootNotices": {},
        }

    def test_selected_contents_and_restricted_bytes(self):
        output = self.root / "output"
        install(self.source, self.manifest, ["restricted"], output)
        verify(self.source, self.manifest, ["restricted"], output)
        installed = output / "share/agent-skills/provider-restricted"
        self.assertIn("name: restricted", (installed / "SKILL.md").read_text())
        self.assertFalse((installed.parent / "provider-example").exists())
        (installed / "helper.py").write_text("modified")
        with self.assertRaisesRegex(ValueError, "Changed upstream content"):
            verify(self.source, self.manifest, ["restricted"], output)

    def test_free_namespace_and_modification_notice(self):
        output = self.root / "output"
        install(self.source, self.manifest, ["example"], output)
        skill = output / "share/agent-skills/provider-example"
        self.assertIn("name: provider-example\n", (skill / "SKILL.md").read_text())
        self.assertIn("Modified by nixpkgs-personal", (skill / "SKILL.md").read_text())
        self.assertEqual((skill / "LICENSE.TXT").read_text(), "example terms\n")

    def test_changed_uppercase_license_requires_review(self):
        (self.source / "skills/restricted/LICENSE.TXT").write_text("changed terms")
        with self.assertRaisesRegex(ValueError, "review required: restricted"):
            validate(self.source, self.manifest)

    def test_added_skill_requires_review(self):
        new = self.source / "skills/new"
        new.mkdir()
        (new / "SKILL.md").write_text("---\nname: new\n---\n")
        with self.assertRaisesRegex(ValueError, "review required: new"):
            validate(self.source, self.manifest)

    def test_added_root_notice_requires_review(self):
        (self.source / "LICENSE.txt").write_text("New repository-wide terms")
        with self.assertRaisesRegex(ValueError, "Root notice review required"):
            validate(self.source, self.manifest)

    def test_invalid_selection(self):
        for names in ([], ["unknown"], ["example", "example"]):
            with self.subTest(names=names), self.assertRaises(ValueError):
                install(self.source, self.manifest, names, self.root / "output")


if __name__ == "__main__":
    unittest.main()
