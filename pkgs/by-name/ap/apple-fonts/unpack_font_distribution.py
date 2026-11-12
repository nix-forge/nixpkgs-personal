"""Extract a font distribution without running Apple installer scripts."""

from __future__ import annotations

import argparse
import base64
import bz2
import gzip
import hashlib
import io
import json
import shutil
import struct
import subprocess
import tarfile
import xml.etree.ElementTree as ET  # ruff: ignore[suspicious-xml-etree-import] - parse_xml rejects declarations and bounds input
import zipfile
import zlib
from pathlib import Path
from typing import override

from font_support import FONT_EXTENSIONS, install, sha256


def seven_zip(source: Path, target: Path) -> None:
    subprocess.run(
        ["7zz", "x", "-y", f"-o{target}", str(source)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


class LimitedReader(io.RawIOBase):
    """Read one bounded XAR data member from an already-open archive."""

    def __init__(self, stream, length: int, digest) -> None:
        super().__init__()
        self.stream = stream
        self.remaining = length
        self.digest = digest

    def read(self, size: int = -1) -> bytes:
        if self.remaining == 0:
            return b""
        if size < 0 or size > self.remaining:
            size = self.remaining
        data = self.stream.read(size)
        self.remaining -= len(data)
        self.digest.update(data)
        return data

    def readinto(self, buffer) -> int:
        data = self.read(len(buffer))
        buffer[: len(data)] = data
        return len(data)

    @override
    def readable(self) -> bool:
        return True

    @override
    def seekable(self) -> bool:
        return False


def xar_child(element: ET.Element, name: str) -> ET.Element | None:
    for child in element:
        if child.tag.rsplit("}", 1)[-1] == name:
            return child
    return None


def xar_member_path(root: Path, parent: Path, name: str) -> tuple[Path, Path]:
    relative = parent / name
    if (
        not name
        or Path(name).is_absolute()
        or any(part in {"", ".", ".."} for part in Path(name).parts)
        or "\x00" in name
    ):
        raise ValueError(f"Unsafe XAR member: {relative}")
    target = root / relative
    if not target.is_relative_to(root):
        raise ValueError(f"Unsafe XAR member: {relative}")
    return relative, target


def extract_xar_file(
    stream, target: Path, data: ET.Element, heap_offset: int, archive_size: int
) -> None:
    length_text = xar_child(data, "length")
    offset_text = xar_child(data, "offset")
    if length_text is None or offset_text is None:
        raise ValueError(f"XAR file has incomplete data metadata: {target}")
    length = int(length_text.text or "-1")
    offset = int(offset_text.text or "-1")
    if length < 0 or offset < 0 or heap_offset + offset + length > archive_size:
        raise ValueError(f"XAR file data is outside the archive: {target}")

    encoding = xar_child(data, "encoding")
    style = encoding.attrib.get("style") if encoding is not None else None
    if style not in {
        None,
        "application/octet-stream",
        "application/x-gzip",
        "application/x-bzip2",
    }:
        raise ValueError(f"Unsupported XAR encoding {style!r}: {target}")

    archived_digest = hashlib.sha1(usedforsecurity=False)
    stream.seek(heap_offset + offset)
    bounded = LimitedReader(stream, length, archived_digest)
    extracted_digest = hashlib.sha1(usedforsecurity=False)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("wb") as output:
        if style in {None, "application/octet-stream"}:
            reader = bounded
        elif style == "application/x-bzip2":
            reader = bz2.BZ2File(bounded, mode="rb")
        else:
            reader = gzip.GzipFile(fileobj=bounded, mode="rb")
        while True:
            chunk = reader.read(1024 * 1024)
            if not chunk:
                break
            output.write(chunk)
            extracted_digest.update(chunk)
        if style in {"application/x-gzip", "application/x-bzip2"}:
            reader.close()
    if bounded.remaining:
        raise ValueError(f"XAR file has trailing encoded data: {target}")

    size = xar_child(data, "size")
    if size is not None and target.stat().st_size != int(size.text or "-1"):
        raise ValueError(f"XAR extracted size mismatch: {target}")
    for name, digest in (
        ("archived-checksum", archived_digest),
        ("extracted-checksum", extracted_digest),
    ):
        checksum = xar_child(data, name)
        if checksum is not None:
            if checksum.attrib.get("style") != "sha1":
                raise ValueError(f"Unsupported XAR checksum: {target}")
            if (checksum.text or "").lower() != digest.hexdigest():
                raise ValueError(f"XAR checksum mismatch: {target}")


def parse_xml(content: bytes, source: Path) -> ET.Element:
    """Parse bounded UTF-8 XML without markup declarations.

    Returns:
        Parsed XML root.

    Raises:
        ValueError: The XML is unsafe or malformed.

    """
    try:
        text = content.decode("utf-8")
        if "<!" in text:
            raise ValueError(f"XML declarations are not allowed: {source}")
        return ET.fromstring(text)  # ruff: ignore[suspicious-xml-element-tree-usage] - bounded input, no DTD or entity definitions
    except (UnicodeError, ET.ParseError) as error:
        raise ValueError(f"Invalid XML: {source}") from error


def read_xar_toc(compressed: bytes, expected_size: int, source: Path) -> ET.Element:
    """Parse a size-bounded XAR table of contents without entity expansion.

    Returns:
        Parsed XML root.

    Raises:
        ValueError: The table is oversized, malformed, or contains entities.

    """
    if expected_size > 16 * 1024 * 1024:
        raise ValueError(f"XAR table of contents is too large: {source}")
    try:
        decoder = zlib.decompressobj()
        content = decoder.decompress(compressed, expected_size + 1)
    except zlib.error as error:
        raise ValueError(f"Invalid XAR table of contents: {source}") from error
    if not decoder.eof or decoder.unused_data or len(content) != expected_size:
        raise ValueError(f"XAR table of contents size mismatch: {source}")
    try:
        return parse_xml(content, source)
    except ValueError as error:
        raise ValueError(f"Invalid XAR table of contents: {source}") from error


def unpack_xar(source: Path, root: Path) -> None:
    """Extract XAR without 7-Zip's inode-zero hard-link bug.

    Raises:
        ValueError: The archive header, XML table, or a member is invalid.

    """
    header = struct.Struct(">4sHHQQI")
    with source.open("rb") as stream:
        values = stream.read(header.size)
        if len(values) != header.size:
            raise ValueError(f"Truncated XAR header: {source}")
        magic, header_size, version, compressed_size, toc_size, _ = header.unpack(
            values
        )
        if magic != b"xar!" or version != 1 or header_size < header.size:
            raise ValueError(f"Unsupported XAR header: {source}")
        stream.seek(header_size)
        compressed_toc = stream.read(compressed_size)
        if len(compressed_toc) != compressed_size:
            raise ValueError(f"Truncated XAR table of contents: {source}")
        toc = read_xar_toc(compressed_toc, toc_size, source)
        table = xar_child(toc, "toc")
        if table is None:
            raise ValueError(f"XAR table of contents is missing: {source}")
        archive_size = source.stat().st_size
        seen = set()
        root.mkdir(parents=True, exist_ok=True)

        def visit(element: ET.Element, parent: Path) -> None:
            name = xar_child(element, "name")
            member_type = xar_child(element, "type")
            if name is None or member_type is None:
                raise ValueError(f"Incomplete XAR member: {source}")
            relative, target = xar_member_path(root, parent, name.text or "")
            if relative in seen:
                raise ValueError(f"Duplicate XAR member: {relative}")
            seen.add(relative)
            if member_type.text in {"directory", "dir"}:
                target.mkdir(parents=True, exist_ok=False)
                for child in element:
                    if child.tag.rsplit("}", 1)[-1] == "file":
                        visit(child, relative)
            elif member_type.text == "file":
                data = xar_child(element, "data")
                if data is None:
                    raise ValueError(f"XAR file has no data: {relative}")
                extract_xar_file(
                    stream,
                    target,
                    data,
                    header_size + compressed_size,
                    archive_size,
                )
            else:
                raise ValueError(
                    f"Unsupported XAR member type {member_type.text!r}: {relative}"
                )

        for child in table:
            if child.tag.rsplit("}", 1)[-1] == "file":
                visit(child, Path())


def unpack(source: Path, root: Path, kind: str) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    if f".{kind}" in FONT_EXTENSIONS:
        shutil.copyfile(source, root / f"font.{kind}")
    elif kind == "zip":
        with zipfile.ZipFile(source) as archive:
            # Reject traversal and symlinks before extraction.
            for item in archive.infolist():
                if (
                    Path(item.filename).is_absolute()
                    or ".." in Path(item.filename).parts
                ):
                    raise ValueError(f"Unsafe ZIP member: {item.filename}")
                if (item.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError(f"ZIP symlink: {item.filename}")
            archive.extractall(root)
    elif kind == "dmg":
        seven_zip(source, root / "dmg")
        packages = list((root / "dmg").rglob("*.pkg"))
        if len(packages) != 1 or not packages[0].is_file():
            raise ValueError("Expected one flat Apple font installer")
        unpack_xar(packages[0], root / "package")
        payloads = sorted((root / "package").rglob("Payload"))
        if not payloads:
            raise ValueError("Missing font installer payload")
        for index, payload in enumerate(payloads):
            intermediate = root / f"compressed-{index}"
            seven_zip(payload, intermediate)
            cpio = list(intermediate.iterdir())
            if len(cpio) != 1:
                raise ValueError("Expected one decompressed cpio payload")
            seven_zip(cpio[0], root / f"payload-{index}")
    elif kind == "tar":
        with tarfile.open(source) as archive:
            if any(
                not (item.isfile() or item.isdir()) for item in archive.getmembers()
            ):
                raise ValueError(
                    "Import archive must contain only regular files and directories"
                )
            archive.extractall(root, filter="data")
    else:
        raise ValueError(f"Unsupported source kind: {kind}")
    return root


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    entry = json.loads(args.manifest.read_text())
    actual_hash = (
        "sha256-" + base64.b64encode(bytes.fromhex(sha256(args.source))).decode()
    )
    if actual_hash != entry["hash"]:
        raise ValueError("Archive differs from its recorded SHA256")
    root = unpack(args.source, Path.cwd() / "extracted", entry["kind"])
    install(root, args.output, entry)


if __name__ == "__main__":
    main()
