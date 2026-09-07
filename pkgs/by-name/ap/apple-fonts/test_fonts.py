"""Regression checks for source selection, archive imports and byte preservation."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from export import export
from font_support import install, inventory, sha256
from unpack import unpack
from update import inspect_source, select_assets


def asset(names: list[str], version: int, delivery: str = "macOS-download") -> dict:
    return {
        "_MasteredVersion": str(version),
        "__RelativePath": str(version),
        "FontInfo4": [
            {"PostScriptFontName": n, "PlatformDelivery": [delivery]} for n in names
        ],
    }


class SelectionTests(unittest.TestCase):
    def test_replacement_keeps_new_faces(self):
        old, new = asset(["Regular"], 1), asset(["Regular", "Bold"], 2)
        self.assertEqual(select_assets({"Assets": [old, new]}), [new])

    def test_partial_overlap_fails(self):
        with self.assertRaisesRegex(ValueError, "partial"):
            select_assets({
                "Assets": [
                    asset(["Regular", "Italic"], 1),
                    asset(["Regular", "Bold"], 2),
                ]
            })

    def test_platform_filter(self):
        ios, hidden, mac = (
            asset(["iOS"], 1, "iOS-download"),
            asset(["Hidden"], 1, "macOS-invisible"),
            asset(["Mac"], 1),
        )
        self.assertEqual(select_assets({"Assets": [ios, hidden, mac]}), [mac])

    def test_same_revision_conflict_fails(self):
        with self.assertRaisesRegex(ValueError, "same-version"):
            select_assets({"Assets": [asset(["Regular"], 1), asset(["Regular"], 1)]})

    def test_empty_catalog_fails(self):
        with self.assertRaisesRegex(ValueError, "no eligible"):
            select_assets({"Assets": []})


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_zip_traversal_rejected(self):
        archive = self.root / "bad.zip"
        with zipfile.ZipFile(archive, "w") as output:
            output.writestr("../outside", "bad")
        with self.assertRaisesRegex(ValueError, "Unsafe ZIP"):
            unpack(archive, self.root / "unpacked", "zip")
        self.assertFalse((self.root / "outside").exists())

    def test_mutable_download_keeps_old_cached_bytes(self):
        entry = {"name": "test", "kind": "dmg", "url": "https://example.test/font.dmg"}
        for data in [b"old archive", b"new archive"]:
            digest = hashlib.sha256(data).digest()
            previous = entry | {"hash": "sha256-" + base64.b64encode(digest).decode()}
            with patch("update.fetch", return_value=data):
                inspect_source(entry.copy(), self.root, previous)
        old = self.root / (hashlib.sha256(b"old archive").hexdigest() + ".dmg")
        self.assertEqual(old.read_bytes(), b"old archive")

    def test_tar_link_rejected(self):
        archive = self.root / "bad.tar"
        with tarfile.open(archive, "w") as output:
            info = tarfile.TarInfo("font.ttf")
            info.type = tarfile.SYMTYPE
            info.linkname = "/etc/passwd"
            output.addfile(info)
        with self.assertRaisesRegex(ValueError, "regular files"):
            unpack(archive, self.root / "unpacked", "tar")

    def test_tar_traversal_rejected(self):
        archive = self.root / "bad.tar"
        with tarfile.open(archive, "w") as output:
            info = tarfile.TarInfo("../outside")
            info.size = 1
            output.addfile(info, io.BytesIO(b"x"))
        with self.assertRaises(tarfile.FilterError):
            unpack(archive, self.root / "unpacked", "tar")

    def fixture(self) -> Path:
        path = Path(os.environ["FONT_FIXTURE"])
        source = self.root / "input"
        source.mkdir()
        (source / "Font.TTF").write_bytes(path.read_bytes())
        return source

    def test_deterministic_export_import_and_tamper_detection(self):
        source = self.fixture()
        first = export([source], [], self.root / "first.tar", "test")
        second = export([source], [], self.root / "second.tar", "test")
        self.assertEqual(first["hash"], second["hash"])
        root = unpack(self.root / "first.tar", self.root / "unpacked", "tar")
        output = self.root / "output"
        install(root, output, first)
        installed = next(output.glob("share/fonts/**/*.ttf"))
        self.assertEqual(sha256(installed), first["files"][0]["sha256"])
        (root / first["files"][0]["path"]).write_bytes(b"broken font")
        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
            install(root, self.root / "tampered", first)

    def test_extra_font_rejected(self):
        source = self.fixture()
        entry = {"name": "test", "files": inventory(source)}
        (source / "extra.ttf").write_bytes((source / "Font.TTF").read_bytes())
        with self.assertRaisesRegex(ValueError, "payload changed"):
            install(source, self.root / "output", entry)

    def test_single_font_fetch_preserves_bytes_and_identity(self):
        # Nix fetchers prefix names with a store hash; use a stable payload name.
        source = self.root / "store-hash-download"
        source.write_bytes(Path(os.environ["FONT_FIXTURE"]).read_bytes())
        root = unpack(source, self.root / "unpacked", "ttf")
        entry = {"name": "test", "files": inventory(root)}
        self.assertEqual(entry["files"][0]["path"], "font.ttf")
        install(root, self.root / "output", entry)
        target = self.root / "output/share/fonts/truetype/test/font.ttf"
        self.assertEqual(sha256(target), sha256(source))

    def test_otc_extension_preserves_collection_bytes(self):
        # Wrap a real TrueType face in a collection using fontTools.
        from fontTools.ttLib import TTCollection, TTFont

        source = self.root / "collection"
        source.mkdir()
        collection = TTCollection()
        collection.fonts = [TTFont(os.environ["FONT_FIXTURE"])]
        collection.save(source / "Font.OTC")
        entry = {"name": "test", "files": inventory(source)}
        install(source, self.root / "output", entry)
        target = next((self.root / "output").glob("share/fonts/**/*.ttc"))
        self.assertEqual(sha256(target), sha256(source / "Font.OTC"))
        self.assertEqual(
            json.loads((self.root / "output/share/doc/test/manifest.json").read_text()),
            entry,
        )


if __name__ == "__main__":
    unittest.main()
