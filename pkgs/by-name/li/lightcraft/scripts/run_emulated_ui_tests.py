"""Run an entire prebuilt ARM Linux libtest suite with an explicit QEMU.

Compilation is deliberately separate. Runtime library store paths must be declared
by the calling derivation; this helper neither binds host paths nor changes CPU
affinity. No test selection or skip options are accepted.
"""

import argparse
import asyncio
import contextlib
import hashlib
import json
import os
import re
import signal
import struct
import sys
import time
from pathlib import Path

ELF_HEADER_SIZE = 64
ARM64_MACHINE = 183
PROGRAM_HEADER_SIZE = 56
PT_INTERP = 3
MIN_QEMU = (11, 1, 2)
MIN_MEMORY_MB = 64
SUMMARY = re.compile(
    r"^test result: (ok|FAILED)\. (\d+) passed; (\d+) failed; (\d+) ignored; "
    r"(\d+) measured; (\d+) filtered out; finished in ([0-9.]+)s$"
)


def parse_listing(text):
    names = []
    for line in text.splitlines():
        if line.endswith(": test"):
            names.append(line.removesuffix(": test"))
        elif line.strip():
            raise ValueError(f"unexpected discovery output: {line!r}")
    if len(set(names)) != len(names):
        raise ValueError("duplicate discovered test names")
    return names


def parse_summary(text, discovered, ignored):
    summaries = [SUMMARY.fullmatch(line) for line in text.splitlines()]
    summaries = [match for match in summaries if match]
    if len(summaries) != 1:
        raise ValueError("expected exactly one complete libtest summary")
    match = summaries[0]
    counts = dict(
        zip(
            ["passed", "failed", "ignored", "measured", "filteredOut"],
            map(int, match.groups()[1:6]),
            strict=True,
        )
    )
    if not discovered or counts["filteredOut"] != 0:
        raise ValueError("zero tests or filtered tests are not a full suite")
    if sum(counts[key] for key in ("passed", "failed", "ignored", "measured")) != len(
        discovered
    ):
        raise ValueError("completed count differs from discovery")
    if counts["ignored"] != len(ignored):
        raise ValueError("ignored count differs from upstream discovery")
    if counts["measured"] or not (counts["passed"] + counts["failed"]):
        raise ValueError("expected a nonempty test suite, not benchmarks/all ignored")
    return counts | {"status": match[1], "seconds": float(match[7])}


def check_elf(path):
    data = path.read_bytes()
    if len(data) < ELF_HEADER_SIZE or data[:6] != b"\x7fELF\x02\x01":
        raise ValueError("expected a little-endian ELF64 executable")
    if struct.unpack_from("<H", data, 18)[0] != ARM64_MACHINE or data[7] not in {0, 3}:
        raise ValueError("expected an ARM64 Linux/SysV ELF executable")
    if struct.unpack_from("<H", data, 16)[0] not in {2, 3}:
        raise ValueError("ELF is not an executable or PIE")
    offset = struct.unpack_from("<Q", data, 32)[0]
    size, count = struct.unpack_from("<HH", data, 54)
    interpreter = None
    for index in range(count):
        entry = offset + index * size
        if size < PROGRAM_HEADER_SIZE or entry + size > len(data):
            raise ValueError("invalid ELF program headers")
        if struct.unpack_from("<I", data, entry)[0] == PT_INTERP:
            start = struct.unpack_from("<Q", data, entry + 8)[0]
            length = struct.unpack_from("<Q", data, entry + 32)[0]
            if start + length > len(data):
                raise ValueError("invalid ELF interpreter")
            interpreter = data[start : start + length].rstrip(b"\0").decode()
            if not interpreter.endswith("/ld-linux-aarch64.so.1"):
                raise ValueError("expected the ARM Linux dynamic interpreter")
    return {
        "sha256": hashlib.sha256(data).hexdigest(),
        "interpreter": interpreter,
        "bytes": len(data),
        "machine": "AArch64",
        "format": "ELF64 little-endian",
    }


