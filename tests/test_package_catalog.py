"""Check catalog recipe links for additional public build outputs."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "package_catalog", ROOT / "scripts/package_catalog.py"
)
assert SPEC is not None
assert SPEC.loader is not None
CATALOG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CATALOG)


class PackageCatalogTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="catalog-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        source = self.root / "pkgs/by-name/ca/cadcraft"
        source.mkdir(parents=True)
        (source / "package.nix").write_text("{}: {}\n")
        self.metadata = {
            "pname": "cadcraft",
            "description": "Drawing application",
            "version": "1.0",
            "homepage": "",
            "licenses": [],
        }

    def test_cross_output_links_existing_recipe(self) -> None:
        inventory = {
            "x86_64-linux": {
                "cadcraft": self.metadata,
                "cadcraft-arm-cross": self.metadata,
            }
        }
        result = CATALOG.render(inventory, {}, self.root)
        self.assertIn("### cadcraft-arm-cross", result)
        self.assertEqual(
            result.count("[Recipe](../pkgs/by-name/ca/cadcraft/package.nix)"), 2
        )
        self.assertNotIn("../pkgs/by-name/ca/cadcraft-arm-cross/", result)

    def test_unknown_recipe_remains_an_error(self) -> None:
        inventory = {"x86_64-linux": {"unrelated-output": self.metadata}}
        with self.assertRaisesRegex(
            ValueError, "missing package source: unrelated-output"
        ):
            CATALOG.render(inventory, {}, self.root)


if __name__ == "__main__":
    unittest.main()
