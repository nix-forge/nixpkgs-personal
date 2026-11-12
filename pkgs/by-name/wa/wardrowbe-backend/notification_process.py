"""Complete owned POSIX commands without timed waitpid polling.

The caller owns a new process session. Exit observation retains the child's PID
until cleanup and reaping, even when descendants retain output pipes. This is a
narrow command API, not a replacement for all subprocess interfaces.
"""

# Fixed diagnostics are redacted; public docs include delegated exceptions.
# ruff: file-ignore[docstring-extraneous-exception]

from __future__ import annotations

import contextlib
import io
import os
import select
import selectors
import signal
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Caller-owned argument vectors, without a shell.
import sys
import threading
import time
from typing import TYPE_CHECKING, Literal, TypedDict, Unpack, overload

if TYPE_CHECKING:
    from collections.abc import Callable, Generator, Mapping, Sequence
    from typing import IO, Any, BinaryIO, TextIO


class _RunOptions(TypedDict, total=False):
    input: bytes | str | None
    capture_output: bool
    check: bool
    stdin: int | BinaryIO | TextIO | None
    stdout: int | BinaryIO | TextIO | None
    stderr: int | BinaryIO | TextIO | None
    env: Mapping[str, str] | None
    cwd: str | os.PathLike[str] | None
    encoding: str | None
    errors: str | None


@contextlib.contextmanager
def defer_cancellation() -> Generator[None]:
    """Defer Python signal handlers across owned resource cleanup.

    Apply only after launching children: new threads inherit the temporary mask.
    Pending handlers run on restoration after the ownership transition finishes.

    Yields:
        A cleanup scope protected against Python signal-handler exceptions.

    """
    handled = {
        number
        for number in signal.valid_signals()
        if callable(signal.getsignal(number))
    }
    previous = signal.pthread_sigmask(signal.SIG_BLOCK, handled)
    try:
        yield
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK, previous)


def _decoded(stream: IO[Any] | None, data: bytearray) -> bytes | str | None:
    if stream is None:
        return None
    result = bytes(data)
    if isinstance(stream, io.TextIOBase):
        return (
            result
            .decode(stream.encoding, stream.errors or "strict")
            .replace("\r\n", "\n")
            .replace("\r", "\n")
        )
    return result


class _ExitNotification:
    def __init__(self, pid: int) -> None:
        self.pid = pid
        self.reader, self.writer = os.pipe()
        self.failure: BaseException | None = None
        self.owns_child = True
        try:
            self.observer = threading.Thread(
                target=self._observe, name="command-exit", daemon=True
            )
        except BaseException:
            os.close(self.writer)
            os.close(self.reader)
            raise

    def _observe(self) -> None:
        try:
            os.waitid(os.P_PID, self.pid, os.WEXITED | os.WNOWAIT)
        except BaseException as error:  # ruff: ignore[blind-except] - Publish every observer failure; otherwise the owner cannot finish.
            self.owns_child = not isinstance(error, ChildProcessError)
            self.failure = error
        finally:
            os.write(self.writer, b"x")

    def close(self) -> None:
        try:
            if self.observer.ident is not None:
                self.observer.join()
        finally:
            try:
                os.close(self.writer)
            finally:
                os.close(self.reader)


def _encoded_input(
    process: subprocess.Popen[Any], payload: bytes | str | None
) -> bytes | None:
    if payload is not None and process.stdin is None:
        raise ValueError("Input requires an input pipe")
    if isinstance(payload, str):
        if not isinstance(process.stdin, io.TextIOBase):
            raise TypeError("Text input requires a text-mode input pipe")
        return payload.encode(process.stdin.encoding, process.stdin.errors or "strict")
    if payload is not None and isinstance(process.stdin, io.TextIOBase):
        raise TypeError("Text input requires a string")
    return payload


