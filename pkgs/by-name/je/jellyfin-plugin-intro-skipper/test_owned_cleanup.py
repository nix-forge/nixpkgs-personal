"""Real sole-waiter cleanup keeps the group PID owned until final signaling."""

import asyncio
import os
import signal
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import check_jellyfin_plugin as checker
import test_plugin_load


class OwnedCleanup(unittest.TestCase):
    def test_normal_exit_never_signals_reaped_group(self):
        async def exercise(root):
            command = test_plugin_load.LifecycleTests().executable(
                root,
                "import signal\nprint('Startup complete', flush=True)\nsignal.pause()\n",
            )
            real_signal = os.killpg
            signals = []

            def held_signal(pid, signum):
                # This actual waitid must still identify an owned child at each signal.
                os.waitid(os.P_PID, pid, os.WEXITED | os.WNOWAIT | os.WNOHANG)
                signals.append(signum)
                return real_signal(pid, signum)

            with patch.object(checker.os, "killpg", side_effect=held_signal):
                async with checker.launch(str(command), root) as running:
                    await running.wait_started()
                self.assertFalse(running.owns_child)
                with self.assertRaisesRegex(RuntimeError, "signaling forbidden"):
                    running.signal_group(signal.SIGKILL)
            self.assertEqual(signals, [signal.SIGTERM, signal.SIGKILL])
            with self.assertRaises(ChildProcessError):
                os.waitpid(running.process.pid, os.WNOHANG)  # ruff: ignore[wait-for-process-in-async-function] - WNOHANG checks ownership without yielding or blocking.
            self.assertTrue(running.exit_task.done())

        with tempfile.TemporaryDirectory() as temporary:
            asyncio.run(exercise(Path(temporary)))

    def test_early_exit_closed_stdout_term_ignoring_descendant_is_killed(self):
        async def exercise(root):
            marker = root / "descendant-pid"
            command = test_plugin_load.LifecycleTests().executable(
                root,
                f"""import os, signal
read_fd, write_fd = os.pipe()
if os.fork():
    os.close(write_fd)
    os.read(read_fd, 1)
    os._exit(0)
os.close(read_fd)
signal.signal(signal.SIGTERM, signal.SIG_IGN)
with open({str(marker)!r}, 'w') as output:
    output.write(str(os.getpid()))
os.close(1)
os.close(2)
os.write(write_fd, b'1')
os.close(write_fd)
signal.pause()
""",
            )
            descriptor = None
            try:
                async with checker.launch(str(command), root) as running:
                    self.assertEqual(await running.exit_task, 0)
                    # Exited server remains a kernel-owned unreaped child.
                    status = os.waitid(  # ruff: ignore[wait-for-process-in-async-function] - exit_task already observed exit; WNOWAIT only observes ownership.
                        os.P_PID, running.process.pid, os.WEXITED | os.WNOWAIT
                    )
                    assert status is not None
                    self.assertEqual(status.si_pid, running.process.pid)
                    descriptor = os.pidfd_open(int(marker.read_text()))
                loop = asyncio.get_running_loop()
                dead = loop.create_future()

                def died():
                    loop.remove_reader(descriptor)
                    if not dead.done():
                        dead.set_result(None)

                loop.add_reader(descriptor, died)
                try:
                    await asyncio.wait_for(dead, 5)
                finally:
                    loop.remove_reader(descriptor)
                self.assertFalse(running.owns_child)
                with self.assertRaises(ChildProcessError):
                    os.waitpid(running.process.pid, os.WNOHANG)  # ruff: ignore[wait-for-process-in-async-function] - WNOHANG checks ownership without yielding or blocking.
            finally:
                if descriptor is not None:
                    os.close(descriptor)

        with tempfile.TemporaryDirectory() as temporary:
            asyncio.run(exercise(Path(temporary)))

    def test_repeated_task_cancellation_finishes_owned_cleanup(self):
        async def exercise(root):
            command = test_plugin_load.LifecycleTests().executable(
                root,
                "import signal\nprint('Startup complete', flush=True)\nsignal.pause()\n",
            )
            ready = asyncio.Event()
            owned = []

            async def operation():
                async with checker.launch(str(command), root) as running:
                    owned.append(running)
                    await running.wait_started()
                    ready.set()
                    await asyncio.get_running_loop().create_future()

            before = set(asyncio.all_tasks())
            task = asyncio.create_task(operation())
            await asyncio.wait_for(ready.wait(), 5)
            task.cancel()
            asyncio.get_running_loop().call_soon(task.cancel)
            with self.assertRaises(asyncio.CancelledError):
                await asyncio.wait_for(task, 5)
            self.assertFalse(owned[0].owns_child)
            self.assertTrue(owned[0].exit_task.done())
            self.assertEqual({t for t in asyncio.all_tasks() if not t.done()}, before)
            with self.assertRaises(ChildProcessError):
                os.waitpid(owned[0].process.pid, os.WNOHANG)  # ruff: ignore[wait-for-process-in-async-function] - WNOHANG checks ownership without yielding or blocking.

        with tempfile.TemporaryDirectory() as temporary:
            asyncio.run(exercise(Path(temporary)))

    def test_cancellation_during_startup_leaves_no_notification_task(self):
        async def exercise(root):
            command = test_plugin_load.LifecycleTests().executable(
                root, "import signal\nsignal.pause()\n"
            )
            entered = asyncio.Event()
            owned = []

            async def operation():
                async with checker.launch(str(command), root) as running:
                    owned.append(running)
                    entered.set()
                    await running.wait_started()

            before = set(asyncio.all_tasks())
            task = asyncio.create_task(operation())
            await asyncio.wait_for(entered.wait(), 5)
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await asyncio.wait_for(task, 5)
            self.assertFalse(owned[0].owns_child)
            self.assertTrue(owned[0].exit_task.done())
            self.assertEqual({t for t in asyncio.all_tasks() if not t.done()}, before)
            with self.assertRaises(ChildProcessError):
                os.waitpid(owned[0].process.pid, os.WNOHANG)  # ruff: ignore[wait-for-process-in-async-function] - WNOHANG checks ownership without yielding or blocking.

        with tempfile.TemporaryDirectory() as temporary:
            asyncio.run(exercise(Path(temporary)))


if __name__ == "__main__":
    unittest.main()
