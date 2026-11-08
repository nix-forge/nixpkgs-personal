"""Environment ownership failures must stop the real wrapper before Cargo runs."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXPECTED_ARGUMENTS = [
    "test",
    "--offline",
    "--locked",
    "-p",
    "swc_native_addon",
    "--test",
    "format",
    "--test",
    "integrity",
]


def executable(name):
    path = shutil.which(name)
    if path is None:
        raise RuntimeError(f"Declared test executable is unavailable: {name}")
    return Path(path).resolve()


class Guard(unittest.TestCase):
    def fixture(self, *, guarded, valid_top):
        # A privileged test process must never make the foreign-root case own /
        # and reach chmod. The production verifier tests retain all native gates.
        if not valid_top and Path("/").stat().st_uid == os.geteuid():
            self.skipTest("No foreign-owned root for this invoking identity")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            environment = root / "environment.sh"
            environment.write_text(
                (HERE / "scripts/native-check-environment.sh")
                .read_text()
                .replace("@coreutils@", str(executable("realpath").parent.parent))
            )
            text = (HERE / "scripts/native-check-tests.sh").read_text()
            if not guarded:
                text = text.replace(" || exit $?", "")
            wrapper = root / "wrapper.sh"
            wrapper.write_text(text.replace("@environment@", str(environment)))
            marker = root / "called"
            cargo = root / "cargo"
            cargo.write_text(
                "#!"
                + str(executable("bash"))
                + '\nprintf "%s\\n" "$@" > "$CARGO_MARKER"\n'
            )
            cargo.chmod(0o700)
            result = subprocess.run(
                [str(executable("bash")), str(wrapper)],
                env=os.environ
                | {
                    "PATH": str(root) + os.pathsep + os.environ["PATH"],
                    "NIX_BUILD_TOP": str(root) if valid_top else "/",
                    "CARGO_MARKER": str(marker),
                },
                capture_output=True,
                text=True,
                check=False,
            )
            return result, marker.read_text().splitlines() if marker.exists() else None

    def test_old_wrapper_ignores_actual_ownership_rejection(self):
        result, cargo = self.fixture(guarded=False, valid_top=False)
        self.assertIn("workspace owned by the current builder", result.stderr)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(cargo, EXPECTED_ARGUMENTS)

    def test_new_wrapper_stops_before_cargo_on_actual_rejection(self):
        result, cargo = self.fixture(guarded=True, valid_top=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("workspace owned by the current builder", result.stderr)
        self.assertIsNone(cargo)

    def test_owned_environment_executes_every_original_test_argument(self):
        result, cargo = self.fixture(guarded=True, valid_top=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(cargo, EXPECTED_ARGUMENTS)


if __name__ == "__main__":
    unittest.main()
