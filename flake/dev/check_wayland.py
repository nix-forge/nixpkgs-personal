"""Check a native Wayland toplevel and presentation in an isolated compositor."""

import argparse
import json
import os
import re
import selectors
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Execute only the Nix-provided application path.
import sys
import time
from pathlib import Path

MAX_PROTOCOL_LINE = 1048576
MAX_PROTOCOL_OBJECTS = 256


def check(executable: str, expected_id: str, evidence: Path) -> None:
    """Require native protocol traffic, the correct desktop ID and a stable frame."""
    environment = os.environ.copy()
    environment.pop("DISPLAY", None)
    environment["WAYLAND_DEBUG"] = "client"
    process = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - The caller supplies a fixed store executable.
        [executable], env=environment, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE
    )
    try:
        _observe(process, expected_id, evidence)
    finally:
        stop(process)


def _observe(
    process: subprocess.Popen[bytes], expected_id: str, evidence: Path
) -> None:
    if process.stderr is None:
        raise RuntimeError("Missing protocol capture pipe")
    deadline = time.monotonic() + 45
    stable_until = None
    observer = ProtocolEvidence(expected_id)
    with selectors.DefaultSelector() as selector, evidence.open("wb") as output:
        selector.register(process.stderr, selectors.EVENT_READ)
        while process.poll() is None:
            now = time.monotonic()
            limit = (
                min(stable_until, deadline + 5)
                if stable_until is not None
                else deadline
            )
            if now >= limit:
                break
            # Block on protocol output or the bounded presentation deadline.
            ready = selector.select(limit - now)
            if not ready:
                continue
            chunk = os.read(process.stderr.fileno(), 65536)
            if not chunk:
                break
            output.write(chunk)
            generation = observer.generation
            qualified = observer.feed(chunk.decode(errors="replace"))
            if not qualified or observer.generation != generation:
                stable_until = None
            if qualified and stable_until is None:
                stable_until = time.monotonic() + 5
        if process.poll() is not None:
            raise RuntimeError(
                f"Application exited before verification: {process.returncode}"
            )
        if stable_until is None or time.monotonic() < stable_until:
            raise RuntimeError("No stable native Wayland presentation before deadline")
        sys.stdout.write(
            json.dumps({
                "app_id": expected_id,
                "native_wayland": True,
                "main_surface": observer.main_surface,
                "committed_buffer": True,
                "frame_callback_completed": True,
                "stable_seconds": 5,
            })
            + "\n"
        )


