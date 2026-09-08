"""Inspect release archives without executing upstream code."""

import base64
import hashlib
import io
import struct
import unittest
import zipfile
from unittest import mock

import update


class ArchiveTests(unittest.TestCase):
    def archive(self, members):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            for name, contents in members:
                archive.writestr(name, contents)
        return stream.getvalue()

    def inspect(self, archive, system="darwin"):
        def download(_url, destination):
            destination.write_bytes(archive)

        with (
            mock.patch.object(update, "_download_file", side_effect=download),
            mock.patch("sys.platform", system),
            mock.patch("platform.machine", return_value="arm64"),
            mock.patch(
                "subprocess.run", side_effect=AssertionError("Executed upstream code")
            ),
        ):
            return update._validate_archive(
                "1.2.3", "https://example.invalid/release.zip"
            )

    def arm64(self):
        return update.MACHO_64_MAGIC + struct.pack("<I", update.CPU_TYPE_ARM64)

    def test_archive_hashed_without_execution(self):
        archive = self.archive([("remindctl", self.arm64())])
        expected = (
            "sha256-" + base64.b64encode(hashlib.sha256(archive).digest()).decode()
        )
        self.assertEqual(self.inspect(archive), expected)

    def test_static_inspection_is_portable(self):
        archive = self.archive([("remindctl", self.arm64())])
        self.assertEqual(self.inspect(archive, "linux"), self.inspect(archive))

    def test_unexpected_members_rejected(self):
        for members in [
            [],
            [("../remindctl", self.arm64())],
            [("remindctl", self.arm64()), ("extra", b"")],
        ]:
            with self.subTest(members=members), self.assertRaises(SystemExit):
                self.inspect(self.archive(members))

    def test_invalid_architecture_rejected(self):
        for contents in [
            b"short",
            b"notMachO",
            update.MACHO_64_MAGIC + struct.pack("<I", 0x01000007),
            update.MACHO_FAT_MAGIC + struct.pack(">I", 1),
        ]:
            with self.subTest(contents=contents), self.assertRaises(SystemExit):
                self.inspect(self.archive([("remindctl", contents)]))

    def test_corrupt_zip_rejected(self):
        with self.assertRaises(SystemExit):
            self.inspect(b"not a ZIP archive")


if __name__ == "__main__":
    unittest.main()
