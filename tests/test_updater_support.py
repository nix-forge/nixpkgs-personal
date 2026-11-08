"""Exercise editable source discovery and standalone Nixpkgs selection."""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import run_update
import update_nix


class UpdaterLocationTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="updater-location-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.package = self.root / "pkgs/by-name/ex/example"
        self.package.mkdir(parents=True)
        (self.package / "package.nix").write_text("{}: {}\n")
        (self.package / "update.py").write_text("raise SystemExit(0)\n")

    def test_nonflake_source_path_works_outside_checkout(self) -> None:
        self.assertEqual(
            run_update.find_package("example", self.package, None), self.package
        )

    def test_flake_store_source_resolves_from_checkout_subdirectory(self) -> None:
        nested = self.root / "docs/nested"
        nested.mkdir(parents=True)
        with patch.object(Path, "cwd", return_value=nested):
            self.assertEqual(
                run_update.find_package(
                    "example", Path("/nix/store/example-source"), None
                ),
                self.package,
            )

    def test_explicit_package_directory_works_from_unrelated_directory(self) -> None:
        with patch.object(Path, "cwd", return_value=Path("/")):
            self.assertEqual(
                run_update.find_package(
                    "example", Path("/nix/store/source"), self.package
                ),
                self.package,
            )
        with self.assertRaisesRegex(ValueError, "editable package"):
            run_update.find_package("example", self.package, self.root)

    def test_store_copy_is_never_selected_for_editing(self) -> None:
        with (
            patch.object(Path, "cwd", return_value=Path("/")),
            self.assertRaisesRegex(ValueError, "UPDATE_NIX_PACKAGE_DIR"),
        ):
            run_update.find_package("example", Path("/nix/store/source"), None)


class ScopeTests(unittest.TestCase):
    def test_direct_invocation_uses_nix_path_without_personal_flake(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(update_nix.package_scope(), "import <nixpkgs> {}")
            expression = update_nix.candidate_expression(
                Path("/example/package"), "package.nix", "fetch-deps"
            )
            self.assertNotIn("getFlake", expression)
            self.assertIn('"fetch-deps"', expression)

    def test_declared_pin_and_nix_string_escaping(self) -> None:
        with tempfile.TemporaryDirectory(prefix="updater-scope-") as temporary:
            source = Path(temporary) / 'é-${unexpected}"'
            source.mkdir()
            (source / "default.nix").write_text("{}: {}\n")
            with patch.dict(os.environ, {"NIXPKGS_UPDATE_SOURCE": str(source)}):
                expression = update_nix.package_scope(system="x86_64-linux")
            self.assertIn("é", expression)
            self.assertNotIn(r"\u00e9", expression)
            self.assertIn(r"\${unexpected}", expression)
            self.assertIn(r"\"", expression)
            self.assertIn('system = "x86_64-linux"', expression)


if __name__ == "__main__":
    unittest.main()
