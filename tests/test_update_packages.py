"""Check safe partial submission by the package updater dispatcher."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/update-packages.py"
SPEC = importlib.util.spec_from_file_location("update_packages", SCRIPT)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("could not load update-packages.py")
update_packages = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = update_packages
SPEC.loader.exec_module(update_packages)


class PartialUpdateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.updaters = {
            name: update_packages._PackageUpdater(
                name, Path(f"/example/{name}/update.py")
            )
            for name in ("first", "second")
        }

    def test_unchanged_failure_allows_successful_package_changes(self) -> None:
        with (
            patch.object(
                update_packages, "_discover_updaters", return_value=self.updaters
            ),
            patch.object(update_packages, "_run_updater", side_effect=[0, 1]),
            patch.object(
                update_packages,
                "_working_tree_snapshot",
                side_effect=[b"", b"", b"changed", b"changed", b"changed"],
            ),
        ):
            self.assertEqual(
                update_packages._main(["--all", "--keep-going", "--allow-partial"]), 0
            )

    def test_failed_updater_must_leave_tree_unchanged(self) -> None:
        with (
            patch.object(
                update_packages, "_discover_updaters", return_value=self.updaters
            ),
            patch.object(update_packages, "_run_updater", return_value=1),
            patch.object(
                update_packages,
                "_working_tree_snapshot",
                side_effect=[b"", b"", b"changed"],
            ),
        ):
            self.assertEqual(
                update_packages._main(["--all", "--keep-going", "--allow-partial"]), 1
            )

    def test_no_successful_changes_remains_failure(self) -> None:
        with (
            patch.object(
                update_packages, "_discover_updaters", return_value=self.updaters
            ),
            patch.object(update_packages, "_run_updater", return_value=1),
            patch.object(update_packages, "_working_tree_snapshot", return_value=b""),
        ):
            self.assertEqual(
                update_packages._main(["--all", "--keep-going", "--allow-partial"]), 1
            )


if __name__ == "__main__":
    unittest.main()
