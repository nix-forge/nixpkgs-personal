"""Regression checks for running Soularr against a shared download client."""

import ast
import contextlib
import logging
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from typing import TYPE_CHECKING
from unittest.mock import Mock

if TYPE_CHECKING:
    from typing import Any

source = ast.parse(Path(sys.argv.pop(1)).read_text(encoding="utf-8"))
functions = ast.Module(
    body=[
        node
        for node in source.body
        if isinstance(node, ast.FunctionDef)
        and node.name
        in {
            "get_records",
            "cancel_and_delete",
            "slskd_do_enqueue",
            "prepare_lidarr_release",
            "process_completed_album",
            "downloaded_file_path",
        }
    ],
    type_ignores=[],
)


class LidarrConnectionError(ConnectionError):
    """Model Pyarr's transport failure."""


class HttpConnectionError(ConnectionError):
    """Model Requests' independent transport failure."""


class SharedClientTests(unittest.TestCase):
    def setUp(self):
        self.lidarr = Mock()
        self.slskd = Mock()
        self.scope: dict[str, Any] = {
            "lidarr": self.lidarr,
            "LIDARR_CONNECTION_ERRORS": (
                LidarrConnectionError,
                HttpConnectionError,
            ),
            "slskd": self.slskd,
            "page_size": 2,
            "search_type": "first_page",
            "logging": logging,
            "transfer_owner": Mock(),
            "peer_cooldowns": lambda: (None, {}),
            "cooldown_peer": Mock(),
            "logger": logging.getLogger("soularr-test"),
            "os": os,
            "shutil": shutil,
        }
        # Execute only selected functions from the pinned source under test.
        exec(compile(functions, "soularr.py", "exec"), self.scope)  # ruff: ignore[exec-builtin]
        self.wanted = {"id": 2, "title": "Album", "releases": [{"albumId": 2}]}
        self.lidarr.get_wanted.return_value = {
            "totalRecords": 1,
            "records": [self.wanted],
        }

    def test_queue_failure_does_not_start_duplicate_download(self):
        self.lidarr.get_queue.side_effect = LidarrConnectionError("offline")
        self.assertEqual(self.scope["get_records"](True), [])

    def test_incomplete_queue_does_not_start_duplicate_download(self):
        self.lidarr.get_queue.side_effect = [
            {"totalRecords": 2, "pageSize": 1, "records": [{"albumId": 1}]},
            LidarrConnectionError("second page offline"),
        ]
        self.assertEqual(self.scope["get_records"](True), [])

    def test_http_queue_failure_also_stops_downloads(self):
        self.lidarr.get_queue.side_effect = HttpConnectionError("offline")
        self.assertEqual(self.scope["get_records"](True), [])

    def test_queued_album_is_skipped(self):
        self.lidarr.get_queue.return_value = {
            "totalRecords": 1,
            "pageSize": 10,
            "records": [{"albumId": 2}],
        }
        self.assertEqual(self.scope["get_records"](True), [])

    def test_missing_album_without_download_is_selected(self):
        self.lidarr.get_queue.return_value = {
            "totalRecords": 0,
            "pageSize": 10,
            "records": [],
        }
        self.assertEqual(self.scope["get_records"](True), [self.wanted])

    def test_existing_transfer_is_not_adopted(self):
        self.slskd.transfers.get_all_downloads.return_value = [
            {
                "directories": [
                    {"directory": "Artist\\Album", "files": [{"id": "other"}]}
                ]
            }
        ]
        self.scope["slskd_download_dir"] = "/nonexistent-test-downloads"
        result = self.scope["slskd_do_enqueue"]("peer", [], "Artist\\Album")
        self.assertIsNone(result)
        self.slskd.transfers.enqueue.assert_not_called()

    def test_transfer_inspection_failure_does_not_enqueue(self):
        self.slskd.transfers.get_all_downloads.side_effect = ConnectionError("offline")
        self.scope["slskd_download_dir"] = "/nonexistent-test-downloads"
        self.assertIsNone(self.scope["slskd_do_enqueue"]("peer", [], "Album"))
        self.slskd.transfers.enqueue.assert_not_called()

    def test_owned_failed_transfer_can_retry(self):
        file = {"filename": "Artist\\Album\\track.flac", "size": 10, "id": "owned-id"}
        directory = {"directory": "Artist\\Album", "files": [file]}
        self.slskd.transfers.get_all_downloads.return_value = [
            {"directories": [directory]}
        ]
        self.slskd.transfers.get_downloads.return_value = {"directories": [directory]}
        self.slskd.transfers.enqueue.return_value = True
        self.scope["slskd_download_dir"] = "/nonexistent-test-downloads"
        self.scope["time"] = Mock()
        result = self.scope["slskd_do_enqueue"](
            "peer", [file], "Artist\\Album", owned_ids={"owned-id"}
        )
        self.assertEqual(result[0]["id"], "owned-id")
        self.slskd.transfers.enqueue.assert_called_once()

    def test_downloaded_edition_is_selected_for_import(self):
        album = {
            "anyReleaseOk": True,
            "releases": [{"id": 1, "monitored": True}, {"id": 2, "monitored": False}],
        }
        self.lidarr.get_album.return_value = album
        self.scope["prepare_lidarr_release"](42, 2)
        self.lidarr.upd_album.assert_called_once_with(album)
        self.assertEqual([r["id"] for r in album["releases"] if r["monitored"]], [2])

    def test_user_pinned_edition_is_preserved(self):
        self.lidarr.get_album.return_value = {
            "anyReleaseOk": False,
            "releases": [{"id": 1, "monitored": True}, {"id": 2, "monitored": False}],
        }
        with self.assertRaises(RuntimeError):
            self.scope["prepare_lidarr_release"](42, 2)
        self.lidarr.upd_album.assert_not_called()

    def test_rejected_enqueue_stops_before_trying_another_peer(self):
        self.slskd.transfers.get_all_downloads.return_value = []
        self.slskd.transfers.enqueue.return_value = False
        self.scope["slskd_download_dir"] = "/nonexistent-test-downloads"
        with self.assertRaises(SystemExit):
            self.scope["slskd_do_enqueue"](
                "peer", [{"filename": "Album\\track.flac", "size": 10}], "Album"
            )
        self.scope["transfer_owner"].begin.assert_called_once()

    def test_partial_enqueue_stops_until_restart_reconciliation(self):
        self.slskd.transfers.get_all_downloads.return_value = []
        self.slskd.transfers.get_downloads.return_value = {"directories": []}
        self.slskd.transfers.enqueue.return_value = True
        self.scope["slskd_download_dir"] = "/nonexistent-test-downloads"
        self.scope["time"] = Mock()
        with self.assertRaises(SystemExit):
            self.scope["slskd_do_enqueue"](
                "peer", [{"filename": "Album\\track.flac", "size": 10}], "Album"
            )
        self.scope["transfer_owner"].begin.assert_called_once()
        self.slskd.transfers.cancel_download.assert_not_called()

    def test_partial_readback_preserves_owned_transfer_for_recovery(self):
        files = [
            {"filename": "Album\\one.flac", "size": 10},
            {"filename": "Album\\two.flac", "size": 20},
        ]
        self.slskd.transfers.get_all_downloads.return_value = []
        self.slskd.transfers.get_downloads.return_value = {
            "directories": [
                {
                    "directory": "Album",
                    "files": [{"filename": files[0]["filename"], "id": "owned-id"}],
                }
            ],
        }
        self.slskd.transfers.enqueue.return_value = True
        self.scope["slskd_download_dir"] = "/nonexistent-test-downloads"
        self.scope["time"] = Mock()
        with self.assertRaises(SystemExit):
            self.scope["slskd_do_enqueue"]("peer", files, "Album")
        self.scope["transfer_owner"].begin.assert_called_once_with(
            "peer", files, "Album"
        )
        self.slskd.transfers.cancel_download.assert_not_called()

    @contextlib.contextmanager
    def _import_fixture(self, task, *, expires=False):
        cwd = Path.cwd()
        try:
            with tempfile.TemporaryDirectory() as directory:
                album_path = Path(directory) / "Album"
                album_path.mkdir()
                track = album_path / "track.flac"
                track.write_bytes(b"preserve download")
                self.scope.update({
                    "slskd_download_dir": directory,
                    "lidarr_download_dir": directory,
                    "rename_download_folders": False,
                    "lidarr_disable_sync": False,
                    "music_tag": Mock(),
                    "time": Mock(),
                })
                self.scope["music_tag"].load_file.side_effect = NotImplementedError
                self.scope["time"].monotonic.side_effect = [0, 301 if expires else 0]
                self.lidarr.get_album.return_value = {
                    "releases": [{"id": 2, "monitored": True}]
                }
                self.lidarr.post_command.return_value = {"id": 77}
                self.lidarr.get_command.return_value = {
                    "commandName": "DownloadedAlbumsScan",
                    "body": {"path": str(album_path)},
                    **task,
                }
                album = {
                    "album_id": 42,
                    "release_id": 2,
                    "title": "Album",
                    "artist": "Artist",
                    "year": "2026",
                    "files": [
                        {
                            "file_dir": "Artist\\Album",
                            "filename": "Artist\\Album\\track.flac",
                        }
                    ],
                }
                yield track, album
        finally:
            os.chdir(cwd)

    def test_unconfirmed_import_times_out_and_preserves_download(self):
        with self._import_fixture({"status": "started"}, expires=True) as (
            track,
            album,
        ):
            with self.assertRaises(TimeoutError):
                self.scope["process_completed_album"](album, [])
            self.assertEqual(track.read_bytes(), b"preserve download")
            self.scope["transfer_owner"].finish.assert_not_called()

    def test_unsuccessful_terminal_import_preserves_download_and_journal(self):
        for status in ["failed", "aborted", "cancelled", "orphaned"]:
            for message in [None, "", "Import stopped"]:
                with (
                    self.subTest(status=status, message=message),
                    self._import_fixture({"status": status, "message": message}) as (
                        track,
                        album,
                    ),
                ):
                    with self.assertRaises(RuntimeError):
                        self.scope["process_completed_album"](album, [])
                    self.assertEqual(track.read_bytes(), b"preserve download")
                    self.scope["transfer_owner"].finish.assert_not_called()

    def test_missing_completed_result_does_not_confirm_import(self):
        for task in [{"status": "completed"}, {"status": "completed", "message": None}]:
            with self.subTest(task=task), self._import_fixture(task) as (track, album):
                with self.assertRaises(RuntimeError):
                    self.scope["process_completed_album"](album, [])
                self.assertEqual(track.read_bytes(), b"preserve download")

    def test_confirmed_completed_import_returns_normally(self):
        with self._import_fixture({"status": "completed", "message": "Completed"}) as (
            track,
            album,
        ):
            self.scope["process_completed_album"](album, [])
            self.assertEqual(track.read_bytes(), b"preserve download")

    def test_failed_peer_is_skipped_before_enqueue(self):
        self.scope["peer_cooldowns"] = lambda: (None, {"peer": 9999999999})
        self.assertIsNone(self.scope["slskd_do_enqueue"]("peer", [], "Album"))
        self.slskd.transfers.enqueue.assert_not_called()

    def test_cancel_preserves_another_consumers_files(self):
        cwd = Path.cwd()
        try:
            with tempfile.TemporaryDirectory() as tmp:
                self.scope["slskd_download_dir"] = tmp
                directory = Path(tmp) / "Album"
                directory.mkdir()
                other = directory / "another-consumers-track.flac"
                other.write_bytes(b"preserve")
                self.scope["cancel_and_delete"]([
                    {
                        "username": "peer",
                        "id": "owned-id",
                        "filename": "own.flac",
                        "file_dir": "Artist\\Album",
                    },
                ])
                self.assertEqual(other.read_bytes(), b"preserve")
                self.scope["transfer_owner"].finish.assert_called_once()
                self.assertTrue(
                    self.scope["transfer_owner"].finish.call_args.kwargs["quarantine"]
                )

        finally:
            os.chdir(cwd)


unittest.main()
