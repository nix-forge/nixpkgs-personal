"""Observe real fork allocation without replacing children or changing tests."""
import json
import os
from pathlib import Path

_native_fork = os.fork
# Retain the original builder-log descriptor before pytest starts capturing FDs.
_trace_fd = os.dup(2)


def snapshot(phase, error=None):
    result = {"phase": phase, "pid": os.getpid(), "error": error}
    for name in ["status", "limits"]:
        try:
            lines = Path("/proc/self", name).read_text().splitlines()
            if name == "status":
                lines = [line for line in lines if line.startswith(("Vm", "Rss", "Threads:"))]
            result[name] = lines
        except OSError as exc:
            result[name] = str(exc)
    try:
        result["mapsCount"] = len(Path("/proc/self/maps").read_text().splitlines())
        result["memory"] = [line for line in Path("/proc/meminfo").read_text().splitlines()
                            if line.startswith(("MemTotal:", "MemAvailable:", "SwapTotal:", "SwapFree:", "CommitLimit:", "Committed_AS:"))]
    except OSError as exc:
        result["memoryError"] = str(exc)
    for file in ["/proc/sys/vm/overcommit_memory", "/proc/sys/vm/overcommit_ratio",
                 "/sys/fs/cgroup/memory.max", "/sys/fs/cgroup/memory.current",
                 "/sys/fs/cgroup/memory.events", "/proc/self/cgroup"]:
        try:
            result[file] = Path(file).read_text().strip()
        except OSError as exc:
            result[file] = str(exc)
    os.write(_trace_fd, ("POSTHOG_FORK_RESOURCE " + json.dumps(result) + "\n").encode())


def traced_fork():
    try:
        snapshot("before-fork")
    except Exception as exc:
        os.write(_trace_fd, ("POSTHOG_FORK_RESOURCE observation error: " + str(exc) + "\n").encode())
    try:
        return _native_fork()
    except OSError as exc:
        snapshot("fork-error", exc.errno)
        raise


snapshot("python-start")
os.fork = traced_fork
