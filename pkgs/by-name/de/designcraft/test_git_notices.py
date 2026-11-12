"""Preserve the actual license and notice files from every pinned Git input."""

import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("scripts") / "install-git-notices.sh"


class GitNoticesTest(unittest.TestCase):
    def _install(self, directory, files):
        dependency = directory / "dependency with spaces"
        dependency.mkdir()
        for name, content in files.items():
            (dependency / name).write_text(content)
        metadata = directory / "sources.json"
        metadata.write_text('{"dependency": {"rev": "pinned"}}\n')
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
        return result, output / "share/doc/example/licenses/git", metadata

    def test_preserves_single_and_dual_license_files_with_notices(self):
        for licenses in [
            ["LICENSE"],
            ["LICENSE.md"],
            ["COPYING"],
            ["LICENSE-MIT", "LICENSE-APACHE"],
        ]:
            with (
                self.subTest(licenses=licenses),
                tempfile.TemporaryDirectory() as temporary,
            ):
                files = dict.fromkeys(licenses, "License text\n")
                files.update({
                    "NOTICE": "Required notice\n",
                    "ATTRIBUTION.md": "Authors\n",
                })
                result, installed, metadata = self._install(Path(temporary), files)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    (installed / "sources.json").read_bytes(), metadata.read_bytes()
                )
                for name, content in files.items():
                    self.assertEqual(
                        (installed / "dependency with spaces" / name).read_text(),
                        content,
                    )

    def test_rejects_inputs_with_no_license_or_an_empty_license(self):
        for files in [{"NOTICE": "A notice is not a license\n"}, {"LICENSE": ""}]:
            with self.subTest(files=files), tempfile.TemporaryDirectory() as temporary:
                result, _, _ = self._install(Path(temporary), files)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
