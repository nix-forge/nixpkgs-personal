"""Run the ignored PDF native clipboard regression with isolated protocol peers."""

import argparse
import json
import os
import re
import selectors
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Execute only explicit Nix-provided peers without a shell.
import sys
import tempfile
import time
from contextlib import ExitStack, suppress
from pathlib import Path

TEST = "create_ui::native_wayland_clipboard_tests::native_wayland_image_clipboard_creates_pdf_and_exports_png"
CAPTURE_LIMIT = 4 * 1024 * 1024
MAX_OFFERS = 256
OVERALL_SECONDS = 60
EXPORT_MARKER = b"ARTCRAFT_PDF_EXPORT_WAITING\n"


def completed_expected_test(text: str) -> bool:
    """Reject successful zero-test runs and require the exact regression to pass.

    Returns:
        Whether the named regression executed successfully.

    """
    return (
        re.search(r"(?m)^running 1 test$", text) is not None
        and re.search(rf"(?m)^test {re.escape(TEST)} \.\.\. ", text) is not None
        and "test result: ok. 1 passed; 0 failed; 0 ignored;" in text
    )


def export_ready(peer) -> bool:
    """Require both the source-test handshake and its new compositor selection.

    Returns:
        Whether the exact test has prepared a compositor-confirmed export.

    """
    return EXPORT_MARKER in peer.output and peer.ready


def compositor_socket(text: str) -> str | None:
    """Read the Sway server_run notification emitted after backend startup.

    Returns:
        The socket name, or None before the running notification.

    """
    match = re.search(r"Running compositor on wayland display '(wayland-\d+)'", text)
    return match[1] if match else None


class OwnerReadiness:
    """Require a compositor image offer/selection after the owner's set_selection."""

    def __init__(self) -> None:
        self.pending = ""
        self.sent_selection = False
        self.selected: str | None = None
        self.png_offers: set[str] = set()

    def feed(self, chunk: str) -> bool:
        lines = (self.pending + chunk).split("\n")
        self.pending = lines.pop()
        if len(self.pending) > CAPTURE_LIMIT:
            raise RuntimeError("Oversized clipboard protocol line")
        for line in lines:
            if re.search(
                r"(?:ext|zwlr)_data_control_device_v1[#@]\d+\.set_selection\(", line
            ):
                self.sent_selection = True
                self.selected = None
                self.png_offers.clear()
            if not self.sent_selection:
                continue
            if match := re.search(
                r'(?:ext|zwlr)_data_control_offer_v1[#@](\d+)\.offer\("image/png"\)',
                line,
            ):
                if len(self.png_offers) >= MAX_OFFERS:
                    raise RuntimeError("Too many clipboard offers")
                self.png_offers.add(match[1])
            if match := re.search(
                r"(?:ext|zwlr)_data_control_device_v1[#@]\d+\.selection\((?:ext|zwlr)_data_control_offer_v1[#@](\d+)\)",
                line,
            ):
                self.selected = match[1]
        return self.selected is not None and self.selected in self.png_offers


def stop(process: subprocess.Popen[bytes], *, own_group: bool = False) -> None:
    """Terminate and reap this owned child using bounded exit notifications.

    Raises:
        RuntimeError: If the owned child does not exit after forced termination.

    """
    if process.returncode is not None:
        return
    try:
        descriptor = os.pidfd_open(process.pid)
    except ProcessLookupError:
        process.wait()
        return
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(descriptor, selectors.EVENT_READ)
            if not selector.select(0):
                signal_peer(process, signal.SIGTERM, own_group=own_group)
            if not selector.select(5):
                signal_peer(process, signal.SIGKILL, own_group=own_group)
                if not selector.select(5):
                    raise RuntimeError("Clipboard fixture child did not exit")
            if own_group:
                kill_descendants(process)
            process.wait()
    finally:
        os.close(descriptor)


def signal_peer(
    process: subprocess.Popen[bytes], value: signal.Signals, *, own_group: bool
) -> None:
    # The child may exit between pidfd readiness and signalling. That race is benign.
    with suppress(ProcessLookupError):
        if own_group:
            os.killpg(process.pid, value)
        else:
            process.send_signal(value)


def kill_descendants(process: subprocess.Popen[bytes]) -> None:
    # Called before wait/reaping while the pidfd proves this group leader's identity.
    signal_peer(process, signal.SIGKILL, own_group=True)


