"""Load the installed Intro Skipper DLL with the selected isolated Jellyfin server."""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import re
import secrets
import shutil
import signal
import socket
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Raw ownership is necessary to retain the sole-waiter anchor until group cleanup.
import sys
import tempfile
from collections import deque
from contextlib import asynccontextmanager, suppress
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, override
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener
from uuid import UUID

if TYPE_CHECKING:
    from collections.abc import AsyncGenerator

PLUGIN_ID = "c83d86bb-a1e0-4c35-a113-e2101cf4ee6b"


def version_tuple(value: str) -> tuple[int, ...]:
    if re.fullmatch(r"\d+(?:\.\d+){1,3}", value) is None:
        raise ValueError("unexpected numeric package version")
    parts = tuple(map(int, value.split(".")))
    return parts + (0,) * (4 - len(parts))


def plugin_id(value: object) -> UUID | None:
    # Jellyfin's selected JsonGuidConverter writes the compact .NET N format.
    if (
        not isinstance(value, str)
        or re.fullmatch(
            r"[0-9a-fA-F]{32}|[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}",
            value,
        )
        is None
    ):
        return None
    return UUID(value)


def validate_plugins(records: object, expected_version: str) -> None:
    if not isinstance(records, list):
        raise TypeError("plugin API did not return a list")
    matches = [
        item
        for item in records
        if isinstance(item, dict) and plugin_id(item.get("Id")) == UUID(PLUGIN_ID)
    ]
    if len(matches) != 1:
        raise ValueError("expected exactly one actual Intro Skipper plugin identity")
    plugin = matches[0]
    if plugin.get("Name") != "Intro Skipper":
        raise ValueError("unexpected plugin name")
    actual_version = plugin.get("Version")
    if not isinstance(actual_version, str) or version_tuple(
        actual_version
    ) != version_tuple(expected_version):
        raise ValueError("loaded plugin version differs from the installed package")
    if plugin.get("Status") != "Active":
        raise ValueError("actual plugin is not Active")


def validate_log(text: str, dll: Path, expected_version: str) -> None:
    if any(
        marker in text
        for marker in (
            "Failed to load assembly",
            "Error registering plugin services",
            "Unable to find plugin in assembly",
            "ReflectionTypeLoadException",
            "MissingMethodException",
            "TypeLoadException",
            "Unable to resolve service for type",
            "Unexpected error while checking the installed FFmpeg version",
        )
    ):
        raise ValueError("actual assembly/type/service registration failed")
    signature = f"Loaded assembly IntroSkipper, Version={expected_version},"
    if not any(
        signature in line
        and re.search(rf"from \"?{re.escape(str(dll))}\"?\s*$", line) is not None
        for line in text.splitlines()
    ):
        raise ValueError("missing exact installed DLL assembly-load evidence")


class NoRedirect(HTTPRedirectHandler):
    @override
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Api:
    def __init__(self, port: int) -> None:
        self.address = f"http://127.0.0.1:{port}"
        self.opener = build_opener(ProxyHandler({}), NoRedirect())

    async def request(
        self, path: str, payload: object = None, token: str | None = None
    ) -> bytes:
        headers = {
            "Authorization": 'MediaBrowser Client="Package check", DeviceId="package-check", Device="Isolated fixture", Version="1"'
        }
        if token is not None:
            # Jellyfin 12 disables legacy X-Emby-Token authorization by default.
            headers["Authorization"] += ", Token=" + json.dumps(token)
        content = None if payload is None else json.dumps(payload).encode()
        if content is not None:
            headers["Content-Type"] = "application/json"
        # The only origin is the allocated loopback port; redirects/proxies are disabled.
        req = Request(self.address + path, data=content, headers=headers)  # ruff: ignore[suspicious-url-open-usage] - Fixed loopback origin; redirects and proxies disabled.

        def read() -> bytes:
            with self.opener.open(req, timeout=5) as response:
                result = response.read(1_048_577)
            if len(result) > 1_048_576:
                raise ValueError("fixture API response exceeds its limit")
            return result

        return await asyncio.to_thread(read)

    async def health(self) -> None:
        # HTTP readiness has no notification channel; retries have bounded backoff.
        deadline = asyncio.get_running_loop().time() + 20
        delay = 0.1
        while True:
            try:
                response = await self.request("/health")
            except HTTPError, URLError:
                if asyncio.get_running_loop().time() >= deadline:
                    raise
                await asyncio.sleep(delay)
                delay = min(delay * 2, 1.0)
            else:
                break
        if response.strip() != b"Healthy":
            raise ValueError("server health is not Healthy")

    async def authenticate(self) -> str:
        # Setup affects only this disposable data directory and loopback process.
        await self.request("/Startup/User")
        password = secrets.token_urlsafe(24)
        await self.request(
            "/Startup/User", {"Name": "plugin-check", "Password": password}
        )
        await self.request("/Startup/Complete", {})
        auth = json.loads(
            await self.request(
                "/Users/AuthenticateByName",
                {"Username": "plugin-check", "Pw": password},
            )
        )
        token = auth["AccessToken"]
        if not isinstance(token, str) or not token:
            raise ValueError("isolated fixture authentication failed")
        return token


