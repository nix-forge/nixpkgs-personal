"""Validate the published HomeKit plugin before exposing it to Scrypted."""

import json
import sys
from pathlib import Path
from zipfile import ZipFile


def main() -> None:
    root = Path(sys.argv[1])
    version = sys.argv[2]
    metadata = json.loads((root / "package.json").read_text())
    if metadata["name"] != "@scrypted/homekit" or metadata["version"] != version:
        raise ValueError("unexpected Scrypted HomeKit package identity")
    if metadata["scrypted"]["type"] != "DeviceProvider":
        raise ValueError("unexpected Scrypted HomeKit plugin type")
    with ZipFile(root / "dist/plugin.zip") as plugin:
        if not {"main.nodejs.js", "sdk.json"} <= set(plugin.namelist()):
            raise ValueError("Scrypted HomeKit plugin artifact is incomplete")
        if plugin.testzip() is not None:
            raise ValueError("Scrypted HomeKit plugin artifact is corrupt")


if __name__ == "__main__":
    main()
