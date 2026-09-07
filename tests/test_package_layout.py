"""Exercise helper drift checks against copied package files through the CLI."""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "tests/check-package-layout.py"


class HelperCopiesTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="package-layout-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        # Copy the real helpers without importing them or running real updaters.
        # This catches drift against the checked-in package inventory rather than
        # constructing a fixture from the checker's own comparison table.
        for package in (ROOT / "pkgs/by-name").glob("*/*"):
            target = self.root / package.relative_to(ROOT)
            target.mkdir(parents=True)
            (target / "package.nix").write_text("{ }: { }\n")
            (target / "README.md").write_text("Fixture package\n")
            for filename in (
                "update_support.py",
                "skills_updater.py",
                "unpack.py",
                "font_support.py",
            ):
                source = package / filename
                if source.exists():
                    shutil.copyfile(source, target / filename)

    def run_checker(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "-B", str(CHECKER), str(self.root)],
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )

    def test_specialized_font_helpers_are_allowed(self) -> None:
        apple = self.root / "pkgs/by-name/ap/apple-fonts/font_support.py"
        for relative in (
            "pkgs/by-name/ap/apple-color-emoji/font_support.py",
            "pkgs/by-name/tt/ttf-ms-win11-auto/font_support.py",
        ):
            self.assertNotEqual(apple.read_bytes(), (self.root / relative).read_bytes())
        result = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_changed_common_helper_is_rejected(self) -> None:
        relative = "pkgs/by-name/wo/wootility/update_support.py"
        helper = self.root / relative
        helper.write_text(helper.read_text() + "\nUPDATER_BEHAVIOR_CHANGED = True\n")
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"Divergent helper copy: {relative}", result.stderr)

    def test_missing_common_helper_is_rejected(self) -> None:
        relative = "pkgs/by-name/wo/wootility/update_support.py"
        (self.root / relative).unlink()
        result = self.run_checker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(relative, result.stderr)


if __name__ == "__main__":
    unittest.main()
