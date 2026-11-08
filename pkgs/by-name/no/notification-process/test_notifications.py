"""Check deadline, pipe, cancellation and ownership behavior of real children."""

from __future__ import annotations

import os
import select
import signal
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import notification_process
import pytest

if TYPE_CHECKING:
    from collections.abc import Callable

_FAILURE_STATUS = 7
_PORTABLE_PIPE_BUF = 512
FIXTURE = Path(__file__).with_name("fixtures") / "command.py"


def _command(mode: str) -> list[str]:
    return [sys.executable, str(FIXTURE), mode]


@pytest.mark.parametrize("payload", [b"", b"hello", b"x" * 100_000])
def test_input_is_delivered_and_eof_closes_the_pipe(payload: bytes) -> None:
    """Deliver complete binary input, including empty and backpressured payloads."""
    result = notification_process.run(
        _command("echo"), input=payload, capture_output=True, timeout=5
    )
    assert result.returncode == 0
    assert result.stdout == payload
    assert result.stderr == b""


def test_text_encoding_and_universal_newlines() -> None:
    """Decode the requested encoding and normalize text output line endings."""
    result = notification_process.run(
        _command("latin1"), text=True, encoding="latin1", capture_output=True, timeout=5
    )
    assert result.stdout == "é\n"
    assert not result.stderr


def test_merged_stderr() -> None:
    """Capture merged streams once and retain absent stderr semantics."""
    result = notification_process.run(
        _command("merged"), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=5
    )
    assert result.stdout == b"stdout\nstderr\n"
    assert result.stderr is None


def test_checked_exit_preserves_decoded_output() -> None:
    """Keep both decoded diagnostic streams on a checked exit failure."""
    with pytest.raises(subprocess.CalledProcessError) as captured:
        notification_process.run(
            _command("failure"), text=True, capture_output=True, check=True, timeout=5
        )
    assert captured.value.returncode == _FAILURE_STATUS
    assert captured.value.stdout == "output\n"
    assert captured.value.stderr == "diagnostic\n"


def test_closed_output_still_has_a_child_exit_deadline() -> None:
    """Bound exit after captured descriptors have already closed."""
    with pytest.raises(subprocess.TimeoutExpired) as captured:
        notification_process.run(
            _command("closed-pipes"), text=True, capture_output=True, timeout=1
        )
    assert captured.value.timeout == 1
    assert captured.value.stdout == b"ready\n"
    assert captured.value.stderr == b"diagnostic\n"


def test_exited_leader_cannot_leave_a_pipe_holding_descendant() -> None:
    """Terminate descendants while the exited leader still retains its identity."""
    with pytest.raises(subprocess.TimeoutExpired) as captured:
        notification_process.run(_command("descendant"), capture_output=True, timeout=1)
    output = captured.value.stdout
    assert output is not None
    child = int(output)
    if hasattr(os, "pidfd_open"):
        try:
            descriptor = os.pidfd_open(child)
        except ProcessLookupError:
            return
        try:
            assert select.select([descriptor], [], [], 1)[0]
        finally:
            os.close(descriptor)


def test_keyboard_interrupt_cleans_up_the_owned_command() -> None:
    """Reap the owned command when its caller receives an interrupt."""
    with pytest.raises(KeyboardInterrupt):
        notification_process.run(_command("interrupt"), capture_output=True, timeout=5)


