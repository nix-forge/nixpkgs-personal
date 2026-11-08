"""Observe owned X11 application windows and process exit without polling."""

from __future__ import annotations

import contextlib
import os
import select
import signal
import sys
from pathlib import Path
from time import monotonic
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Generator
    from types import FrameType

from notification_process import defer_cancellation
from Xlib import X, display, error


def _windows(root, name: str) -> bool:
    for window in root.query_tree().children:
        try:
            window.change_attributes(
                event_mask=X.PropertyChangeMask | X.StructureNotifyMask
            )
            title = window.get_wm_name() or ""
            classes = window.get_wm_class() or ()
            matches = any(name in str(value).lower() for value in (title, *classes))
            if matches and window.get_attributes().map_state == X.IsViewable:
                return True
        except error.BadWindow:  # ruff: ignore[try-except-continue] -- Expected destruction race after subscription.
            # A destroyed window can disappear between the event and snapshot.
            continue
    return False


@contextlib.contextmanager
def _owned_child(executable: str, logfd: int) -> Generator[int]:
    pid = pidfd = None
    original_mask = signal.pthread_sigmask(signal.SIG_BLOCK, [])
    try:
        # Native spawn explicitly resets the child mask while parent ownership
        # establishment remains protected from Python cancellation handlers.
        with defer_cancellation():
            pid = os.posix_spawn(
                executable,
                [executable],
                os.environ,
                setsid=True,
                setsigmask=original_mask,
                setsigdef=tuple(
                    getattr(signal, name)
                    for name in ("SIGPIPE", "SIGXFZ", "SIGXFSZ")
                    if hasattr(signal, name)
                ),
                file_actions=[
                    (os.POSIX_SPAWN_DUP2, logfd, 1),
                    (os.POSIX_SPAWN_DUP2, logfd, 2),
                ],
            )
            pidfd = os.pidfd_open(pid)
        yield pidfd
    finally:
        with defer_cancellation():
            try:
                if pid is not None:
                    with contextlib.suppress(ProcessLookupError):
                        os.killpg(pid, signal.SIGKILL)
                    os.waitpid(pid, 0)
            finally:
                if pidfd is not None:
                    os.close(pidfd)


def _observe(connection, root, name: str, pidfd: int) -> None:
    deadline = monotonic() + 20
    while True:
        window_ready = _windows(root, name)
        remaining = deadline - monotonic()
        if remaining <= 0:
            raise TimeoutError("No application window appeared")
        if window_ready:
            break
        # Replies can queue events before the connection FD becomes readable.
        if not connection.pending_events():
            ready, _, _ = select.select([connection.fileno(), pidfd], [], [], remaining)
            if pidfd in ready:
                raise RuntimeError("Application exited before opening its window")
            if not ready:
                raise TimeoutError("No application window appeared")
        while connection.pending_events():
            connection.next_event()
            if monotonic() >= deadline:
                raise TimeoutError("Window observation deadline expired")
    if select.select([pidfd], [], [], 5)[0]:
        raise RuntimeError("Application exited during the survival interval")


def _check(executable: str) -> None:
    name = Path(executable).name.lower()
    with (
        contextlib.closing(display.Display()) as connection,
        Path(f"{name}.log").open("wb") as log,
    ):
        root = connection.screen().root
        root.change_attributes(event_mask=X.SubstructureNotifyMask)
        connection.sync()
        with _owned_child(executable, log.fileno()) as pidfd:
            _observe(connection, root, name, pidfd)
    sys.stdout.write(f"{name}: X11 window opened with software rendering\n")


def _terminate(number: int, _frame: FrameType | None) -> None:
    raise SystemExit(128 + number)


def main() -> None:
    """Keep the outer supervisor's interrupt effective even if inherited ignored."""
    signal.signal(signal.SIGINT, signal.default_int_handler)
    signal.signal(signal.SIGTERM, _terminate)
    signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGINT, signal.SIGTERM})
    for argument in sys.argv[1:]:
        _check(argument)


if __name__ == "__main__":
    main()