async def capture(args, env, log, deadline, limit):
    started = time.monotonic()
    child = await asyncio.create_subprocess_exec(
        *args,
        cwd=log.parent,
        env=env,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        start_new_session=True,
    )
    reader = child.stdout
    if reader is None:
        child.kill()
        await child.wait()
        raise ValueError("subprocess output pipe was not created")
    written = 0
    error = None

    async def drain():
        nonlocal written
        with log.open("wb") as stream:
            while chunk := await reader.read(65536):
                written += len(chunk)
                if written > limit:
                    raise ValueError("log byte budget exceeded; output is incomplete")
                stream.write(chunk)
                stream.flush()
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
        return await child.wait()

    try:
        code = await asyncio.wait_for(drain(), timeout=deadline)
        return {
            "argv": args,
            "exitCode": code,
            "elapsedSeconds": time.monotonic() - started,
            "logBytes": written,
        }
    except (OSError, ValueError, TimeoutError, asyncio.CancelledError) as exception:
        error = f"{type(exception).__name__}: {exception}"
        raise
    finally:
        # Reap on success and failure, including children whose leader exited.
        # Kill before draining: a noisy timed-out process must not prolong cleanup.
        with contextlib.suppress(ProcessLookupError):
            os.killpg(child.pid, signal.SIGKILL)
        await reader.read()
        await child.wait()
        log.with_suffix(".receipt.json").write_text(
            json.dumps(
                {
                    "argv": args,
                    "exitCode": child.returncode,
                    "elapsedSeconds": time.monotonic() - started,
                    "logBytesObserved": written,
                    "error": error,
                },
                indent=2,
            )
            + "\n"
        )


async def run(options):
    output = options.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    receipt = {
        "success": False,
        "fullSuite": True,
        "testThreads": 1,
        "rayonThreads": options.rayon_threads,
        "memoryMb": options.memory_mb,
        "timeoutSeconds": options.timeout_seconds,
        "expectedTestCount": options.expected_test_count,
        "cpuAffinity": sorted(os.sched_getaffinity(0)),
        "stages": {},
    }
    loop = asyncio.get_running_loop()
    task = asyncio.current_task()
    if task is None:
        raise ValueError("runner must execute within an asyncio task")
    for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        loop.add_signal_handler(signum, task.cancel, f"received signal {signum.name}")
    try:
        await execute(options, output, receipt)
    except (OSError, ValueError, TimeoutError, asyncio.CancelledError) as error:
        receipt["error"] = f"{type(error).__name__}: {error}"
    finally:
        suite_log = output / "suite.log"
        if suite_log.exists():
            outcomes = re.findall(
                r"^test (.+?) \.\.\. (ok|FAILED|ignored)(?:,.*)?$",
                suite_log.read_text(errors="replace"),
                re.MULTILINE,
            )
            receipt["outcomes"] = outcomes
            receipt["completedNames"] = [name for name, _status in outcomes]
        receipt["summaryComplete"] = "summary" in receipt
        receipt["incomplete"] = "summary" not in receipt
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if receipt["success"] else 1


