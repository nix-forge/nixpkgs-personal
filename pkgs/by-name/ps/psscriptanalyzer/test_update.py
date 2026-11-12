"""Check that release preparation cannot leave half an update behind."""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import update


class UpdateTests(unittest.TestCase):
    def test_failed_dependency_refresh_preserves_pins(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary)
            original = (update.PACKAGE / "source.nix").read_text()
            (package / "source.nix").write_text(original)
            (package / "deps.json").write_text("[]\n")
            with (
                patch.object(update, "PACKAGE", package),
                patch.object(update, "tag_commit", return_value="a" * 40),
                patch.object(
                    update, "prefetch", side_effect=["sha256-source", "sha256-help"]
                ),
                patch.object(
                    update,
                    "regenerate_deps",
                    side_effect=RuntimeError("restore failed"),
                ),
                self.assertRaisesRegex(RuntimeError, "restore failed"),
            ):
                update.main(["--version", "1.26.0"])
            self.assertEqual((package / "source.nix").read_text(), original)
            self.assertEqual((package / "deps.json").read_text(), "[]\n")

    def test_preview_refreshes_and_displays_dependencies_without_writing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary)
            original = (update.PACKAGE / "source.nix").read_text()
            (package / "source.nix").write_text(original)
            (package / "deps.json").write_text("[]\n")
            output = io.StringIO()
            with (
                patch.object(update, "PACKAGE", package),
                patch.object(update, "tag_commit", return_value="a" * 40),
                patch.object(
                    update, "prefetch", side_effect=["sha256-source", "sha256-help"]
                ),
                patch.object(
                    update,
                    "regenerate_deps",
                    side_effect=lambda staged: (staged / "deps.json").write_text(
                        '[{"candidate": true}]\n'
                    ),
                ) as regenerate,
                contextlib.redirect_stdout(output),
            ):
                self.assertEqual(update.main(["--version", "1.26.0", "--dry-run"]), 0)
            regenerate.assert_called_once()
            self.assertIn("candidate", output.getvalue())
            self.assertEqual((package / "deps.json").read_text(), "[]\n")
            self.assertEqual((package / "source.nix").read_text(), original)


if __name__ == "__main__":
    unittest.main()
