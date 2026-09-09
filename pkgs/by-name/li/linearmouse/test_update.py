"""Keep the application's release and schema pins in one atomic update."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import update


class SchemaPinTests(unittest.TestCase):
    def test_existing_metadata_round_trip(self):
        content = Path(__file__).with_name("source.nix").read_text()
        state = update._parse_existing(content)
        self.assertEqual(state.schema_url, update._schema_url(state.version))
        self.assertEqual(update._render_source(state), content)
        self.assertNotEqual(state.hash_sri, state.schema_hash_sri)

    def test_update_fetches_matching_schema_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "update.py"
            source = script.with_name("source.nix")
            source.write_text(Path(__file__).with_name("source.nix").read_text())
            release = {
                "draft": False,
                "prerelease": False,
                "tag_name": "v0.12.0",
                "assets": [
                    {
                        "name": "LinearMouse.dmg",
                        "browser_download_url": "https://github.com/linearmouse/linearmouse/releases/download/v0.12.0/LinearMouse.dmg",
                    }
                ],
            }
            with (
                patch.object(update, "__file__", str(script)),
                patch.object(update, "_fetch_json", return_value=release),
                patch.object(
                    update,
                    "_prefetch_hash",
                    side_effect=["sha256-app", "sha256-schema"],
                ) as prefetch,
            ):
                self.assertEqual(update._main([]), 0)
            state = update._parse_existing(source.read_text())
            self.assertEqual(state.version, "0.12.0")
            self.assertEqual(state.schema_url, update._schema_url("0.12.0"))
            self.assertEqual(state.schema_hash_sri, "sha256-schema")
            self.assertEqual(prefetch.call_args_list[1].args, (state.schema_url,))

    def test_missing_schema_preserves_existing_pins(self):
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "update.py"
            source = script.with_name("source.nix")
            original = Path(__file__).with_name("source.nix").read_text()
            source.write_text(original)
            state = update._parse_existing(original)
            with (
                patch.object(update, "__file__", str(script)),
                patch.object(update, "_fetch_json"),
                patch.object(
                    update,
                    "_extract_release",
                    return_value=update._Release(state.version, state.url),
                ),
                patch.object(
                    update, "_prefetch_hash", side_effect=["sha256-app", SystemExit(1)]
                ),
                self.assertRaises(SystemExit),
            ):
                update._main(["--refresh"])
            self.assertEqual(source.read_text(), original)


if __name__ == "__main__":
    unittest.main()