async def execute(options, output, receipt):
    env = os.environ.copy()
    for name in list(env):
        if name in {
            "DISPLAY",
            "WAYLAND_DISPLAY",
            "DBUS_SESSION_BUS_ADDRESS",
        } or name.startswith((
            "LIGHTCRAFT_",
            "RAYON_",
            "RUST_TEST_",
            "QEMU_",
            "LD_",
            "XDG_",
        )):
            env.pop(name)
    for key, name in {
        "HOME": "home",
        "XDG_CONFIG_HOME": "config",
        "XDG_DATA_HOME": "data",
        "XDG_CACHE_HOME": "cache",
        "XDG_RUNTIME_DIR": "runtime",
        "XDG_STATE_HOME": "state",
    }.items():
        directory = output / name
        directory.mkdir(mode=0o700)
        env[key] = str(directory)
    env.update(
        LIGHTCRAFT_GPU="0",
        LIGHTCRAFT_MEMORY_MB=str(options.memory_mb),
        RAYON_NUM_THREADS=str(options.rayon_threads),
        RUST_TEST_THREADS="1",
    )
    receipt["environment"] = {
        key: value
        for key, value in env.items()
        if key.startswith(("LIGHTCRAFT_", "XDG_", "RAYON_", "RUST_TEST_"))
        or key == "HOME"
    }
    executable = options.executable.resolve(strict=True)
    qemu = options.qemu.resolve(strict=True)
    receipt["executable"] = str(executable)
    receipt["elf"] = check_elf(executable)
    receipt["qemu"] = str(qemu)
    version = await capture(
        [str(qemu), "--version"], env, output / "qemu-version.log", 30, 65536
    )
    version_text = (output / "qemu-version.log").read_text()
    found = re.search(r"qemu-aarch64 version (\d+)\.(\d+)\.(\d+)", version_text)
    if version["exitCode"] or not found or tuple(map(int, found.groups())) < MIN_QEMU:
        raise ValueError("explicit qemu-aarch64 >=11.1.2 is required")
    receipt["qemuVersion"] = version_text.strip()
    prefix = [str(qemu), str(executable)]
    for stage, extra in (("discovery", []), ("ignored", ["--ignored"])):
        log = output / f"{stage}.log"
        receipt["stages"][stage] = await capture(
            [*prefix, "--list", "--format", "terse", *extra],
            env,
            log,
            60,
            options.max_log_bytes,
        )
        if receipt["stages"][stage]["exitCode"]:
            raise ValueError(f"{stage} process failed")
        receipt[stage] = parse_listing(log.read_text())
    discovered, ignored = receipt["discovery"], receipt["ignored"]
    if not discovered or not set(ignored).issubset(discovered):
        raise ValueError("empty or inconsistent test discovery")
    if (
        options.expected_test_count is not None
        and len(discovered) != options.expected_test_count
    ):
        raise ValueError("discovery differs from expected test count")
    log = output / "suite.log"
    receipt["stages"]["suite"] = await capture(
        [*prefix, "--test-threads", "1", "--color", "never"],
        env,
        log,
        options.timeout_seconds,
        options.max_log_bytes,
    )
    text = log.read_text(errors="replace")
    receipt["summary"] = parse_summary(text, discovered, ignored)
    verify_outcomes(text, receipt, discovered, ignored)
    receipt["success"] = (
        receipt["stages"]["suite"]["exitCode"] == 0
        and receipt["summary"]["status"] == "ok"
        and receipt["summary"]["failed"] == 0
    )
    if not receipt["success"]:
        raise ValueError("full suite failed; see suite.log")


def verify_outcomes(text, receipt, discovered, ignored):
    outcomes = re.findall(
        r"^test (.+?) \.\.\. (ok|FAILED|ignored)(?:,.*)?$", text, re.MULTILINE
    )
    receipt["completedNames"] = [name for name, _status in outcomes]
    receipt["outcomes"] = outcomes
    names = receipt["completedNames"]
    if len(names) != len(discovered) or set(names) != set(discovered):
        raise ValueError("completed test names differ from discovery")
    for status, count in (
        ("ok", "passed"),
        ("FAILED", "failed"),
        ("ignored", "ignored"),
    ):
        if (
            sum(value == status for _name, value in outcomes)
            != receipt["summary"][count]
        ):
            raise ValueError("per-test outcomes differ from summary")
    if {name for name, status in outcomes if status == "ignored"} != set(ignored):
        raise ValueError("ignored test names differ from upstream discovery")


def positive(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def memory_budget(value):
    number = positive(value)
    if number < MIN_MEMORY_MB:
        raise argparse.ArgumentTypeError(
            "must be at least 64 MiB (the upstream minimum)"
        )
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qemu", type=Path, required=True)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-test-count", type=positive)
    parser.add_argument("--rayon-threads", type=positive, default=8)
    parser.add_argument("--memory-mb", type=memory_budget, default=1536)
    parser.add_argument("--timeout-seconds", type=positive, default=7200)
    parser.add_argument("--max-log-bytes", type=positive, default=256 * 1024 * 1024)
    return asyncio.run(run(parser.parse_args()))


if __name__ == "__main__":
    sys.exit(main())
