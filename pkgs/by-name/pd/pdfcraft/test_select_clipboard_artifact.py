"""Verify only the exact executable PDF library test artifact can be installed."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "artifact_selector",
    Path(__file__).with_name("scripts") / "select_clipboard_artifact.py",
)
assert spec is not None
assert spec.loader is not None
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


class ArtifactSelectionTests(unittest.TestCase):
    def test_one_executable_library_artifact_is_selected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / "libtest"
            executable.write_text("test fixture", encoding="utf-8")
            executable.chmod(0o700)
            message = {
                "reason": "compiler-artifact",
                "target": {"name": "pdfcraft_ui_egui", "kind": ["lib"]},
                "profile": {"test": True},
                "executable": str(executable),
            }
            messages = root / "messages.json"
            messages.write_text(json.dumps(message) + "\n", encoding="utf-8")
            self.assertEqual(selector.select_artifact(messages), executable)

    def test_non_test_and_duplicate_artifacts_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / "libtest"
            executable.write_text("test fixture", encoding="utf-8")
            executable.chmod(0o700)
            message = {
                "reason": "compiler-artifact",
                "target": {"name": "pdfcraft_ui_egui", "kind": ["lib"]},
                "profile": {"test": True},
                "executable": str(executable),
            }
            messages = root / "messages.json"
            messages.write_text(
                json.dumps(message) + "\n" + json.dumps(message) + "\n",
                encoding="utf-8",
            )
            with self.assertRaises(RuntimeError):
                selector.select_artifact(messages)
            message["profile"]["test"] = False
            messages.write_text(json.dumps(message) + "\n", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                selector.select_artifact(messages)

    def test_non_executable_output_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            executable = root / "libtest"
            executable.write_text("test fixture", encoding="utf-8")
            executable.chmod(0o600)
            message = {
                "reason": "compiler-artifact",
                "target": {"name": "pdfcraft_ui_egui", "kind": ["lib"]},
                "profile": {"test": True},
                "executable": str(executable),
            }
            messages = root / "messages.json"
            messages.write_text(json.dumps(message) + "\n", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                selector.select_artifact(messages)


if __name__ == "__main__":
    unittest.main()
