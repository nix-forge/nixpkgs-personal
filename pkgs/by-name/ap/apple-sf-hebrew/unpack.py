"""Extract a font distribution without running Apple installer scripts."""

from __future__ import annotations

import argparse
import base64
import json
import shutil
import subprocess
import tarfile
import zipfile
from pathlib import Path

from font_support import FONT_EXTENSIONS, install, sha256


def seven_zip(source: Path, target: Path) -> None:
    subprocess.run(
        ["7zz", "x", "-y", f"-o{target}", str(source)],
        check=True,
        stdout=subprocess.DEVNULL,
    )


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
        seven_zip(packages[0], root / "package")
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