def test_cwd_and_environment_are_preserved(tmp_path: Path) -> None:
    """Pass the exact working directory and environment to the child."""
    result = notification_process.run(
        _command("environment"),
        cwd=tmp_path,
        env={"FIXTURE_VALUE": "public fixture"},
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert result.stdout == f"{tmp_path}\npublic fixture\n"


def test_input_mode_errors_do_not_leave_a_running_child() -> None:
    """Clean up a launched child if input validation fails."""
    with pytest.raises(TypeError):
        notification_process.run(_command("closed-pipes"), input="text", timeout=5)


def test_conflicting_output_options_fail_before_launch() -> None:
    """Reject contradictory capture options before starting a program."""
    with pytest.raises(ValueError, match="Capture output conflicts"):
        notification_process.run(
            ["must-not-launch"], capture_output=True, stdout=subprocess.PIPE, timeout=5
        )


def test_notification_start_failure_reaps_the_child(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Clean up the child when its blocking observer cannot start."""

    def fail_start(_thread: object) -> None:
        message = "public start failure"
        raise OSError(message)

    monkeypatch.setattr(notification_process.threading.Thread, "start", fail_start)
    with pytest.raises(OSError, match="public start failure"):
        notification_process.run(
            _command("closed-pipes"), capture_output=True, timeout=5
        )


def test_final_reaping_uses_only_blocking_waitpid(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Reject repeated nonblocking exit probes in the final reaping path."""
    original: Callable[[int, int], tuple[int, int]] = os.waitpid
    observed: list[int] = []

    def waitpid(pid: int, options: int) -> tuple[int, int]:
        observed.append(options)
        return original(pid, options)

    monkeypatch.setattr(notification_process.os, "waitpid", waitpid)
    notification_process.run(
        _command("echo"), input=b"notification", capture_output=True, timeout=5
    )
    assert observed
    assert all(options == 0 for options in observed)


def test_writable_pipe_backpressure_retries_on_notification(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Respect the portable write guarantee and tolerate a readiness race."""
    original = os.write
    writes: list[int] = []
    blocked = False

    def write(descriptor: int, payload: bytes) -> int:
        nonlocal blocked
        if len(payload) > 1:
            writes.append(len(payload))
            if not blocked:
                blocked = True
                raise BlockingIOError
        return original(descriptor, payload)

    monkeypatch.setattr(notification_process.select, "PIPE_BUF", _PORTABLE_PIPE_BUF)
    monkeypatch.setattr(notification_process.os, "write", write)
    payload = b"portable input" * 10_000
    result = notification_process.run(
        _command("echo"), input=payload, capture_output=True, timeout=5
    )
    assert result.stdout == payload
    assert blocked
    assert max(writes) <= _PORTABLE_PIPE_BUF


def test_cancellation_during_observer_start_retains_cleanup_ownership(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Defer a pending interrupt until the observer is safely joinable."""
    original = notification_process.threading.Thread.start

    def start(thread: notification_process.threading.Thread) -> None:
        original(thread)
        os.kill(os.getpid(), signal.SIGINT)

    monkeypatch.setattr(notification_process.threading.Thread, "start", start)
    with pytest.raises(KeyboardInterrupt):
        notification_process.run(
            _command("closed-pipes"), capture_output=True, timeout=5
        )


def test_timeout_without_capture_preserves_absent_streams() -> None:
    """Report absent output streams without manufacturing captured bytes."""
    with pytest.raises(subprocess.TimeoutExpired) as captured:
        notification_process.run(
            _command("closed-pipes"),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=0.1,
        )
    assert captured.value.stdout is None
    assert captured.value.stderr is None


def test_native_wait_records_an_already_exited_child() -> None:
    """Observe a retained zombie with one immediate exit-readiness check."""
    process = subprocess.Popen(
        _command("failure"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOWAIT)
        assert notification_process.wait_child(process, timeout=0) == _FAILURE_STATUS
        assert process.returncode == _FAILURE_STATUS
    finally:
        if process.returncode is None:
            process.kill()
            process.wait()


def test_native_wait_timeout_leaves_child_with_its_owner() -> None:
    """Keep a timed-out child available for the owner's termination policy."""
    process = subprocess.Popen(
        _command("closed-pipes"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    try:
        with pytest.raises(subprocess.TimeoutExpired):
            notification_process.wait_child(process, timeout=0.1)
        assert process.returncode is None
        assert (
            os.waitid(os.P_PID, process.pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
            is None
        )
    finally:
        process.kill()
        assert notification_process.wait_child(process, timeout=5) == -signal.SIGKILL


def test_pipe_exchange_api_finishes_the_retained_child() -> None:
    """Reap an explicitly owned session after exchanging its complete pipes."""
    process = subprocess.Popen(
        _command("echo"),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    stdout, stderr = notification_process.communicate_and_reap(
        process, input=b"owned session", timeout=5
    )
    assert stdout == b"owned session"
    assert stderr == b""
    assert process.returncode == 0