class ProtocolEvidence:
    """Retain bounded native presentation evidence for the identified main surface."""

    def __init__(self, expected_id: str) -> None:
        self.expected_id = expected_id
        self.seen: set[str] = set()
        self.pending = ""
        self.xdg_surfaces: dict[str, str] = {}
        self.toplevels: dict[str, str] = {}
        self.generation = 0
        self.main_surface: str | None = None
        self.main_toplevel: str | None = None
        self.attached = False
        self.callbacks: dict[str, bool] = {}

    def feed(self, chunk: str) -> bool:
        """Consume fresh protocol text, retaining incomplete lines and object links.

        Returns:
            Whether the identified main surface has committed a buffer and completed a frame.

        Raises:
            RuntimeError: If protocol input exceeds the bounded startup capture.

        """
        lines = (self.pending + chunk).split("\n")
        self.pending = lines.pop()
        if len(self.pending) > MAX_PROTOCOL_LINE:
            raise RuntimeError("Oversized Wayland protocol line")
        for line in lines:
            self._line(line)
        return {"registry", "app_id", "buffer", "frame"}.issubset(self.seen)

    @staticmethod
    def _remember(mapping: dict[str, str], key: str, value: str) -> None:
        """Retain surface links within the bounded startup probe.

        Raises:
            RuntimeError: If the client creates too many surface roles.

        """
        if key not in mapping and len(mapping) >= MAX_PROTOCOL_OBJECTS:
            raise RuntimeError("Too many Wayland surface roles for bounded probe")
        mapping[key] = value

    def _line(self, line: str) -> None:
        if re.search(r"wl_display[#@]\d+\.get_registry\(", line):
            self.seen.add("registry")
        self._roles(line)
        self._surface(line)
        if (
            match := re.search(r"wl_callback[#@](\d+)\.done\(", line)
        ) and self.callbacks.pop(match[1], False):
            self.seen.add("frame")

    def _roles(self, line: str) -> None:
        if match := re.search(
            r"get_xdg_surface\(new id xdg_surface[#@](\d+), wl_surface[#@](\d+)\)", line
        ):
            self._remember(self.xdg_surfaces, match[1], match[2])
        if match := re.search(
            r"xdg_surface[#@](\d+)\.get_toplevel\(new id xdg_toplevel[#@](\d+)\)", line
        ):
            self._remember(self.toplevels, match[2], match[1])
        if match := re.search(
            r'xdg_toplevel[#@](\d+)\.set_app_id\("([^"\n]*)"\)', line
        ):
            if match[2] == self.expected_id:
                surface = self.xdg_surfaces.get(self.toplevels.get(match[1], ""))
                if surface != self.main_surface:
                    self._reset_surface()
                self.main_surface = surface
                self.main_toplevel = match[1]
                if surface is not None:
                    self.seen.add("app_id")
            elif match[1] == self.main_toplevel:
                self._reset_surface()
        self._destroyed_role(line)

    def _reset_surface(self) -> None:
        self.generation += 1
        self.seen.difference_update({"app_id", "buffer", "frame"})
        self.main_surface = None
        self.main_toplevel = None
        self.attached = False
        self.callbacks.clear()

    def _destroyed_role(self, line: str) -> None:
        if match := re.search(
            r"(wl_surface|xdg_surface|xdg_toplevel)[#@](\d+)\.destroy\(", line
        ):
            role, identifier = match.groups()
            main = {
                "wl_surface": self.main_surface,
                "xdg_surface": self.toplevels.get(self.main_toplevel or ""),
                "xdg_toplevel": self.main_toplevel,
            }
            if identifier == main[role]:
                self._reset_surface()
            if role == "xdg_surface":
                self.xdg_surfaces.pop(identifier, None)
            elif role == "xdg_toplevel":
                self.toplevels.pop(identifier, None)

    def _surface(self, line: str) -> None:
        """Require a committed buffer and frame request on the identified main surface.

        Raises:
            RuntimeError: If the client exceeds the pending-frame bound.

        """
        if self.main_surface is None:
            return
        surface = re.escape(self.main_surface)
        if match := re.search(
            rf"wl_surface[#@]{surface}\.attach\((wl_buffer[#@]\d+|nil|null)", line
        ):
            self.attached = match[1].startswith("wl_buffer")
        if match := re.search(
            rf"wl_surface[#@]{surface}\.frame\(new id wl_callback[#@](\d+)\)", line
        ):
            if len(self.callbacks) >= MAX_PROTOCOL_OBJECTS:
                raise RuntimeError("Too many pending Wayland frame callbacks")
            self.callbacks[match[1]] = False
        if re.search(rf"wl_surface[#@]{surface}\.commit\(", line):
            if self.attached:
                self.seen.add("buffer")
                for callback in self.callbacks:
                    self.callbacks[callback] = True
            else:
                self.generation += 1
                self.seen.difference_update({"buffer", "frame"})
                self.callbacks.clear()


def stop(process: subprocess.Popen[bytes]) -> None:
    """Bound graceful shutdown, then reap a terminated process.

    Raises:
        RuntimeError: If the child ignores forced termination.

    """
    # A pidfd provides child-exit notification without timeout polling.
    if process.poll() is not None:
        return
    try:
        descriptor = os.pidfd_open(process.pid)
    except ProcessLookupError:
        # The child can exit between the status check and pidfd creation.
        process.wait()
        return
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(descriptor, selectors.EVENT_READ)
            process.terminate()
            if not selector.select(5):
                process.kill()
                if not selector.select(5):
                    raise RuntimeError("Wayland child did not exit after termination")
            process.wait()
    finally:
        os.close(descriptor)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable")
    parser.add_argument("app_id")
    parser.add_argument("evidence", type=Path)
    arguments = parser.parse_args()
    check(arguments.executable, arguments.app_id, arguments.evidence)
