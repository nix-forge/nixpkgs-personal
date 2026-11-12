"""Validate the published Scrypted plugin before exposing it to a server."""

import json
import sys
from pathlib import Path, PurePosixPath
from zipfile import ZipFile


def main() -> None:
    root = Path(sys.argv[1])
    version = sys.argv[2]
    metadata = json.loads((root / "package.json").read_text())
    if metadata["name"] != "@scrypted/arlo" or metadata["version"] != version:
        raise ValueError("unexpected Scrypted Arlo package identity")
    if metadata["scrypted"]["runtime"] != "python":
        raise ValueError("unexpected Scrypted Arlo runtime")
    with ZipFile(root / "dist/plugin.zip") as plugin:
        names = set(plugin.namelist())
        if not {"main.py", "requirements.txt", "README.md"} <= names:
            raise ValueError("Scrypted Arlo plugin artifact is incomplete")
        for entry in plugin.infolist():
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("Scrypted Arlo plugin artifact has an unsafe path")
            if not entry.is_dir() and path.suffix not in {".py", ".md", ".txt"}:
                raise ValueError("Scrypted Arlo plugin artifact is not source-only")
        if plugin.testzip() is not None:
            raise ValueError("Scrypted Arlo plugin artifact is corrupt")


if __name__ == "__main__":
    main()
