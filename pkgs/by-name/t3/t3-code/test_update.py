"""Offline regression checks for the package's source updater."""

from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

import update


class UpdateTests(unittest.TestCase):
    def test_repository_input_discovery_walks_past_inner_pkgs_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "flake.nix").touch()
            (root / "flake.lock").touch()
            script = root / "pkgs/by-name/t3/t3-code/update.py"
            with patch.object(update, "__file__", str(script)):
                self.assertEqual(update._nixpkgs_ref(), str(root))
                self.assertIn(".inputs.nixpkgs", update._nixpkgs_expression())

    def test_copied_package_uses_upstream_registry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            script = Path(temporary) / "t3-code/update.py"
            with patch.object(update, "__file__", str(script)):
                self.assertEqual(update._nixpkgs_ref(), "nixpkgs")
                self.assertEqual(
                    update._nixpkgs_expression(), "builtins.getFlake flakeRef"
                )

    def test_published_digest_change_requires_refresh(self) -> None:
        existing = update._parse_existing(
            Path(update.__file__).with_name("source.nix").read_text()
        )
        release = update._ReleaseMeta(
            version=existing.version,
            darwin_url=existing.darwin_url,
            darwin_hash_sri=existing.darwin_hash,
            linux_rev=existing.linux_rev,
        )
        self.assertTrue(update._quick_matches(existing, release))
        self.assertFalse(
            update._quick_matches(
                existing, replace(release, darwin_hash_sri=update.FAKE_HASH)
            )
        )


if __name__ == "__main__":
    unittest.main()
