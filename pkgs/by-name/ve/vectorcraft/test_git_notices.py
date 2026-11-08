"""Retain complete Git dependency notices and their referenced license trees."""

import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("scripts") / "install-git-notices.sh"
ROOT_NOTICES = {
    "LICENSE-MIT": b"Complete MIT terms\n",
    "LICENSE-APACHE": b"Complete Apache terms\n",
    "NOTICE": b"PDF terms: see licenses/pdf-writer/ and licenses/pdf-backend/\n",
    "ATTRIBUTION.md": b"Dependency authors\n",
}


class GitNoticesTest(unittest.TestCase):
    def _install(self, directory, files):
        dependency = directory / "dependency with spaces"
        dependency.mkdir()
        for name, content in files.items():
            path = dependency / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        metadata = directory / "sources.json"
        metadata.write_bytes(b'{"dependency": {"rev": "pinned"}}\n')
        text = SCRIPT.read_text()
        for key, value in {
            "pname": "example",
            "gitSources": shlex.quote(str(dependency)),
            "gitMetadata": shlex.quote(str(metadata)),
        }.items():
            text = text.replace(f"@{key}@", value)
        runner = directory / "install.sh"
        runner.write_text("set -euo pipefail\n" + text)
        output = directory / "output"
        result = subprocess.run(
            ["bash", str(runner)],
            env={**os.environ, "out": str(output)},
            capture_output=True,
            text=True,
            check=False,
        )
        installed = output / "share/doc/example/licenses/git"
        return result, installed, metadata

    def test_retains_nested_notices_with_original_paths_and_bytes(self):
        files = {
            **ROOT_NOTICES,
            "licenses/pdf-writer/LICENSE_MIT": b"Writer MIT copyright and terms\n",
            "licenses/pdf-writer/LICENSE_APACHE": b"Writer Apache copyright and terms\n",
            "licenses/pdf-writer/LICENSE-ICC.txt": b"ICC profile redistribution terms\n",
            "licenses/pdf-backend/assets/CGATS_LICENSE.txt": b"Colour fixture terms\n",
            "licenses/another component/LICENSE_MIT": b"Different component MIT terms\n",
        }
        with tempfile.TemporaryDirectory() as temporary:
            result, installed, metadata = self._install(Path(temporary), files)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                (installed / "sources.json").read_bytes(), metadata.read_bytes()
            )
            for name, content in files.items():
                path = installed / "dependency with spaces" / name
                self.assertTrue(path.is_file(), f"Missing dependency notice: {name}")
                self.assertEqual(path.read_bytes(), content)

    def test_supports_inputs_without_a_nested_license_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, installed, _ = self._install(Path(temporary), ROOT_NOTICES)
            self.assertEqual(result.returncode, 0, result.stderr)
            for name, content in ROOT_NOTICES.items():
                self.assertEqual(
                    (installed / "dependency with spaces" / name).read_bytes(), content
                )

    def test_still_rejects_missing_required_root_license(self):
        with tempfile.TemporaryDirectory() as temporary:
            result, _, _ = self._install(
                Path(temporary), {"LICENSE-MIT": b"MIT terms\n"}
            )
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
