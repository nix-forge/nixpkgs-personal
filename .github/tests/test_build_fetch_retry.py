"""Exercise network recovery without invoking Nix or contacting upstreams."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "build-with-fetch-retry.sh"
FAKE_BUILD = """
import pathlib, sys
counter = pathlib.Path(sys.argv[1])
attempt = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(attempt))
print(sys.argv[2])
sys.exit(23 if attempt <= int(sys.argv[3]) else 0)
"""
NETWORK_FAILURE = (
    "curl: (6) Could not resolve host: github.com\n"
    "error: cannot download source from any mirror\n"
    "error: Cannot build '/nix/store/fixture-source.drv'.\n"
    "Reason: builder failed with exit code 1."
)


class BuildFetchRetryTests(unittest.TestCase):
    """Preserve failure status and retry only bounded source network failures."""

    def run_build(self, message: str, failures: int) -> tuple[int, int]:
        """Return wrapper status and the number of fake build invocations."""
        with tempfile.TemporaryDirectory() as directory:
            counter = Path(directory) / "attempts"
            result = subprocess.run(
                [
                    "bash",
                    str(SCRIPT),
                    sys.executable,
                    "-c",
                    FAKE_BUILD,
                    str(counter),
                    message,
                    str(failures),
                ],
                env=os.environ | {"FETCH_RETRY_DELAY_SECONDS": "0"},
                capture_output=True,
                check=False,
                timeout=10,
            )
            return result.returncode, int(counter.read_text())

    def test_success_runs_once(self) -> None:
        self.assertEqual(self.run_build("built", 0), (0, 1))

    def test_transient_dns_failure_recovers(self) -> None:
        self.assertEqual(self.run_build(NETWORK_FAILURE, 1), (0, 2))

    def test_persistent_dns_failure_stops(self) -> None:
        self.assertEqual(self.run_build(NETWORK_FAILURE, 9), (23, 3))

    def test_non_network_failures_are_not_retried(self) -> None:
        for message in (
            "compiler error",
            "hash mismatch in fixed-output derivation",
            "curl: (22) HTTP 404\nerror: cannot download source from any mirror",
            "curl: (6) Could not resolve host\ncompiler error",
            NETWORK_FAILURE + "\ncompiler error",
            NETWORK_FAILURE + "\nerror: hash mismatch in fixed-output derivation",
            NETWORK_FAILURE + "\nld: undefined reference to missing_symbol\n"
            "error: builder for '/nix/store/compiler.drv' failed with exit code 1",
            NETWORK_FAILURE + "\nld: undefined reference to missing_symbol\n"
            "error: Cannot build '/nix/store/compiler.drv'.\n"
            "Reason: builder failed with exit code 1.",
            "curl: (6) Could not resolve host\ncurl: (22) HTTP 404\n"
            "error: cannot download source from any mirror",
        ):
            with self.subTest(message=message):
                self.assertEqual(self.run_build(message, 9), (23, 1))


if __name__ == "__main__":
    unittest.main()
