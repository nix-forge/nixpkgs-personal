"""Check bounded loopback readiness, health, administration and graceful shutdown."""

from __future__ import annotations

import contextlib
import http.client
import json
import os
import re
import select
import selectors
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - fixed native package tools, checked args, no shell.
import sys
import tempfile
import time
from pathlib import Path


def wait_exit(process: subprocess.Popen[bytes], timeout: float) -> int:
    """Await an own child's exit using Linux pidfd or Darwin process notification.

    Returns:
        The child's final exit code.

    Raises:
        TimeoutError: The child does not exit before the bounded deadline.
        ProcessLookupError: Notification registration fails for a live child.
        ValueError: The host does not support the native notification mechanism.

    """
    if process.poll() is not None:
        return process.wait()
    if sys.platform == "linux":
        descriptor = os.pidfd_open(process.pid)
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(descriptor, selectors.EVENT_READ)
                if not selector.select(timeout):
                    raise TimeoutError("Server did not exit within its deadline")
        finally:
            os.close(descriptor)
    elif sys.platform == "darwin":
        with contextlib.closing(select.kqueue()) as queue:
            event = select.kevent(
                process.pid,
                filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                fflags=select.KQ_NOTE_EXIT,
            )
            try:
                events = queue.control([event], 1, timeout)
            except ProcessLookupError:
                if process.poll() is None:
                    raise
                return process.wait()
            if not events:
                raise TimeoutError("Server did not exit within its deadline")
    else:
        raise ValueError(f"Unsupported native service test platform: {sys.platform}")
    return process.wait()


def ready(process: subprocess.Popen[bytes], timeout: float) -> tuple[int, bytes]:
    """Await the actual listening log on a pipe, with no socket/sleep polling loop.

    Returns:
        The announced loopback port and captured readiness log.

    Raises:
        TimeoutError: No ready message arrives before the bounded deadline.
        ValueError: The log is missing, too large, or ends before readiness.

    """
    if process.stdout is None:
        raise ValueError("Server log pipe is missing")
    fd = process.stdout.fileno()
    os.set_blocking(fd, False)
    deadline = time.monotonic() + timeout
    log = bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(fd, selectors.EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise TimeoutError(f"Server readiness timed out: {bytes(log)!r}")
            data = os.read(fd, 4096)
            if not data:
                raise ValueError(f"Server exited before readiness: {bytes(log)!r}")
            log.extend(data)
            if len(log) > 65536:
                raise ValueError("Server exceeded the bounded readiness log")
            match = re.search(rb"listening on 127\.0\.0\.1:(\d+);", log)
            if match:
                os.set_blocking(fd, True)
                return int(match[1]), bytes(log)


def run(server: Path, *arguments: str) -> str:
    """Run a bounded native server administrative command.

    Returns:
        The successful command output.

    """
    return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - immutable executable and explicit argument list.
        [str(server), *arguments],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout


def check(package: Path, version: str) -> None:
    """Exercise only a temporary private server and stop it without leaving children.

    Raises:
        ValueError: A version, readiness, health or shutdown assertion fails.

    """
    server = package / "bin/figcraft-server"
    if run(server, "--version").strip() != f"figcraft-server {version}":
        raise ValueError("Unexpected server version")
    if "/healthz" not in run(server, "--help"):
        raise ValueError("Server help is incomplete")
    with tempfile.TemporaryDirectory(prefix="figcraft-server-") as temporary:
        data = Path(temporary) / "data"
        run(server, "check", "--data", str(data), "--listen", "127.0.0.1:0")
        environment = os.environ | {"RUST_LOG": "info", "RUST_LOG_STYLE": "never"}
        process = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - own native tool and temporary test state.
            [str(server), "serve", "--data", str(data), "--listen", "127.0.0.1:0"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=environment,
        )
        try:
            port, log = ready(process, 30)
            record = json.loads((data / "server.json").read_text())
            if record != {"listen": f"127.0.0.1:{port}", "pid": process.pid}:
                raise ValueError("Readiness log and administrative endpoint differ")
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
            try:
                connection.request("GET", "/healthz")
                response = connection.getresponse()
                if response.status != 200 or response.read(1024).strip() != b"ok":
                    raise ValueError("Server health probe failed")
            finally:
                connection.close()
            run(server, "files", "list", "--data", str(data))
            process.send_signal(signal.SIGTERM)
            if wait_exit(process, 15) != 0:
                raise ValueError("Server did not exit gracefully")
            if process.stdout is None:
                raise ValueError("Server log pipe is missing")
            log += process.stdout.read(65536)
            if b"stopped" not in log:
                raise ValueError("Server did not report completed shutdown")
            run(server, "check", "--data", str(data))
        finally:
            if process.poll() is None:
                process.kill()
                wait_exit(process, 5)
            if process.stdout is not None:
                process.stdout.close()


if __name__ == "__main__":
    check(Path(sys.argv[1]), sys.argv[2])
