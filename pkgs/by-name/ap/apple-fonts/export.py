#!/usr/bin/env python3
"""Export fonts from explicit directories into a deterministic import archive."""

from __future__ import annotations

import argparse
import base64
import io
import json
import tarfile
import tempfile
from pathlib import Path

from font_support import inventory, sha256


def export(roots: list[Path], notices: list[Path], archive: Path, version: str) -> dict:
    """Record regular-file fonts; never depend on resource forks in the store."""
    with tempfile.TemporaryDirectory(prefix="apple-font-export-") as directory:
        root = Path(directory)
        for index, source in enumerate(roots):
            for font in inventory(source):
                path = source / font["path"]
                resource = path / "..namedfork/rsrc"
                if resource.exists() and resource.stat().st_size:
                    raise ValueError(
                        f"External resource fork requires a separate import strategy: {path}"
                    )
                target = root / f"root-{index}" / font["path"]
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
        for index, notice in enumerate(notices):
            target = root / "notices" / f"LICENSE-{index}{notice.suffix}"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(notice.read_bytes())
        files = inventory(root)
        names = [n for f in files for n in f["faces"]]
        if len(names) != len(set(names)):
            raise ValueError(
                "Duplicate PostScript names in export; select non-overlapping font directories"
            )
        with tarfile.open(archive, "w", format=tarfile.PAX_FORMAT) as output:
            for path in sorted(root.rglob("*")):
                if path.is_file():
                    data = path.read_bytes()
                    info = tarfile.TarInfo(path.relative_to(root).as_posix())
                    info.size = len(data)
                    info.mode = 0o444
                    info.mtime = 0
                    output.addfile(info, io.BytesIO(data))
        return {
            "name": "apple-fonts-local",
            "version": version,
            "kind": "tar",
            "archiveName": archive.name,
            "hash": "sha256-"
            + base64.b64encode(bytes.fromhex(sha256(archive))).decode(),
            "files": files,
        }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directories", type=Path, nargs="+")
    parser.add_argument(
        "--version", required=True, help="Record the macOS version and build"
    )
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--notice", action="append", type=Path, default=[])
    args = parser.parse_args()
    if args.archive.exists() or args.manifest.exists():
        parser.error("Output already exists; choose new archive and manifest paths")
    entry = export(args.directories, args.notice, args.archive, args.version)
    args.manifest.write_text(json.dumps(entry, ensure_ascii=False, indent=2) + "\n")
    print(f"Exported {len(entry['files'])} font files to {args.archive}")


if __name__ == "__main__":
    main()
