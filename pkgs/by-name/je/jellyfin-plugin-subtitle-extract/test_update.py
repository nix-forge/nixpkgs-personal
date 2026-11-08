"""Verify release metadata gates and update staging."""

from __future__ import annotations

import json
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

import update


class UpdateTests(unittest.TestCase):
    def test_manifest_rejects_target_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = {
                "version": 9,
                "targetAbi": "12.0.0.0",
                "framework": "net10.0",
                "artifacts": ["Jellyfin.Plugin.SubtitleExtract.dll"],
            }
            (root / "build.yaml").write_text(json.dumps(manifest))
            yaml = types.SimpleNamespace(safe_load=json.loads)
            with patch.object(update.importlib, "import_module", return_value=yaml):
                self.assertEqual(update.manifest_version(root, "12.0.0.0"), "9.0.0.0")
                with self.assertRaisesRegex(ValueError, "target ABI changed"):
                    update.manifest_version(root, "10.10.0.0")
                manifest["artifacts"].append("unexpected.dll")
                (root / "build.yaml").write_text(json.dumps(manifest))
                with self.assertRaisesRegex(ValueError, "artifact inventory changed"):
                    update.manifest_version(root, "12.0.0.0")

    def test_failed_restore_leaves_package_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary)
            original = (update.PACKAGE / "source.nix").read_text()
            (package / "source.nix").write_text(original)
            (package / "deps.json").write_text("[]\n")
            release = {"tag_name": "v9", "published_at": "2026-09-25T00:00:00Z"}
            with (
                patch.object(update, "PACKAGE", package),
                patch.object(update, "github_release", return_value=release),
                patch.object(update, "tag_commit", return_value="a" * 40),
                patch.object(
                    update,
                    "prefetch",
                    return_value={"hash": "sha256-test", "storePath": temporary},
                ),
                patch.object(update, "manifest_version", return_value="9.0.0.0"),
                patch.object(
                    update,
                    "regenerate_deps",
                    side_effect=RuntimeError("restore failed"),
                ),
                self.assertRaisesRegex(RuntimeError, "restore failed"),
            ):
                update.main([])
            self.assertEqual((package / "source.nix").read_text(), original)
            self.assertEqual((package / "deps.json").read_text(), "[]\n")


if __name__ == "__main__":
    unittest.main()
