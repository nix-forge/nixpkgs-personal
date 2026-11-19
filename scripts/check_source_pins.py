"""Validate committed Nix source pins without fetching release payloads."""

from __future__ import annotations

import base64
import datetime as dt
import json
import re
import sys
from pathlib import Path


def validate_release_metadata(pins: dict, name: str) -> None:
    """Validate optional AppStream release metadata against the pinned version.

    Raises:
        ValueError: If metadata is incomplete, invalid or contradicts the version.

    """
    release_fields = {"releaseDate", "releaseType"}
    if release_fields.intersection(pins):
        if not release_fields.issubset(pins):
            raise ValueError(f"Incomplete release metadata: {name}")
        date = pins["releaseDate"]
        if not isinstance(date, str) or not re.fullmatch(
            r"[0-9]{4}-[0-9]{2}-[0-9]{2}", date
        ):
            raise ValueError(f"Release date must use ISO calendar format: {name}")
        dt.date.fromisoformat(date)
        kind = pins["releaseType"]
        if kind not in {"stable", "development", "snapshot"}:
            raise ValueError(f"Unknown AppStream release type: {name}")
        version = pins.get("version", "")
        snapshot = re.search(r"-unstable-([0-9]{4}-[0-9]{2}-[0-9]{2})$", version)
        if kind == "snapshot" and (snapshot is None or snapshot[1] != date):
            raise ValueError(f"Snapshot date disagrees with its source version: {name}")
        if kind == "stable" and snapshot is not None:
            raise ValueError(f"An unstable source must not be marked stable: {name}")


def validate(pins: dict, name: str) -> int:
    """Validate nested source and dependency hash fields and explicit version pins.

    Returns:
        The number of fixed-output hashes checked.

    Raises:
        ValueError: A hash is malformed or fake, or a revision/version is unpinned.

    """
    validate_release_metadata(pins, name)
    count = 0
    for key, value in pins.items():
        label = f"{name}.{key}"
        if isinstance(value, dict):
            count += validate(value, label)
        elif key == "hash" or key.endswith("Hash"):
            if not isinstance(value, str) or not re.fullmatch(
                r"sha256-[A-Za-z0-9+/]{43}=", value
            ):
                raise ValueError(f"Invalid SHA256 SRI source pin: {label}")
            if base64.b64decode(value[7:], validate=True) == bytes(32):
                raise ValueError(f"Fake hash left in committed source pins: {label}")
            count += 1
        elif (key in {"version", "rev"} or key.endswith("Rev")) and (
            not isinstance(value, str)
            or not value
            or value.lower() in {"latest", "master", "main", "head"}
        ):
            raise ValueError(f"Unpinned version or revision: {label}")
    return count


def main() -> None:
    """Validate the source metadata exported by the Nix check."""
    entries = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    count = sum(validate(entry["pins"], entry["name"]) for entry in entries)
    print(f"Validated {count} source/dependency hashes in {len(entries)} source files")


if __name__ == "__main__":
    main()
