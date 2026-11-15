"""Run updater metadata and no-update CLI paths with real Git and Nix."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PREFLIGHT = ROOT / ".github/scripts/check-updater-source.sh"


class UpdaterSourceTests(unittest.TestCase):
    def test_workflow_checks_metadata_before_shell_realization(self):
        workflow = (
            (ROOT / ".github/workflows/update-packages.yml")
            .read_text()
            .split("  update:\n", 1)[1]
        )
        self.assertIn(
            "fetch-depth: 0", workflow.split("      - name: Set up Nix", 1)[0]
        )
        self.assertLess(
            workflow.index("run: bash .github/scripts/check-updater-source.sh"),
            workflow.index("nix develop .#updater --command"),
        )

    def test_full_history_and_no_update(self):
        with tempfile.TemporaryDirectory(prefix="updater-source-") as temporary:
            root = Path(temporary) / "source"
            root.mkdir()

            def git(*args):
                return subprocess.check_output(
                    ["git", *args], cwd=root, text=True
                ).strip()

            git("init", "-q", "-b", "main")
            git("config", "user.name", "CI Test")
            git("config", "user.email", "ci@example.invalid")
            git("config", "core.hooksPath", "/dev/null")
            # A local input exercises locked Git metadata without network or builds.
            source = root / "nixpkgs"
            source.mkdir()
            (source / "flake.nix").write_text("{ outputs = { self }: {}; }")
            (source / "default.nix").write_text(
                '{}: { lib.version = "fixture"; callPackage = file: _: import file {}; }'
            )
            (root / "flake.nix").write_text(
                '{ inputs.nixpkgs.url = "path:./nixpkgs"; outputs = { self, nixpkgs }: {}; }'
            )
            package = root / "pkgs/by-name/de/demo"
            package.mkdir(parents=True)
            (package / "update.py").write_text(
                'import subprocess\nsubprocess.run(["nix", "eval", "--raw", "--expr", \'"current"\'], check=True)\n'
            )
            (root / "scripts").mkdir()
            shutil.copyfile(
                ROOT / "scripts/update_packages.py", root / "scripts/update_packages.py"
            )
            git("add", ".")
            git("-c", "commit.gpgsign=false", "commit", "-qm", "fixture")
            subprocess.run(
                ["nix", "flake", "lock"], cwd=root, check=True, capture_output=True
            )
            git("add", ".")
            git("-c", "commit.gpgsign=false", "commit", "-qm", "lock")
            env = os.environ | {"PWD": str(root)}
            result = subprocess.run(
                ["bash", str(PREFLIGHT)],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            before = git("status", "--porcelain")
            result = subprocess.run(
                [sys.executable, "scripts/update_packages.py", "--package", "demo"],
                cwd=root,
                env=env,
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("succeeded (1): demo", result.stdout)
            self.assertEqual(git("status", "--porcelain"), before)
            shallow = Path(temporary) / "shallow"
            subprocess.run(
                ["git", "clone", "-q", "--depth=1", root.as_uri(), str(shallow)],
                check=True,
            )
            result = subprocess.run(
                ["bash", str(PREFLIGHT)],
                cwd=shallow,
                env=env | {"PWD": str(shallow)},
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("full-history", result.stderr)


if __name__ == "__main__":
    unittest.main()
