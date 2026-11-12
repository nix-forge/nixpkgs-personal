"""Exercise updater publication failures using real temporary source files."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import update_transaction


class PublicationTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="update-publication-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / "source.nix"
        self.lock = self.root / "deps.json"
        self.source.write_text("old pin\n")
        self.lock.write_text("old lock\n")
        self.source.chmod(0o644)
        self.lock.chmod(0o640)

    def test_success_preserves_modes_and_uses_unique_temporaries(self) -> None:
        unrelated = self.root / ".source.nix.tmp"
        unrelated.write_text("unrelated")
        update_transaction.commit_files({
            self.source: "new pin\n",
            self.lock: b"new lock\n",
        })
        self.assertEqual(self.source.read_text(), "new pin\n")
        self.assertEqual(self.lock.read_text(), "new lock\n")
        self.assertEqual(self.source.stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.lock.stat().st_mode & 0o777, 0o640)
        self.assertEqual(unrelated.read_text(), "unrelated")
        self.assertEqual(set(self.root.iterdir()), {self.source, self.lock, unrelated})

    def test_second_publication_failure_restores_first_file(self) -> None:
        self._failed_publication(OSError("publication failed"))

    def test_interrupted_publication_restores_first_file(self) -> None:
        self._failed_publication(KeyboardInterrupt())

    def _failed_publication(self, error: BaseException) -> None:
        original = Path.replace

        def replace(path: Path, target: Path) -> Path:
            if target == self.lock:
                raise error
            return original(path, target)

        with patch.object(Path, "replace", replace), self.assertRaises(type(error)):
            update_transaction.commit_files({
                self.source: "new pin",
                self.lock: "new lock",
            })
        self.assertEqual(self.source.read_text(), "old pin\n")
        self.assertEqual(self.lock.read_text(), "old lock\n")
        self.assertEqual(set(self.root.iterdir()), {self.source, self.lock})
        self.assertEqual(self.source.stat().st_mode & 0o777, 0o644)

    def test_symlink_target_is_rejected(self) -> None:
        linked = self.root / "linked.nix"
        linked.symlink_to(self.source)
        with self.assertRaisesRegex(ValueError, "symlink"):
            update_transaction.commit_files({linked: "new pin"})
        self.assertEqual(self.source.read_text(), "old pin\n")

    def test_new_target_removed_after_later_failure(self) -> None:
        created = self.root / "new.json"
        original = Path.replace

        def replace(path: Path, target: Path) -> Path:
            if target == self.lock:
                raise OSError("failed")
            return original(path, target)

        with patch.object(Path, "replace", replace), self.assertRaises(OSError):
            update_transaction.commit_files({created: "{}", self.lock: "new lock"})
        self.assertFalse(created.exists())


if __name__ == "__main__":
    unittest.main()
