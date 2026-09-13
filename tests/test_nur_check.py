"""Keep the proposed NUR registration aligned with the admission formatter."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_nur", ROOT / "scripts/check-nur.py"
)
assert SPEC is not None
assert SPEC.loader is not None
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class RegistrationTests(unittest.TestCase):
    def registration(self, value):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "registration.json"
            path.write_text(json.dumps(value))
            return CHECK.registration(path)

    def test_current_proposal(self):
        name, entry = CHECK.registration(ROOT / "docs/nur-registration.json")
        self.assertEqual(name, "nix-forge")
        self.assertEqual(entry["github-contact"], "IanHollow")
        self.assertEqual(entry["url"], "https://github.com/nix-forge/nixpkgs-personal")

    def test_missing_contact_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "github-contact"):
            self.registration({
                "example": {"url": "https://github.com/example/packages"}
            })

    def test_blank_required_fields_are_rejected(self):
        for field in ("url", "github-contact"):
            entry = {
                "url": "https://github.com/example/packages",
                "github-contact": "example",
            }
            entry[field] = " "
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, field):
                self.registration({"example": entry})

    def test_ambiguous_entries_are_rejected(self):
        for entries in ([], {}, {"one": {}, "two": {}}, {"one": None}):
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                self.registration(entries)


if __name__ == "__main__":
    unittest.main()