class _PipeExchange:
    def __init__(
        self,
        process: subprocess.Popen[Any],
        notification: _ExitNotification,
        payload: bytes | None,
        timeout: float | None,
        deadline: float | None,
    ) -> None:
        self.process = process
        self.notification = notification
        self.payload = payload
        self.timeout = timeout
        self.deadline = deadline
        self.offset = 0
        self.outputs = {"stdout": bytearray(), "stderr": bytearray()}
        self.streams = {"stdout": process.stdout, "stderr": process.stderr}

    def _register(self, selector: selectors.BaseSelector) -> None:
        selector.register(self.notification.reader, selectors.EVENT_READ, "exit")
        for name, stream in self.streams.items():
            if stream is not None:
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ, name)
        if self.process.stdin is not None:
            if self.payload:
                os.set_blocking(self.process.stdin.fileno(), False)
                selector.register(self.process.stdin, selectors.EVENT_WRITE, "stdin")
            else:
                self.process.stdin.close()

    def _ready(
        self, selector: selectors.BaseSelector
    ) -> list[tuple[selectors.SelectorKey, int]]:
        remaining = None if self.deadline is None else self.deadline - time.monotonic()
        if remaining is not None and remaining <= 0:
            self._expired()
        ready = selector.select(remaining)
        if not ready:
            self._expired()
        return ready

    def _expired(self) -> None:
        if self.timeout is None:
            raise RuntimeError("A blocking notification wait ended without a deadline")
        raise subprocess.TimeoutExpired(
            self.process.args,
            self.timeout,
            None if self.process.stdout is None else bytes(self.outputs["stdout"]),
            None if self.process.stderr is None else bytes(self.outputs["stderr"]),
        )

    def _write(
        self, selector: selectors.BaseSelector, key: selectors.SelectorKey
    ) -> None:
        if self.payload is None:
            raise RuntimeError("Input pipe was registered without input")
        try:
            self.offset += os.write(
                key.fd, self.payload[self.offset : self.offset + select.PIPE_BUF]
            )
        except BlockingIOError:
            return
        except BrokenPipeError:
            self.offset = len(self.payload)
        if self.offset == len(self.payload):
            selector.unregister(key.fileobj)
            stream = self.process.stdin
            if stream is not None:
                stream.close()

    def _read(
        self, selector: selectors.BaseSelector, key: selectors.SelectorKey
    ) -> None:
        try:
            chunk = os.read(key.fd, 65536)
        except BlockingIOError:
            return
        if chunk:
            self.outputs[key.data].extend(chunk)
        else:
            selector.unregister(key.fileobj)
            stream = self.streams[key.data]
            if stream is not None:
                stream.close()

    def _receive(
        self, selector: selectors.BaseSelector, key: selectors.SelectorKey
    ) -> None:
        if key.data == "exit":
            os.read(self.notification.reader, 1)
            selector.unregister(self.notification.reader)
            if self.notification.failure is not None:
                raise self.notification.failure
        elif key.data == "stdin":
            self._write(selector, key)
        else:
            self._read(selector, key)

    def exchange(self) -> tuple[Any, Any]:
        with selectors.DefaultSelector() as selector:
            self._register(selector)
            while selector.get_map():
                for key, _ in self._ready(selector):
                    self._receive(selector, key)
        return (
            _decoded(self.process.stdout, self.outputs["stdout"]),
            _decoded(self.process.stderr, self.outputs["stderr"]),
        )


def communicate(
    process: subprocess.Popen[Any],
    *,
    input: bytes | str | None = None,  # ruff: ignore[builtin-argument-shadowing] - Preserve the familiar subprocess keyword.
    timeout: float | None = None,
) -> tuple[Any, Any]:
    """Exchange pipe data and observe exit without reaping the owned child.

    On failure, kill its session before joining the observer. The caller must
    reap in a finally block. No other code may reap or poll this process during
    communication. All captured pipe descriptors belong to this operation.
    Joining retains ownership until the killed child exits; a kernel task in
    uninterruptible sleep can therefore delay cleanup beyond the deadline.

    Returns:
        Captured stdout and stderr, decoded for text-mode pipes.

    Raises:
        TypeError: Input does not match the pipe's text or binary mode.
        ValueError: Input was supplied without an input pipe.
        subprocess.TimeoutExpired: The communication deadline expired.
        OSError: A descriptor operation or child-exit observation failed.

    """
    deadline = None if timeout is None else time.monotonic() + timeout
    notification = None
    try:
        payload = _encoded_input(process, input)
        with defer_cancellation():
            notification = _ExitNotification(process.pid)
            notification.observer.start()
        return _PipeExchange(
            process, notification, payload, timeout, deadline
        ).exchange()
    finally:
        _close_resources(process, notification)


