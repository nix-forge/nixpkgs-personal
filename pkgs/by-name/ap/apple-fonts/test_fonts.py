"""Regression checks for source selection, archive imports and byte preservation."""

from __future__ import annotations

import base64
import bz2
import hashlib
import io
import json
import operator
import os
import struct
import subprocess
import tarfile
import tempfile
import unittest
import xml.etree.ElementTree as ET  # ruff: ignore[suspicious-xml-etree-import] - only constructs test fixtures
import zipfile
import zlib
from pathlib import Path
from unittest.mock import patch

from export import export
from font_support import install, inventory, sha256
from unpack import read_xar_toc, unpack, unpack_xar
from update import (
    developer_entries,
    inspect_source,
    select_assets,
    update,
)


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


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def test_developer_only_skips_catalog_download(self):
        old = {
            "catalog": "https://example.test/catalog",
            "catalogHash": "catalog-hash",
            "selection": ["macOS"],
            "sources": [
                {
                    "name": "catalog-asset",
                    "kind": "zip",
                    "url": "https://example.test/catalog-asset.zip",
                }
            ],
        }
        developer = developer_entries()
        with (
            patch("update.fetch") as fetch,
            patch("update.inspect_sources", return_value=developer),
        ):
            result = update(self.root, old, developers_only=True)
        fetch.assert_not_called()
        self.assertEqual(result["catalogHash"], "catalog-hash")
        self.assertEqual(
            result["sources"],
            sorted([old["sources"][0], *developer], key=operator.itemgetter("name")),
        )


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

    def test_xar_toc_rejects_oversized_and_entity_content(self):
        source = self.root / "package.pkg"
        small = zlib.compress(b"<xar/>")
        with self.assertRaisesRegex(ValueError, "too large"):
            read_xar_toc(small, 16 * 1024 * 1024 + 1, source)
        entity = b'<!DOCTYPE xar [<!ENTITY expanded "bad">]><xar>&expanded;</xar>'
        with self.assertRaisesRegex(ValueError, "Invalid XAR"):
            read_xar_toc(zlib.compress(entity), len(entity), source)

    def test_xar_members_with_zero_inodes_keep_their_bytes(self):
        toc = ET.Element("xar")
        table = ET.SubElement(toc, "toc")
        directory = ET.SubElement(table, "file", id="1")
        ET.SubElement(directory, "name").text = "Package"
        ET.SubElement(directory, "type").text = "directory"
        heap = bytearray()
        members = {
            "PackageInfo": (b'<pkg-info version="2"/>', "application/octet-stream"),
            "Payload": (b"payload bytes", "application/x-bzip2"),
        }
        for identifier, (name, (content, style)) in enumerate(members.items(), 2):
            member = ET.SubElement(directory, "file", id=str(identifier))
            ET.SubElement(member, "name").text = name
            ET.SubElement(member, "type").text = "file"
            data = ET.SubElement(member, "data")
            archived = (
                bz2.compress(content) if style == "application/x-bzip2" else content
            )
            ET.SubElement(data, "length").text = str(len(archived))
            ET.SubElement(data, "offset").text = str(len(heap))
            ET.SubElement(data, "size").text = str(len(content))
            ET.SubElement(data, "encoding", style=style)
            archived_checksum = hashlib.sha1(
                archived, usedforsecurity=False
            ).hexdigest()
            extracted_checksum = hashlib.sha1(
                content, usedforsecurity=False
            ).hexdigest()
            ET.SubElement(
                data, "archived-checksum", style="sha1"
            ).text = archived_checksum
            ET.SubElement(
                data, "extracted-checksum", style="sha1"
            ).text = extracted_checksum
            heap.extend(archived)
        toc_bytes = ET.tostring(toc, encoding="utf-8")
        compressed_toc = zlib.compress(toc_bytes)
        archive = self.root / "package.pkg"
        archive.write_bytes(
            struct.pack(
                ">4sHHQQI", b"xar!", 28, 1, len(compressed_toc), len(toc_bytes), 1
            )
            + compressed_toc
            + heap
        )
        unpacked = self.root / "unpacked"
        unpack_xar(archive, unpacked)
        package_info = unpacked / "Package/PackageInfo"
        payload = unpacked / "Package/Payload"
        self.assertEqual(package_info.read_bytes(), members["PackageInfo"][0])
        self.assertEqual(payload.read_bytes(), members["Payload"][0])
        self.assertNotEqual(package_info.stat().st_ino, payload.stat().st_ino)

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
