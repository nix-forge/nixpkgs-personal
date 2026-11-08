"""Exercise the runner's process boundary without QEMU or application builds."""

import json
import os
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

RUNNER = Path(__file__).resolve().parent / "scripts/run_emulated_ui_tests.py"
FAKE_EMULATOR = """#!{python}
import json, os, pathlib, subprocess, sys, time
args=sys.argv[1:]
mode=os.environ.get("FIXTURE_MODE", "ok")
if args == ["--version"]:
    print("qemu-aarch64 version " + ("11.1.1" if mode == "old" else "11.1.2"));sys.exit(0)
if "--list" in args:
    if mode == "empty": sys.exit(0)
    if mode == "duplicate": print("real_case: test\\nreal_case: test");sys.exit(0)
    if "--ignored" in args: print("upstream_ignored: test")
    else: print("real_case: test\\nupstream_ignored: test")
    sys.exit(0)
pathlib.Path("observed.json").write_text(json.dumps({{"args":args,"env":dict(os.environ)}}))
if mode in ("timeout", "leader_exit", "chatty_timeout"):
    child=subprocess.Popen([sys.executable,"-c","import sys,time;sys.stdout.write('N'*250000);sys.stdout.flush();time.sleep(60)"])
    pathlib.Path("child.pid").write_text(str(child.pid))
    print("started original fixture",flush=True)
    if mode == "leader_exit": sys.exit(0)
    time.sleep(60)
if mode == "overflow": print("X"*20000,flush=True);sys.exit(0)
print("running 2 tests")
print("test " + ("invented_case" if mode=="names" else "real_case") + " ... " + ("FAILED" if mode == "failure" else "ok"))
print("test upstream_ignored ... ignored")
if mode != "truncated":
    failed=mode=="failure"
    print("test result: {{}}. {{}} passed; {{}} failed; 1 ignored; 0 measured; {{}} filtered out; finished in 0.01s".format("FAILED" if failed else "ok",int(not failed),int(failed),int(mode=="filtered")))
sys.exit(101 if mode=="failure" else 0)
"""


class RunnerProcessTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.executable = self.root / "ARM executable with spaces"
        elf = bytearray(64)
        elf[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<HH", elf, 16, 2, 183)
        self.executable.write_bytes(elf)
        self.qemu = self.root / "explicit emulator"
        self.qemu.write_text(FAKE_EMULATOR.format(python=sys.executable))
        self.qemu.chmod(0o700)
        self.output = self.root / "result"

    def invoke(self, mode="ok", extra=()):
        env = os.environ | {
            "FIXTURE_MODE": mode,
            "DISPLAY": ":99",
            "LIGHTCRAFT_GPU": "1",
            "LIGHTCRAFT_TEST_TRACE": "1",
            "LIGHTCRAFT_PROFILE": "1",
            "XDG_DATA_DIRS": "/unsafe",
            "RAYON_NUM_THREADS": "99",
            "QEMU_CPU": "invalid",
        }
        result = subprocess.run(
            [
                sys.executable,
                str(RUNNER),
                "--qemu",
                str(self.qemu),
                "--executable",
                str(self.executable),
                "--output",
                str(self.output),
                "--expected-test-count",
                "2",
                *extra,
            ],
            env=env,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        return result, json.loads((self.output / "receipt.json").read_text())

    def test_full_suite_preserves_upstream_ignored_and_isolates_environment(self):
        result, receipt = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(receipt["success"])
        self.assertEqual(receipt["ignored"], ["upstream_ignored"])
        self.assertEqual(receipt["completedNames"], ["real_case", "upstream_ignored"])
        observed = json.loads((self.output / "observed.json").read_text())
        self.assertEqual(
            observed["args"][1:], ["--test-threads", "1", "--color", "never"]
        )
        env = observed["env"]
        self.assertEqual(env["LIGHTCRAFT_GPU"], "0")
        self.assertEqual(env["RAYON_NUM_THREADS"], "8")
        self.assertNotIn("DISPLAY", env)
        self.assertNotIn("LIGHTCRAFT_TEST_TRACE", env)
        self.assertNotIn("QEMU_CPU", env)
        self.assertNotIn("LIGHTCRAFT_PROFILE", env)
        self.assertNotIn("XDG_DATA_DIRS", env)
        self.assertEqual(Path(env["HOME"]).parent, self.output)
        self.assertEqual(Path(env["XDG_RUNTIME_DIR"]).stat().st_mode & 0o777, 0o700)

    def test_suite_failure_is_not_hidden_by_complete_summary(self):
        result, receipt = self.invoke("failure")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(receipt["summary"]["failed"], 1)
        self.assertEqual(receipt["stages"]["suite"]["exitCode"], 101)
        self.assertIn("FAILED", (self.output / "suite.log").read_text())

    def test_partial_or_filtered_summaries_are_not_success(self):
        for mode in ("truncated", "filtered"):
            with self.subTest(mode=mode):
                self.output = self.root / mode
                result, receipt = self.invoke(mode)
                self.assertEqual(result.returncode, 1)
                self.assertFalse(receipt["success"])

    def test_discovery_mismatch_stops_before_suite(self):
        result, receipt = self.invoke(extra=("--expected-test-count", "3"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("expected test count", receipt["error"])
        self.assertFalse((self.output / "observed.json").exists())

    def test_empty_and_duplicate_discovery_are_rejected_before_suite(self):
        for mode in ("empty", "duplicate"):
            with self.subTest(mode=mode):
                self.output = self.root / mode
                result, receipt = self.invoke(mode)
                self.assertEqual(result.returncode, 1)
                self.assertFalse(receipt["success"])
                self.assertFalse((self.output / "observed.json").exists())

    def test_memory_budget_rejects_63_and_accepts_upstream_minimum_64(self):
        command = [
            sys.executable,
            str(RUNNER),
            "--qemu",
            str(self.qemu),
            "--executable",
            str(self.executable),
            "--output",
            str(self.output),
            "--memory-mb",
            "63",
        ]
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=5, check=False
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("at least 64 MiB", result.stderr)
        self.assertFalse(self.output.exists())
        result, receipt = self.invoke(extra=("--memory-mb", "64"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(receipt["memoryMb"], 64)
        self.assertEqual(receipt["environment"]["LIGHTCRAFT_MEMORY_MB"], "64")

    def test_incompatible_emulator_is_rejected(self):
        result, receipt = self.invoke("old")
        self.assertEqual(result.returncode, 1)
        self.assertIn("11.1.2", receipt["error"])
        self.assertFalse((self.output / "observed.json").exists())

    def test_wrong_architecture_is_rejected_before_emulation(self):
        elf = bytearray(self.executable.read_bytes())
        struct.pack_into("<H", elf, 18, 62)
        self.executable.write_bytes(elf)
        result, receipt = self.invoke()
        self.assertEqual(result.returncode, 1)
        self.assertIn("ARM64", receipt["error"])
        self.assertFalse((self.output / "qemu-version.log").exists())

    def test_log_overflow_is_explicit_failure(self):
        result, receipt = self.invoke("overflow", ("--max-log-bytes", "4096"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("log byte budget", receipt["error"])
        self.assertTrue((self.output / "suite.receipt.json").exists())

    def test_fabricated_summary_does_not_hide_wrong_test_inventory(self):
        result, receipt = self.invoke("names")
        self.assertEqual(result.returncode, 1)
        self.assertIn("completed test names", receipt["error"])

    def test_exited_leader_does_not_leave_descendant_holding_output_pipe(self):
        result, receipt = self.invoke("leader_exit", ("--timeout-seconds", "1"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("TimeoutError", receipt["error"])
        self.assertLess(
            json.loads((self.output / "suite.receipt.json").read_text())[
                "elapsedSeconds"
            ],
            5,
        )

    def test_termination_signal_preserves_receipt_and_cleans_child(self):
        command = [
            sys.executable,
            str(RUNNER),
            "--qemu",
            str(self.qemu),
            "--executable",
            str(self.executable),
            "--output",
            str(self.output),
        ]
        with subprocess.Popen(
            command,
            env=os.environ | {"FIXTURE_MODE": "timeout"},
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        ) as child:
            deadline = time.monotonic() + 5
            while (
                not (self.output / "child.pid").exists() and time.monotonic() < deadline
            ):
                time.sleep(0.01)
            self.assertTrue((self.output / "child.pid").exists())
            child.send_signal(signal.SIGTERM)
            child.communicate(timeout=5)
            self.assertEqual(child.returncode, 1)
        receipt = json.loads((self.output / "receipt.json").read_text())
        self.assertFalse(receipt["success"])
        self.assertIn("SIGTERM", receipt["error"])

    def test_timeout_preserves_logs_and_terminates_descendants(self):
        result, receipt = self.invoke("timeout", ("--timeout-seconds", "1"))
        self.assertEqual(result.returncode, 1)
        self.assertIn("TimeoutError", receipt["error"])
        self.assertIn(
            "started original fixture", (self.output / "suite.log").read_text()
        )
        child = Path("/proc") / (self.output / "child.pid").read_text()
        if child.exists():
            # A zombie awaiting init reaping is not an executing escaped child.
            self.assertEqual((child / "stat").read_text().split(") ", 1)[1][0], "Z")


if __name__ == "__main__":
    unittest.main()
