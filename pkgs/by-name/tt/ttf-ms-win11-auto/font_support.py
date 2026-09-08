"""Inspect the bytes and face identities of this package's font payload."""

from __future__ import annotations

import hashlib
import subprocess
from pathlib import Path

FONT_EXTENSIONS = {".ttf", ".ttc", ".otf", ".otc", ".dfont"}


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def faces(path: Path) -> list[str]:
    result = subprocess.run(
        ["fc-scan", "--format", "%{postscriptname}\n", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )
    # Fontconfig also emits an unnamed variable default for some named-instance fonts.
    names = sorted(set(filter(None, result.stdout.splitlines())))
    if not names:
        raise ValueError(f"No named font faces in {path}")
    return names


def inventory(root: Path) -> list[dict]:
    result = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in FONT_EXTENSIONS:
            if path.is_symlink():
                raise ValueError(f"Font symlink must be resolved before import: {path}")
            result.append({
                "path": path.relative_to(root).as_posix(),
                "sha256": sha256(path),
                "faces": faces(path),
            })
    if not result:
        raise ValueError(f"No supported fonts in {root}")
    return result
