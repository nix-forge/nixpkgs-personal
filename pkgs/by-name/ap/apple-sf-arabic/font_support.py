"""Inspect and install unchanged font files from pinned Apple distributions."""

from __future__ import annotations

import hashlib
import json
import shutil
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


def safe_path(root: Path, name: str) -> Path:
    path = root / name
    if (
        Path(name).is_absolute()
        or ".." in Path(name).parts
        or not path.is_relative_to(root)
    ):
        raise ValueError(f"Unsafe payload path: {name}")
    return path


def install(root: Path, output: Path, entry: dict) -> None:
    """Verify the complete input inventory, then copy fonts without conversion."""
    actual = inventory(root)
    if actual != entry["files"]:
        raise ValueError(f"Font payload changed for {entry['name']}")
    destinations = set()
    for item in actual:
        source = safe_path(root, item["path"])
        extension = source.suffix.lower()
        # Core Text accepts OpenType collections with .ttc; nix-darwin's
        # extension filter omits .otc. Rename only, retaining every byte.
        suffix = ".ttc" if extension == ".otc" else extension
        folder = "opentype" if extension in {".otf", ".otc"} else "truetype"
        relative = Path(item["path"]).with_suffix(suffix)
        destination = output / "share/fonts" / folder / entry["name"] / relative
        key = str(destination).casefold()
        if key in destinations:
            raise ValueError(f"Case-insensitive filename collision: {destination}")
        destinations.add(key)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        destination.chmod(0o444)
        if sha256(destination) != item["sha256"] or faces(destination) != item["faces"]:
            raise ValueError(f"Installed font differs: {destination}")
    documentation = output / "share/doc" / entry["name"]
    documentation.mkdir(parents=True, exist_ok=True)
    (documentation / "manifest.json").write_text(json.dumps(entry, indent=2) + "\n")
    # Preserve notices shipped anywhere in the extracted distribution.
    for path in sorted(root.rglob("*")):
        if path.is_file() and any(
            x in path.name.lower()
            for x in ("license", "licence", "copyright", "notice")
        ):
            target = documentation / "upstream" / path.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
