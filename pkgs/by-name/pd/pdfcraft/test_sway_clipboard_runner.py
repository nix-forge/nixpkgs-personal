"""Prevent zero-test success from qualifying a native clipboard regression."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import ExitStack
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location(
    "clipboard_runner", Path(__file__).with_name("run_sway_clipboard.py")
)
assert spec is not None
assert spec.loader is not None
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class ExecutedRegressionTests(unittest.TestCase):
    def test_empty_filter_is_not_a_pass(self) -> None:
        self.assertFalse(
            runner.completed_expected_test(
                "running 0 tests\ntest result: ok. 0 passed; 0 failed; 0 ignored;\n"
            )
        )

    def test_another_test_cannot_qualify(self) -> None:
        self.assertFalse(
            runner.completed_expected_test(
                "running 1 test\ntest another_test ... ok\ntest result: ok. 1 passed; 0 failed; 0 ignored;\n"
            )
        )

    def test_exact_executed_regression_qualifies(self) -> None:
        self.assertTrue(
            runner.completed_expected_test(
                f"running 1 test\ntest {runner.TEST} ... ok\ntest result: ok. 1 passed; 0 failed; 0 ignored;\n"
            )
        )

    def test_interleaved_protocol_stderr_does_not_hide_a_real_pass(self) -> None:
        self.assertTrue(
            runner.completed_expected_test(
                f"running 1 test\ntest {runner.TEST} ... [protocol] buffer transfer\nok\ntest result: ok. 1 passed; 0 failed; 0 ignored;\n"
            )
        )


class ExportHandshakeTests(unittest.TestCase):
    def test_test_marker_alone_does_not_confirm_selection(self) -> None:
        peer = mock.Mock(output=bytearray(runner.EXPORT_MARKER), ready=False)
        self.assertFalse(runner.export_ready(peer))

    def test_selection_alone_does_not_confirm_source_test_phase(self) -> None:
        peer = mock.Mock(output=bytearray(), ready=True)
        self.assertFalse(runner.export_ready(peer))

    def test_source_marker_and_new_compositor_selection_confirm_export(self) -> None:
        peer = mock.Mock(output=bytearray(runner.EXPORT_MARKER), ready=True)
        self.assertTrue(runner.export_ready(peer))


class CompositorNotificationTests(unittest.TestCase):
    def test_backend_starting_is_not_compositor_readiness(self) -> None:
        self.assertIsNone(
            runner.compositor_socket("Starting backend on wayland display 'wayland-1'")
        )

    def test_running_notification_has_the_exact_display_name(self) -> None:
        self.assertEqual(
            runner.compositor_socket(
                "00:00:00 [INFO] Running compositor on wayland display 'wayland-1'"
            ),
            "wayland-1",
        )


class ClipboardOwnerNotificationTests(unittest.TestCase):
    def test_source_offer_alone_does_not_prove_compositor_selection(self) -> None:
        parser = runner.OwnerReadiness()
        self.assertFalse(
            parser.feed(
                'zwlr_data_control_source_v1#4.offer("image/png")\nzwlr_data_control_device_v1#3.set_selection(zwlr_data_control_source_v1#4)\n'
            )
        )

    def test_matching_compositor_offer_and_selection_qualify(self) -> None:
        parser = runner.OwnerReadiness()
        self.assertTrue(
            parser.feed(
                'zwlr_data_control_device_v1#3.set_selection(zwlr_data_control_source_v1#4)\nzwlr_data_control_offer_v1#8.offer("image/png")\nzwlr_data_control_device_v1#3.selection(zwlr_data_control_offer_v1#8)\n'
            )
        )

    def test_stale_or_wrong_offer_does_not_qualify(self) -> None:
        parser = runner.OwnerReadiness()
        self.assertFalse(
            parser.feed(
                'zwlr_data_control_offer_v1#8.offer("image/png")\nzwlr_data_control_device_v1#3.set_selection(zwlr_data_control_source_v1#4)\nzwlr_data_control_device_v1#3.selection(zwlr_data_control_offer_v1#8)\n'
            )
        )
        self.assertFalse(
            parser.feed(
                'zwlr_data_control_offer_v1#9.offer("image/png")\nzwlr_data_control_device_v1#3.selection(zwlr_data_control_offer_v1#10)\n'
            )
        )

    def test_ext_protocol_at_ids_and_fragmented_lines_qualify(self) -> None:
        parser = runner.OwnerReadiness()
        transcript = 'ext_data_control_device_v1@3.set_selection(ext_data_control_source_v1@4)\next_data_control_offer_v1@8.offer("image/png")\next_data_control_device_v1@3.selection(ext_data_control_offer_v1@8)\n'
        ready = False
        for character in transcript:
            ready = parser.feed(character)
        self.assertTrue(ready)


@unittest.skipUnless(hasattr(os, "pidfd_open"), "Linux child-exit notification")
class OwnedPeerCleanupTests(unittest.TestCase):
    def test_pidfd_completion_collects_output_without_timeout_polling(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, ExitStack() as stack:
            supervisor = runner.Supervisor(stack)
            peer = supervisor.spawn(
                [sys.executable, "-c", "print('complete')"],
                os.environ.copy(),
                Path(temporary) / "child.log",
            )
            self.assertEqual(supervisor.complete(peer, 5), b"complete\n")
            self.assertEqual(peer.process.returncode, 0)

    def test_capture_setup_failure_still_reaps_the_owned_child(self) -> None:
        original = subprocess.Popen
        children = []

        def capture(*args, **kwargs):
            child = original(*args, **kwargs)
            children.append(child)
            return child

        with tempfile.TemporaryDirectory() as temporary:
            with (
                self.assertRaises(FileNotFoundError),
                mock.patch.object(runner.subprocess, "Popen", side_effect=capture),
                ExitStack() as stack,
            ):
                supervisor = runner.Supervisor(stack)
                supervisor.spawn(
                    [sys.executable, "-c", "import signal; signal.pause()"],
                    os.environ.copy(),
                    Path(temporary) / "missing" / "child.log",
                )
            self.assertEqual(len(children), 1)
            self.assertIsNotNone(children[0].returncode)


if __name__ == "__main__":
    unittest.main()