@dataclass
class RunningServer:
    process: subprocess.Popen[bytes]
    lines: deque[str]
    started: asyncio.Event
    exit_task: asyncio.Task[int]
    output: asyncio.StreamReader
    owns_child: bool = True

    async def wait_started(self) -> None:
        startup_task = asyncio.create_task(self.started.wait())
        try:
            completed, _ = await asyncio.wait(
                {self.exit_task, startup_task},
                timeout=90,
                return_when=asyncio.FIRST_COMPLETED,
            )
        finally:
            startup_task.cancel()
            await asyncio.gather(startup_task, return_exceptions=True)
        if self.exit_task in completed:
            raise RuntimeError(
                f"selected server exited during startup ({self.exit_task.result()})"
            )
        if not self.started.is_set():
            raise TimeoutError("server did not report startup completion")

    async def capture(self) -> None:
        async for line in self.output:
            decoded = line.decode(errors="replace")
            self.lines.append(decoded)
            if "Startup complete" in decoded:
                self.started.set()

    def signal_group(self, signum: signal.Signals) -> None:
        # This sole waiter has not reaped the leader. Its live/zombie PID still
        # anchors the group, including when descendants closed the output pipe.
        if not self.owns_child:
            raise RuntimeError(
                "server ownership was released; group signaling forbidden"
            )
        os.waitid(os.P_PID, self.process.pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
        with suppress(ProcessLookupError):
            os.killpg(self.process.pid, signum)

    async def stop(self, capture: asyncio.Task[None] | None) -> None:
        try:
            self.signal_group(signal.SIGTERM)
            tasks = {self.exit_task} if capture is None else {self.exit_task, capture}
            _, pending = await asyncio.wait(tasks, timeout=10)
            # The server's unreaped leader remains the group identity anchor.
            self.signal_group(signal.SIGKILL)
            if pending:
                _, pending = await asyncio.wait(tasks, timeout=5)
            if capture in pending:
                capture.cancel()
                await asyncio.wait_for(
                    asyncio.gather(capture, return_exceptions=True), timeout=2
                )
            if self.exit_task in pending:
                self.exit_task.cancel()
                await asyncio.wait_for(
                    asyncio.gather(self.exit_task, return_exceptions=True), timeout=2
                )
            if pending:
                raise TimeoutError(
                    "owned server/session output did not finish after bounded shutdown"
                )
            self.exit_task.result()
            if capture is not None:
                result = capture.exception()
                if result is not None:
                    raise RuntimeError("server output capture failed") from result
        finally:
            # This is the sole reaper, after the last possible group signal.
            # ruff: ignore[wait-for-process-in-async-function] - WNOHANG is nonblocking; the sole reaper releases ownership only after final group signals.
            pid, status = os.waitpid(self.process.pid, os.WNOHANG)
            if pid != self.process.pid:
                raise RuntimeError("owned server did not exit before bounded reaping")
            self.process.returncode = os.waitstatus_to_exitcode(status)
            self.owns_child = False


def prepare(root: Path, dll: Path, plugin_version: str) -> tuple[Path, int]:
    plugin_root = root / "data/plugins" / f"IntroSkipper_{plugin_version}"
    plugin_root.mkdir(parents=True)
    installed = plugin_root / "IntroSkipper.dll"
    shutil.copyfile(dll, installed)
    if (
        hashlib.sha256(dll.read_bytes()).digest()
        != hashlib.sha256(installed.read_bytes()).digest()
    ):
        raise ValueError("plugin copy differs from the installed DLL")
    for name in ("config", "cache", "logs", "home"):
        (root / name).mkdir()
    with socket.socket() as available:
        available.bind(("127.0.0.1", 0))
        port = available.getsockname()[1]
    (root / "config/network.xml").write_text(
        f"""<NetworkConfiguration>
<InternalHttpPort>{port}</InternalHttpPort><PublicHttpPort>{port}</PublicHttpPort>
<EnableIPv4>true</EnableIPv4><EnableIPv6>false</EnableIPv6>
<EnableHttps>false</EnableHttps><EnableRemoteAccess>false</EnableRemoteAccess>
<EnableUPnP>false</EnableUPnP>
<LocalNetworkAddresses><string>127.0.0.1</string></LocalNetworkAddresses>
</NetworkConfiguration>"""
    )
    return installed, port


def _observed_exit_code(process: subprocess.Popen[bytes]) -> int:
    status = os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
    if status is None:
        raise RuntimeError("pidfd exit notification has no child status")
    return status.si_status if status.si_code == os.CLD_EXITED else -status.si_status


async def _observe_exit(process: subprocess.Popen[bytes]) -> int:
    # Linux pidfd readiness observes exit; WNOWAIT deliberately retains the PID.

    loop = asyncio.get_running_loop()
    descriptor = os.pidfd_open(process.pid)
    exited = loop.create_future()

    def ready() -> None:
        loop.remove_reader(descriptor)
        if exited.done():
            return
        try:
            code = _observed_exit_code(process)
            process.returncode = code
            exited.set_result(code)
        except BaseException as error:  # ruff: ignore[blind-except] - Publish observer errors to its owner instead of leaving an unfulfilled future.
            exited.set_exception(error)

    try:
        loop.add_reader(descriptor, ready)
        return await exited
    finally:
        loop.remove_reader(descriptor)
        os.close(descriptor)


async def _shield_cleanup(awaitable) -> bool:
    cleanup = asyncio.create_task(awaitable)
    cancelled = False
    while True:
        try:
            await asyncio.shield(cleanup)
        except asyncio.CancelledError:
            if cleanup.cancelled():
                raise
            cancelled = True
        else:
            return cancelled


@asynccontextmanager
async def launch(server: str, root: Path) -> AsyncGenerator[RunningServer]:
    environment = os.environ | {
        "HOME": str(root / "home"),
        "DOTNET_CLI_HOME": str(root / "home"),
        "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
    }
    # Popen ownership is acquired synchronously, before a cancellation point.
    # No asyncio transport or Popen poll/wait is allowed to reap this child.
    process = subprocess.Popen(  # ruff: ignore[create-subprocess-in-async-function, subprocess-without-shell-equals-true] - Atomic ownership before cancellation; asyncio transport reaping would release the group anchor.
        [
            server,
            "--datadir",
            str(root / "data"),
            "--configdir",
            str(root / "config"),
            "--cachedir",
            str(root / "cache"),
            "--logdir",
            str(root / "logs"),
            "--nowebclient",
        ],
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    output = asyncio.StreamReader()
    running = RunningServer(
        process,
        deque(maxlen=2000),
        asyncio.Event(),
        asyncio.create_task(_observe_exit(process)),
        output,
    )
    capture = None
    transport = None
    try:
        if process.stdout is None:
            raise RuntimeError("server output pipe is missing")
        transport, _ = await asyncio.get_running_loop().connect_read_pipe(
            lambda: asyncio.StreamReaderProtocol(output), process.stdout
        )
        capture = asyncio.create_task(running.capture())
        yield running
    finally:
        primary_failure = sys.exc_info()[1]
        try:
            cancelled = await _shield_cleanup(running.stop(capture))
            if cancelled and primary_failure is None:
                raise asyncio.CancelledError
        except (OSError, RuntimeError) as error:
            if primary_failure is None:
                raise
            sys.stderr.write(f"Secondary cleanup failure: {error}\n")
        finally:
            if transport is not None:
                transport.close()
            elif process.stdout is not None:
                process.stdout.close()


async def inspect(
    running: RunningServer,
    api: Api,
    dll: Path,
    plugin_version: str,
    server_version: str,
) -> None:
    await running.wait_started()
    validate_log("".join(running.lines), dll, plugin_version)
    await api.health()
    system = json.loads(await api.request("/System/Info/Public"))
    if version_tuple(system["Version"]) != version_tuple(server_version):
        raise ValueError("running server differs from the selected package version")
    token = await api.authenticate()
    validate_plugins(
        json.loads(await api.request("/Plugins", token=token)), plugin_version
    )
    validate_log("".join(running.lines), dll, plugin_version)
    if running.process.returncode is not None:
        raise RuntimeError("server exited after plugin validation")
    print(
        f"Intro Skipper {plugin_version} Active with Jellyfin {server_version}; installed DLL identity and service loading verified"
    )


async def check(
    server: str, dll: Path, plugin_version: str, server_version: str
) -> None:
    with tempfile.TemporaryDirectory(prefix="jellyfin-plugin-check-") as directory:
        root = Path(directory)
        installed, port = prepare(root, dll, plugin_version)
        async with launch(server, root) as running:
            try:
                await inspect(
                    running, Api(port), installed, plugin_version, server_version
                )
            finally:
                # Retain bounded diagnostics on failure, without API passwords/tokens.
                if sys.exc_info()[0] is not None:
                    sys.stderr.write("".join(running.lines)[-32768:])


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: check_jellyfin_plugin.py SERVER DLL PLUGIN_VERSION SERVER_VERSION"
        )
    asyncio.run(check(sys.argv[1], Path(sys.argv[2]), sys.argv[3], sys.argv[4]))


if __name__ == "__main__":
    main()
