"""Validate Craft patch metadata, source references, inventory and checksums."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

PACKAGES = {
    "craft-fonts",
    "craft-launcher",
    "designcraft",
    "effectcraft",
    "figcraft",
    "filmcraft",
}
KINDS = {
    "upstream-candidate",
    "upstream-backport",
    "packaging-policy",
    "platform-workaround",
    "toolchain-workaround",
}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_patch(record: dict, directory: Path) -> str:
    require(
        isinstance(record, dict)
        and set(record)
        == {"file", "sha256", "kind", "upstream", "reason", "removeWhen"},
        f"Invalid patch fields in {directory.name}",
    )
    filename = record["file"]
    require(
        isinstance(filename, str)
        and re.fullmatch(r"[a-z0-9][a-z0-9.-]*\.patch", filename) is not None,
        f"Invalid patch filename in {directory.name}",
    )
    label = f"{directory.name}/{filename}"
    require(record["kind"] in KINDS, f"Unknown patch kind: {label}")
    for field in ("reason", "removeWhen"):
        require(
            isinstance(record[field], str) and bool(record[field].strip()),
            f"Missing {field}: {label}",
        )
    require(
        isinstance(record["upstream"], list) and bool(record["upstream"]),
        f"Missing upstream references: {label}",
    )
    for reference in record["upstream"]:
        require(isinstance(reference, str), f"Invalid upstream reference: {label}")
        url = urlsplit(reference)
        require(
            url.scheme == "https" and bool(url.netloc), f"Invalid upstream URL: {label}"
        )
    require(
        isinstance(record["sha256"], str)
        and re.fullmatch(r"[0-9a-f]{64}", record["sha256"]) is not None,
        f"Invalid SHA256: {label}",
    )
    require((directory / filename).is_file(), f"Missing patch: {label}")
    digest = hashlib.sha256((directory / filename).read_bytes()).hexdigest()
    require(digest == record["sha256"], f"Patch checksum changed: {label}")
    return filename


def main() -> None:
    specification, manifest_path, packages_path = map(Path, sys.argv[1:])
    sources = {
        entry["name"]: entry["pins"] for entry in json.loads(specification.read_text())
    }
    manifest = json.loads(manifest_path.read_text())
    require(set(manifest) == {"schemaVersion", "packages"}, "Invalid lifecycle fields")
    require(
        type(manifest["schemaVersion"]) is int and manifest["schemaVersion"] == 1,
        "Unsupported lifecycle schema",
    )
    require(
        set(manifest["packages"]) == PACKAGES,
        "Craft lifecycle package inventory changed",
    )
    count = 0
    for name, package in manifest["packages"].items():
        require(
            set(package) == {"sourceRevision", "patches"},
            f"Invalid package fields: {name}",
        )
        require(
            package["sourceRevision"] == sources[name]["rev"],
            f"Source revision changed: {name}",
        )
        require(isinstance(package["patches"], list), f"Invalid patches list: {name}")
        directory = packages_path / name[:2] / name
        filenames = [validate_patch(record, directory) for record in package["patches"]]
        require(
            len(set(filenames)) == len(filenames), f"Duplicate lifecycle patch: {name}"
        )
        actual = {patch.name for patch in directory.glob("*.patch")}
        require(set(filenames) == actual, f"Patch inventory changed: {name}")
        count += len(filenames)
    print(f"Validated lifecycle schema, source references and {count} patch checksums")


if __name__ == "__main__":
    main()