def _close_resources(
    process: subprocess.Popen[Any], notification: _ExitNotification | None
) -> None:
    """Attempt every owned close without hiding an active command failure."""
    primary = sys.exception()
    failures: list[BaseException] = []
    with defer_cancellation():
        if primary is not None and (notification is None or notification.owns_child):
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
        for stream in (process.stdin, process.stdout, process.stderr, notification):
            if stream is not None:
                try:
                    stream.close()
                except BaseException as error:  # ruff: ignore[blind-except] - Complete every owned cleanup before reporting failures.
                    failures.append(error)
        if failures and primary is None:
            raise failures[0]


def _prepare_options(
    options: _RunOptions, text: bool
) -> tuple[bytes | str | None, bool]:
    payload = options.pop("input", None)
    capture = options.pop("capture_output", False)
    check = options.pop("check", False)
    if payload is not None:
        if options.get("stdin") is not None:
            raise ValueError("Input and stdin cannot both be supplied")
        options["stdin"] = subprocess.PIPE
    if capture:
        if options.get("stdout") is not None or options.get("stderr") is not None:
            raise ValueError("Capture output conflicts with output destinations")
        options["stdout"] = subprocess.PIPE
        options["stderr"] = subprocess.PIPE
    if not text and (
        options.get("encoding") is not None or options.get("errors") is not None
    ):
        raise ValueError("Encoding options require text mode")
    return payload, check


def _communicate_until(
    process: subprocess.Popen[Any],
    payload: bytes | str | None,
    deadline: float | None,
    timeout: float | None,
) -> tuple[Any, Any]:
    remaining = None if deadline is None else deadline - time.monotonic()
    try:
        return communicate_and_reap(process, input=payload, timeout=remaining)
    except subprocess.TimeoutExpired as error:
        if timeout is not None:
            error.timeout = timeout
        raise


def _reap_owned(process: subprocess.Popen[Any]) -> int:
    with defer_cancellation():
        _, status = os.waitpid(process.pid, 0)
        process.returncode = os.waitstatus_to_exitcode(status)
    return process.returncode


def communicate_and_reap(
    process: subprocess.Popen[Any],
    *,
    input: bytes | str | None = None,  # ruff: ignore[builtin-argument-shadowing] - Preserve the familiar subprocess keyword.
    timeout: float | None = None,
) -> tuple[Any, Any]:
    """Exchange owned-session pipes and finish sole child reaping on every path.

    This has the same session and sole-ownership requirements as communicate.
    Failure terminates the owned group before joining and final reaping.

    Returns:
        Captured stdout and stderr, decoded for text-mode pipes.

    Raises:
        ChildProcessError: Another waiter violated sole child ownership.

    """
    owns_child = True
    try:
        return communicate(process, input=input, timeout=timeout)
    except ChildProcessError:
        owns_child = False
        raise
    finally:
        if owns_child:
            _reap_owned(process)


def _wait_pidfd(process: subprocess.Popen[Any], deadline: float | None) -> None:
    descriptor = None
    try:
        with defer_cancellation():
            descriptor = os.pidfd_open(process.pid)
        with selectors.DefaultSelector() as selector:
            selector.register(descriptor, selectors.EVENT_READ)
            remaining = (
                None if deadline is None else max(0, deadline - time.monotonic())
            )
            if not selector.select(remaining):
                raise TimeoutError
    finally:
        if descriptor is not None:
            with defer_cancellation():
                os.close(descriptor)


