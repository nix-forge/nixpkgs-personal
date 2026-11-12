"""Check the plugin to web compatibility gate and staged refresh."""

from __future__ import annotations

import json
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

import update


class UpdateTests(unittest.TestCase):
    def test_flutter_builder_tracks_lock_constraint(self) -> None:
        update.check_flutter_sdk({"sdks": {"flutter": ">=3.47.0"}})
        with self.assertRaisesRegex(ValueError, "update web.nix builder"):
            update.check_flutter_sdk({"sdks": {"flutter": ">=3.50.0"}})

    def test_manifest_selects_web_version_and_rejects_abi_change(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = root / "manifest.json"
            manifest.write_text(
                json.dumps([
                    {
                        "versions": [
                            {
                                "sourceUrl": "https://github.com/Moonfin-Client/Plugin/releases/download/2.3.0/Moonfin.Server-2.3.0.0.zip",
                                "version": "2.3.0.0",
                                "targetAbi": "10.10.0.0",
                                "changelog": "The bundled web client moves up to Moonfin 2.6.0.",
                            }
                        ]
                    }
                ])
            )
            self.assertEqual(
                update.selected_manifest(manifest, "2.3.0", "10.10.0.0"),
                ("2.3.0.0", "10.10.0.0", "2.6.0"),
            )
            with self.assertRaisesRegex(ValueError, "target ABI changed"):
                update.selected_manifest(manifest, "2.3.0", "12.0.0.0")

    def test_late_master_manifest_is_pinned_and_identity_checked(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            identity = {
                "guid": "same",
                "name": "Moonbase",
                "owner": "upstream",
                "category": "General",
            }
            tagged = root / "tagged.json"
            fallback = root / "fallback.json"
            tagged.write_text(json.dumps([{**identity, "versions": []}]))
            fallback.write_text(
                json.dumps([
                    {
                        **identity,
                        "versions": [
                            {
                                "sourceUrl": "https://github.com/Moonfin-Client/Plugin/releases/download/2.3.0/Moonfin.Server-2.3.0.0.zip",
                                "version": "2.3.0.0",
                                "targetAbi": "10.10.0.0",
                                "changelog": "The bundled web client moves up to Moonfin 2.6.0.",
                            }
                        ],
                    }
                ])
            )
            with (
                patch.object(
                    update, "default_branch_commit", return_value="b" * 40
                ) as branch,
                patch.object(
                    update,
                    "prefetch_manifest",
                    side_effect=[
                        {"hash": "sha256-tag", "storePath": str(tagged)},
                        {"hash": "sha256-master", "storePath": str(fallback)},
                    ],
                ),
            ):
                revision, fetched, selected = update.choose_manifest(
                    "a" * 40, "2.3.0", "10.10.0.0"
                )
            branch.assert_called_once_with(update.PLUGIN)
            self.assertEqual(revision, "b" * 40)
            self.assertEqual(fetched["hash"], "sha256-master")
            self.assertEqual(selected, ("2.3.0.0", "10.10.0.0", "2.6.0"))
            changed = json.loads(fallback.read_text())
            changed[0]["guid"] = "different"
            fallback.write_text(json.dumps(changed))
            with (
                patch.object(update, "default_branch_commit", return_value="b" * 40),
                patch.object(
                    update,
                    "prefetch_manifest",
                    side_effect=[
                        {"hash": "sha256-tag", "storePath": str(tagged)},
                        {"hash": "sha256-master", "storePath": str(fallback)},
                    ],
                ),
                self.assertRaisesRegex(ValueError, "changed plugin identity: guid"),
            ):
                update.choose_manifest("a" * 40, "2.3.0", "10.10.0.0")

    def test_failed_restore_preserves_all_existing_pins(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary)
            original = (update.PACKAGE / "source.nix").read_text()
            current_tag = update.source_field(original, "releaseTag")
            major, minor, patch_version = map(int, current_tag.split("."))
            next_tag = f"{major}.{minor}.{patch_version + 1}"
            (package / "source.nix").write_text(original)
            (package / "web.nix").write_text((update.PACKAGE / "web.nix").read_text())
            for name in ("deps.json", "pubspec.lock.json", "git-hashes.json"):
                (package / name).write_text("{}\n")
            web = Path(temporary) / "web"
            web.mkdir()
            (web / "pubspec.lock").write_text("packages:\n  one:\n    source: hosted\n")
            with (
                patch.object(update, "PACKAGE", package),
                patch.object(update, "release_tag", return_value=next_tag),
                patch.object(update, "tag_commit", side_effect=["a" * 40, "b" * 40]),
                patch.object(
                    update,
                    "prefetch",
                    side_effect=[
                        {"hash": "sha256-plugin", "storePath": temporary},
                        {"hash": "sha256-web", "storePath": str(web)},
                    ],
                ),
                patch.object(
                    update,
                    "choose_manifest",
                    return_value=(
                        "c" * 40,
                        {"hash": "sha256-manifest"},
                        (f"{next_tag}.0", "10.10.0.0", "2.7.0"),
                    ),
                ),
                patch.object(update, "git_hashes", return_value={}),
                patch.object(
                    update.importlib,
                    "import_module",
                    return_value=types.SimpleNamespace(
                        safe_load=lambda _: (
                            {"packages": {"one": {"source": "hosted"}}}
                            | {"sdks": {"flutter": ">=3.47.0"}}
                        )
                    ),
                ),
                patch.object(
                    update,
                    "regenerate_deps",
                    side_effect=RuntimeError("restore failed"),
                ),
                self.assertRaisesRegex(RuntimeError, "restore failed"),
            ):
                update.main([])
            self.assertEqual((package / "source.nix").read_text(), original)
            for name in ("deps.json", "pubspec.lock.json", "git-hashes.json"):
                self.assertEqual((package / name).read_text(), "{}\n")


if __name__ == "__main__":
    unittest.main()