def cleanup_peer(process: subprocess.Popen[bytes]) -> None:
    try:
        stop(process, own_group=True)
    finally:
        for pipe in [process.stdin, process.stdout, process.stderr]:
            if pipe is not None:
                pipe.close()


class Peer:
    def __init__(self, process: subprocess.Popen[bytes], log) -> None:
        self.process = process
        self.log = log
        self.output = bytearray()
        self.stderr = bytearray()
        self.captured = 0
        self.open_pipes = 2
        self.exited = False
        self.readiness = OwnerReadiness()
        self.ready = False
        self.socket_name: str | None = None

    def done(self) -> bool:
        return self.exited and self.open_pipes == 0


class Supervisor:
    """Drain protocol streams and wait on owned pidfds and selection notifications."""

    def __init__(self, stack: ExitStack) -> None:
        self.stack = stack
        self.selector = stack.enter_context(selectors.DefaultSelector())
        self.peers: list[Peer] = []
        self.deadline = time.monotonic() + OVERALL_SECONDS

    def spawn(
        self, command: list[str], environment: dict[str, str], log: Path, stdin=None
    ) -> Peer:
        process = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - Callers supply fixed store tools or the controlled Python test child.
            command,
            env=environment,
            stdin=stdin,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        self.stack.callback(cleanup_peer, process)
        output = self.stack.enter_context(log.open("wb"))
        peer = Peer(process, output)
        descriptor = os.pidfd_open(process.pid)
        self.stack.callback(os.close, descriptor)
        self.selector.register(descriptor, selectors.EVENT_READ, (peer, "exit"))
        for pipe, kind in [(process.stdout, "stdout"), (process.stderr, "stderr")]:
            if pipe is None:
                raise RuntimeError("Missing supervised capture pipe")
            self.selector.register(pipe, selectors.EVENT_READ, (peer, kind))
        self.peers.append(peer)
        return peer

    def wait_until(
        self, predicate, seconds: int, required: tuple[Peer, ...] = ()
    ) -> None:
        deadline = min(self.deadline, time.monotonic() + seconds)
        while not predicate():
            if any(peer.exited for peer in required):
                raise RuntimeError("Required clipboard peer exited before readiness")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("Clipboard fixture notification deadline exceeded")
            for key, _mask in self.selector.select(remaining):
                peer, kind = key.data
                if kind == "exit":
                    kill_descendants(peer.process)
                    peer.process.wait()
                    peer.exited = True
                    self.selector.unregister(key.fileobj)
                else:
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        self.selector.unregister(key.fileobj)
                        peer.open_pipes -= 1
                        continue
                    peer.captured += len(chunk)
                    if peer.captured > CAPTURE_LIMIT:
                        raise RuntimeError(
                            "Clipboard peer exceeded bounded protocol capture"
                        )
                    peer.log.write(chunk)
                    peer.log.flush()
                    if kind == "stdout":
                        peer.output.extend(chunk)
                    else:
                        peer.stderr.extend(chunk)
                        peer.socket_name = compositor_socket(
                            bytes(peer.stderr).decode(errors="replace")
                        )
                        peer.ready = peer.ready or peer.readiness.feed(
                            chunk.decode(errors="replace")
                        )

    def complete(
        self, peer: Peer, seconds: int, required: tuple[Peer, ...] = ()
    ) -> bytes:
        self.wait_until(peer.done, seconds, required)
        if any(required_peer.exited for required_peer in required):
            raise RuntimeError("Required clipboard peer exited before completion")
        if peer.process.returncode != 0:
            raise RuntimeError(
                f"Clipboard peer exited with status {peer.process.returncode}"
            )
        return bytes(peer.output)


def isolated_environment(root: Path, wl_paste: Path) -> dict[str, str]:
    environment = os.environ.copy()
    for key in ["DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET", "SWAYSOCK"]:
        environment.pop(key, None)
    for key, name in [
        ("HOME", "home"),
        ("XDG_RUNTIME_DIR", "runtime"),
        ("XDG_CONFIG_HOME", "config"),
        ("XDG_DATA_HOME", "data"),
        ("XDG_CACHE_HOME", "cache"),
        ("XDG_STATE_HOME", "state"),
    ]:
        directory = root / name
        directory.mkdir(mode=0o700)
        environment[key] = str(directory)
    environment.update({
        "WLR_BACKENDS": "headless",
        "WLR_HEADLESS_OUTPUTS": "1",
        "WLR_RENDERER": "pixman",
        "XDG_SESSION_TYPE": "wayland",
        "XDG_CURRENT_DESKTOP": "sway",
        "WAYLAND_DEBUG": "client",
    })
    environment["PATH"] = (
        str(wl_paste.parent) + os.pathsep + environment.get("PATH", "")
    )
    return environment