def _wait_kqueue(process: subprocess.Popen[Any], deadline: float | None) -> None:
    queue = None
    try:
        with defer_cancellation():
            queue = select.kqueue()
            queue.control(
                [
                    select.kevent(
                        signal.SIGCHLD,
                        filter=select.KQ_FILTER_SIGNAL,
                        flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                    )
                ],
                0,
                0,
            )
        while True:
            # Subscribe before the initial snapshot; subsequent snapshots only
            # follow SIGCHLD notifications, including exits of other children.
            status = os.waitid(
                os.P_PID, process.pid, os.WEXITED | os.WNOWAIT | os.WNOHANG
            )
            if status is not None:
                return
            remaining = None if deadline is None else deadline - time.monotonic()
            if remaining is not None and remaining <= 0:
                raise TimeoutError
            if not queue.control([], 1, remaining):
                raise TimeoutError
    finally:
        if queue is not None:
            with defer_cancellation():
                queue.close()


def _native_waiter() -> Callable[[subprocess.Popen[Any], float | None], None]:
    if sys.platform == "linux":
        return _wait_pidfd
    if sys.platform == "darwin":
        return _wait_kqueue
    raise NotImplementedError("Native child-exit readiness is unavailable")


def wait_child(process: subprocess.Popen[Any], timeout: float | None = None) -> int:
    """Wait on native exit readiness, leaving a timed-out child with its owner.

    Linux uses a pidfd; Darwin subscribes to SIGCHLD with kqueue. This does
    not exchange captured pipe data. Drain pipes separately or use
    communicate_and_reap for owned sessions. No other waiter may reap the child.

    Returns:
        The child's recorded exit code.

    Raises:
        subprocess.TimeoutExpired: The exit deadline expired; the child is still owned.
        NotImplementedError: The platform has no supported exit-readiness backend.
        RuntimeError: An untimed native wait ended without an exit notification.

    """
    if process.returncode is not None:
        return process.returncode
    deadline = None if timeout is None else time.monotonic() + timeout
    wait = _native_waiter()
    try:
        wait(process, deadline)
    except TimeoutError as error:
        if timeout is None:
            raise RuntimeError(
                "An untimed child-exit wait ended unexpectedly"
            ) from error
        raise subprocess.TimeoutExpired(process.args, timeout) from error
    return _reap_owned(process)


@overload
def run(
    arguments: Sequence[str | os.PathLike[str]],
    *,
    timeout: float | None = None,
    text: Literal[True],
    **options: Unpack[_RunOptions],
) -> subprocess.CompletedProcess[str]: ...


@overload
def run(
    arguments: Sequence[str | os.PathLike[str]],
    *,
    timeout: float | None = None,
    text: Literal[False] = False,
    **options: Unpack[_RunOptions],
) -> subprocess.CompletedProcess[bytes]: ...


def run(
    arguments: Sequence[str | os.PathLike[str]],
    *,
    timeout: float | None = None,
    text: bool = False,
    **options: Unpack[_RunOptions],
) -> subprocess.CompletedProcess[Any]:
    """Run one owned command, retaining ordinary result and timeout interfaces.

    Returns:
        The command's exit status and requested captured output.

    Raises:
        ValueError: Input or output options conflict.
        TypeError: Input does not match the selected pipe mode.
        subprocess.TimeoutExpired: The overall command deadline expired.
        subprocess.CalledProcessError: A checked command returned nonzero.
        OSError: Launch, communication, observation or reaping failed.
        ChildProcessError: Another waiter violated sole child ownership.

    """
    deadline = None if timeout is None else time.monotonic() + timeout
    payload, check = _prepare_options(options, text)
    process = subprocess.Popen(  # ruff: ignore[subprocess-without-shell-equals-true] - An owned argument vector, without a shell.
        arguments,
        text=text,
        start_new_session=True,
        stdin=options.get("stdin"),
        stdout=options.get("stdout"),
        stderr=options.get("stderr"),
        env=options.get("env"),
        cwd=options.get("cwd"),
        encoding=options.get("encoding"),
        errors=options.get("errors"),
    )
    stdout, stderr = _communicate_until(process, payload, deadline, timeout)
    result = subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)
    if check:
        result.check_returncode()
    return result
