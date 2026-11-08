"""Verify native Wayland evidence cannot be confused with sync or discarded logs."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

OBSERVER_PATH = (
    Path(sys.argv[1])
    if __name__ == "__main__" and len(sys.argv) > 1
    else Path(__file__).resolve().parents[1] / "flake/dev/check_wayland.py"
)
SPEC = importlib.util.spec_from_file_location("check_wayland", OBSERVER_PATH)
assert SPEC is not None
assert SPEC.loader is not None
OBSERVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OBSERVER)
APP_ID = "org.example.application"
INITIAL = (
    "wl_display#1.get_registry(new id wl_registry#2)\n"
    "xdg_wm_base#10.get_xdg_surface(new id xdg_surface#5, wl_surface#3)\n"
    "xdg_surface#5.get_toplevel(new id xdg_toplevel#4)\n"
    'xdg_toplevel#4.set_app_id("org.example.application")\n'
)
FRAME = (
    "wl_surface#3.attach(wl_buffer#6, 0, 0)\n"
    "wl_surface#3.frame(new id wl_callback#9)\n"
    "wl_surface#3.commit()\n"
    "wl_callback#9.done(1234)\n"
)


class WaylandEvidenceTests(unittest.TestCase):
    def test_surface_frame_excludes_registry_sync(self) -> None:
        observer = OBSERVER.ProtocolEvidence(APP_ID)
        self.assertFalse(
            observer.feed(
                INITIAL
                + "wl_surface#3.attach(wl_buffer#6, 0, 0)\nwl_surface#3.commit()\nwl_callback#2.done(1234)\n"
            )
        )
        self.assertNotIn("frame", observer.seen)

    def test_wrong_callback_or_prior_completion_does_not_present(self) -> None:
        for frame in [
            FRAME.replace("wl_callback#9.done", "wl_callback#8.done"),
            "wl_callback#9.done(1234)\n"
            + FRAME.split("wl_callback#9.done", maxsplit=1)[0],
        ]:
            self.assertFalse(OBSERVER.ProtocolEvidence(APP_ID).feed(INITIAL + frame))

    def test_wrong_desktop_id_is_rejected(self) -> None:
        self.assertFalse(
            OBSERVER.ProtocolEvidence("org.example.other").feed(INITIAL + FRAME)
        )

    def test_decoration_only_presentation_is_rejected(self) -> None:
        self.assertFalse(
            OBSERVER.ProtocolEvidence(APP_ID).feed(
                INITIAL + FRAME.replace("wl_surface#3", "wl_surface#7")
            )
        )

    def test_uncommitted_or_null_buffer_is_rejected(self) -> None:
        for frame in [
            FRAME.replace("wl_surface#3.commit()\n", ""),
            FRAME.replace("wl_buffer#6", "nil"),
        ]:
            self.assertFalse(OBSERVER.ProtocolEvidence(APP_ID).feed(INITIAL + frame))

    def test_main_surface_unmapping_or_destroy_clears_presentation(self) -> None:
        for event in [
            "wl_surface#3.attach(nil, 0, 0)\nwl_surface#3.commit()\n",
            "wl_surface#3.destroy()\n",
            "xdg_surface#5.destroy()\n",
            "xdg_toplevel#4.destroy()\n",
            'xdg_toplevel#4.set_app_id("org.example.other")\n',
        ]:
            observer = OBSERVER.ProtocolEvidence(APP_ID)
            self.assertTrue(observer.feed(INITIAL + FRAME))
            self.assertFalse(observer.feed(event))

    def test_same_chunk_remap_advances_presentation_generation(self) -> None:
        observer = OBSERVER.ProtocolEvidence(APP_ID)
        self.assertTrue(observer.feed(INITIAL + FRAME))
        generation = observer.generation
        self.assertTrue(
            observer.feed(
                "wl_surface#3.attach(nil, 0, 0)\nwl_surface#3.commit()\n" + FRAME
            )
        )
        self.assertGreater(observer.generation, generation)

    def test_replacement_main_surface_requires_its_own_frame(self) -> None:
        observer = OBSERVER.ProtocolEvidence(APP_ID)
        self.assertTrue(observer.feed(INITIAL + FRAME))
        replacement = (
            INITIAL
            .replace("wl_surface#3", "wl_surface#13")
            .replace("xdg_surface#5", "xdg_surface#15")
            .replace("xdg_toplevel#4", "xdg_toplevel#14")
        )
        self.assertFalse(observer.feed(replacement))
        self.assertEqual(observer.main_surface, "13")
        self.assertTrue(observer.feed(FRAME.replace("wl_surface#3", "wl_surface#13")))

    def test_at_object_ids_and_fragmented_lines_are_supported(self) -> None:
        observer = OBSERVER.ProtocolEvidence(APP_ID)
        transcript = (INITIAL + FRAME).replace("#", "@")
        for character in transcript:
            qualified = observer.feed(character)
        self.assertTrue(qualified)

    def test_evidence_survives_discarded_text_and_cross_chunk_callback(self) -> None:
        observer = OBSERVER.ProtocolEvidence(APP_ID)
        self.assertFalse(observer.feed(INITIAL))
        self.assertFalse(observer.feed("x" * 1048576 + "\n"))
        request, completion = FRAME.split("wl_callback#9.done", 1)
        self.assertFalse(observer.feed(request))
        self.assertTrue(observer.feed("wl_callback#9.done" + completion))
        self.assertTrue(observer.feed("unrelated\n"))


@unittest.skipUnless(hasattr(os, "pidfd_open"), "Linux child-exit notification")
class WaylandCleanupTests(unittest.TestCase):
    def test_capture_setup_failure_still_reaps_the_child(self) -> None:
        with (
            subprocess.Popen(
                [sys.executable, "-c", "import signal; signal.pause()"],
                stderr=subprocess.PIPE,
            ) as child,
            tempfile.TemporaryDirectory() as directory,
        ):
            with (
                patch.object(OBSERVER.subprocess, "Popen", return_value=child),
                self.assertRaises(FileNotFoundError),
            ):
                OBSERVER.check(
                    "unused", APP_ID, Path(directory) / "missing" / "capture"
                )
            self.assertIsNotNone(child.returncode)

    def test_cleanup_preserves_an_already_reaped_child(self) -> None:
        with subprocess.Popen([sys.executable, "-c", "pass"]) as child:
            child.wait()
            OBSERVER.stop(child)
            self.assertEqual(child.returncode, 0)

    def test_cleanup_terminates_and_reaps_a_live_child(self) -> None:
        with subprocess.Popen([
            sys.executable,
            "-c",
            "import signal; signal.pause()",
        ]) as child:
            OBSERVER.stop(child)
            self.assertIsNotNone(child.returncode)
            self.assertLess(child.returncode, 0)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