def run(args: argparse.Namespace) -> None:
    """Require data-control peers and the exact source test, without polling readiness.

    Raises:
        RuntimeError: If protocol readiness or the exact regression is absent.

    """
    args.evidence.mkdir(parents=True, exist_ok=False)
    with (
        tempfile.TemporaryDirectory(prefix="artcraft-pdf-clipboard-") as temporary,
        ExitStack() as stack,
    ):
        root = Path(temporary)
        environment = isolated_environment(root, args.wl_paste)
        config = root / "sway.conf"
        config.write_text(
            "xwayland disable\noutput * mode 1280x720\nseat seat0 fallback true\n",
            encoding="utf-8",
        )
        supervisor = Supervisor(stack)
        compositor = supervisor.spawn(
            [str(args.sway), "--verbose", "--unsupported-gpu", "--config", str(config)],
            environment,
            args.evidence / "compositor.log",
        )
        # Sway 1.11/1.12 emit this after backend startup, immediately before their
        # display event loop. A created socket alone can precede listen/startup.
        supervisor.wait_until(
            lambda: compositor.socket_name is not None, 15, (compositor,)
        )
        socket_name = compositor.socket_name
        if socket_name is None:
            raise RuntimeError("Missing compositor display notification")
        environment["WAYLAND_DISPLAY"] = socket_name
        globals_peer = supervisor.spawn(
            [str(args.wayland_info)], environment, args.evidence / "globals.log"
        )
        globals_text = supervisor.complete(globals_peer, 10, (compositor,)).decode(
            errors="replace"
        )
        manager = next(
            (
                name
                for name in [
                    "ext_data_control_manager_v1",
                    "zwlr_data_control_manager_v1",
                ]
                if name in globals_text
            ),
            None,
        )
        if manager is None or "wl_seat" not in globals_text:
            raise RuntimeError("Isolated compositor lacks data-control manager/seat")
        fixture = stack.enter_context(args.fixture.open("rb"))
        owner = supervisor.spawn(
            [str(args.wl_copy), "--foreground", "--type", "image/png"],
            environment,
            args.evidence / "owner.log",
            fixture,
        )
        supervisor.wait_until(lambda: owner.ready, 15, (compositor, owner))
        reader = supervisor.spawn(
            [str(args.wl_paste), "--type", "image/png", "--no-newline"],
            environment,
            args.evidence / "owner-ready.log",
        )
        if (
            supervisor.complete(reader, 10, (compositor, owner))
            != args.fixture.read_bytes()
        ):
            raise RuntimeError("External PNG bytes differ from the published fixture")
        test = supervisor.spawn(
            [str(args.test_executable), "--ignored", "--exact", TEST, "--nocapture"],
            environment,
            args.evidence / "test.log",
            subprocess.PIPE,
        )
        supervisor.wait_until(lambda: export_ready(test), 15, (compositor, test))
        acknowledgement = test.process.stdin
        if acknowledgement is None:
            raise RuntimeError("Missing source-test handshake pipe")
        acknowledgement.write(b"export-ready\n")
        acknowledgement.flush()
        acknowledgement.close()
        supervisor.complete(test, 45, (compositor,))
        if not completed_expected_test(bytes(test.output).decode(errors="replace")):
            raise RuntimeError(
                "Compiled executable did not run and pass the exact regression"
            )
        result = {
            "test": TEST,
            "data_control_manager": manager,
            "native_wayland": True,
            "external_png_roundtrip": True,
            "create_from_clipboard": True,
        }
        (args.evidence / "result.json").write_text(
            json.dumps(result, indent=2) + "\n", encoding="utf-8"
        )
        sys.stdout.write(json.dumps(result) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for option in [
        "sway",
        "wl-copy",
        "wl-paste",
        "wayland-info",
        "test-executable",
        "fixture",
        "evidence",
    ]:
        parser.add_argument("--" + option, type=Path, required=True)
    run(parser.parse_args())
