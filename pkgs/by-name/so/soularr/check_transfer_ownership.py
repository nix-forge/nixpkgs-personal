"""Crash and partial enqueue recovery without affecting unrelated transfers."""

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from transfer_ownership import TransferOwnership


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.downloads = self.root / "downloads"
        self.downloads.mkdir()
        self.api = Mock()
        self.api.cancel_download.return_value = True
        self.file = {
            "filename": "Artist\\Album\\track.flac",
            "file_dir": "Artist\\Album",
            "username": "peer",
            "id": "owned",
        }

    def owner(self):
        return TransferOwnership(self.api, self.root, self.downloads)

    def snapshot(self):
        return [
            {
                "username": "peer",
                "directories": [
                    {
                        "files": [
                            self.file,
                            {"filename": "Other\\other.flac", "id": "other"},
                        ]
                    }
                ],
            }
        ]

    def test_restart_recovers_partial_enqueue_and_preserves_other_files(self):
        owner = self.owner()
        owner.begin(
            "peer",
            [self.file, {"filename": "Artist\\Album\\not-accepted.flac"}],
            "Artist\\Album",
        )
        directory = self.downloads / "Album"
        directory.mkdir()
        (directory / "track.flac").write_bytes(b"owned data")
        (directory / "another.flac").write_bytes(b"other consumer")
        self.api.get_all_downloads.return_value = self.snapshot()
        self.owner().recover()
        self.api.cancel_download.assert_called_once_with(
            username="peer", id="owned", remove=True
        )
        self.assertEqual((directory / "another.flac").read_bytes(), b"other consumer")
        self.assertEqual(
            next(
                (self.downloads / "failed_downloads").rglob("track.flac")
            ).read_bytes(),
            b"owned data",
        )
        self.assertEqual(self.owner().records, {})

    def test_restart_after_cancel_releases_directory_for_retry(self):
        owner = self.owner()
        owner.begin("peer", [self.file], "Artist\\Album")
        directory = self.downloads / "Album"
        directory.mkdir()
        (directory / "track.flac").write_bytes(b"partial")
        owner.finish([self.file], quarantine=True)
        self.owner().recover()
        self.assertFalse(directory.exists())
        self.assertEqual(self.owner().records, {})

    def test_api_outage_preserves_journal(self):
        owner = self.owner()
        owner.begin("peer", [self.file], "Artist\\Album")
        self.api.get_all_downloads.side_effect = ConnectionError("offline")
        with self.assertRaises(ConnectionError):
            self.owner().recover()
        self.assertTrue(self.owner().records)
        self.api.cancel_download.assert_not_called()

    def test_restart_after_remote_removal_finishes_quarantine(self):
        owner = self.owner()
        owner.records[owner.key("peer", self.file["filename"])] = {
            **self.file,
            "quarantine": True,
        }
        owner.save()
        directory = self.downloads / "Album"
        directory.mkdir()
        (directory / "track.flac").write_bytes(b"partial")
        self.api.get_all_downloads.return_value = []
        self.owner().recover()
        self.assertFalse(directory.exists())
        self.assertEqual(json.loads(owner.path.read_text()), {})


unittest.main()
