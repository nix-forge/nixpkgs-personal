"""Reject undocumented or stale ArtCraft source-patch lifecycle decisions."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

KINDS = frozenset({
    "upstream-backport",
    "upstream-candidate",
    "packaging-policy",
    "platform-workaround",
    "toolchain-workaround",
})
PATCH_FIELDS = frozenset({"file", "sha256", "kind", "upstream", "reason", "removeWhen"})


def _object(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        raise TypeError(f"{label} must be an object")
    return value


def _fields(value: dict, required: set | frozenset, label: str) -> None:
    if value.keys() != required:
        raise ValueError(f"{label} has missing or unknown fields")


def _text(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} must be nonempty text")
    return value


def _hex(value: object, length: int, label: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(rf"[0-9a-f]{{{length}}}", value):
        raise ValueError(f"{label} must be {length} lowercase hexadecimal characters")
    return value


def _package_name(value: object) -> str:
    name = _text(value, "package name")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
        raise ValueError(f"Invalid package name: {name}")
    return name


def _patch_name(value: object) -> str:
    name = _text(value, "patch filename")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*\.patch", name):
        raise ValueError(f"Patch filename must be a .patch basename: {name}")
    return name


def _references(value: object, label: str) -> None:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{label} requires at least one upstream HTTPS URL")
    seen: set[str] = set()
    for item in value:
        url = _text(item, label)
        parts = urlsplit(url)
        if (
            parts.scheme != "https"
            or not parts.hostname
            or parts.username is not None
            or parts.password is not None
            or any(
                character.isspace() or not character.isprintable() for character in url
            )
        ):
            raise ValueError(f"{label} must use a valid public HTTPS URL: {url}")
        # Accessing port also rejects malformed and out-of-range port numbers.
        _ = parts.port
        if url in seen:
            raise ValueError(f"Duplicate upstream URL: {label}")
        seen.add(url)


def _sources(value: object) -> dict[str, dict]:
    if not isinstance(value, list):
        raise TypeError("Source pins must be a list of name/pins objects")
    result: dict[str, dict] = {}
    for item in value:
        entry = _object(item, "source entry")
        name = _text(entry.get("name"), "source name")
        if name in result:
            raise ValueError(f"Duplicate source package: {name}")
        result[name] = _object(entry.get("pins"), f"{name} source pins")
    return result


def _inventory(value: object) -> dict[str, dict]:
    result = _object(value, "Actual patch inventory")
    if not result:
        raise ValueError(
            "Actual patch inventory must include the authoritative app list"
        )
    for name, files in result.items():
        _package_name(name)
        for filename, digest in _object(files, f"{name} actual patches").items():
            _patch_name(filename)
            _hex(digest, 64, f"{name}/{filename} actual SHA-256")
    return result


def _patches(value: object, actual: dict, name: str) -> int:
    if not isinstance(value, list):
        raise TypeError(f"{name} patches must be a list, including [] for no patches")
    recorded: set[str] = set()
    for item in value:
        patch = _object(item, f"{name} patch")
        _fields(patch, PATCH_FIELDS, f"{name} patch")
        filename = _patch_name(patch["file"])
        label = f"{name}/{filename}"
        if filename in recorded:
            raise ValueError(f"Duplicate patch: {label}")
        recorded.add(filename)
        digest = _hex(patch["sha256"], 64, f"{label} SHA-256")
        kind = _text(patch["kind"], f"{label} kind")
        if kind not in KINDS:
            raise ValueError(f"Unknown patch kind: {label}: {kind}")
        _references(patch["upstream"], label)
        _text(patch["reason"], f"{label} reason")
        _text(patch["removeWhen"], f"{label} removal condition")
        if filename in actual and digest != actual[filename]:
            raise ValueError(f"Changed patch requires lifecycle review: {label}")
    if recorded != actual.keys():
        undocumented = sorted(actual.keys() - recorded)
        orphaned = sorted(recorded - actual.keys())
        raise ValueError(
            f"Patch inventory mismatch for {name}: undocumented={undocumented}, orphaned={orphaned}"
        )
    return len(recorded)


def validate(registry: object, sources: object, inventory: object) -> int:
    """Validate independently supplied source pins and actual patch hashes.

    Returns:
        The number of documented patches.

    Raises:
        ValueError: The registry is malformed, incomplete, orphaned or stale.

    """
    document = _object(registry, "Lifecycle registry")
    _fields(document, {"schemaVersion", "packages"}, "Lifecycle registry")
    if (
        not isinstance(document["schemaVersion"], int)
        or isinstance(document["schemaVersion"], bool)
        or document["schemaVersion"] != 1
    ):
        raise ValueError("Unsupported lifecycle schemaVersion; expected integer 1")
    packages = _object(document["packages"], "Registry packages")
    actual = _inventory(inventory)
    pins = _sources(sources)
    if packages.keys() != actual.keys():
        missing = sorted(actual.keys() - packages.keys())
        orphaned = sorted(packages.keys() - actual.keys())
        raise ValueError(
            f"Package inventory mismatch: undocumented={missing}, orphaned={orphaned}"
        )
    count = 0
    for name, item in packages.items():
        _package_name(name)
        entry = _object(item, f"{name} lifecycle")
        _fields(entry, {"sourceRevision", "patches"}, f"{name} lifecycle")
        revision = _hex(entry["sourceRevision"], 40, f"{name} source revision")
        if name not in pins:
            raise ValueError(f"Missing source pin: {name}")
        actual_revision = _hex(
            pins[name].get("rev"), 40, f"{name} actual source revision"
        )
        if revision != actual_revision:
            raise ValueError(
                f"Changed source revision requires lifecycle review: {name}"
            )
        count += _patches(entry["patches"], actual[name], name)
    return count


def _unique_keys(pairs: list[tuple[str, object]]) -> dict:
    result: dict = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def load(path: Path) -> object:
    """Read JSON without silently overwriting duplicate object keys.

    Returns:
        The decoded JSON value.

    """
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_keys)


def main() -> int:
    """Validate a registry against Nix-exported source pins and actual patch hashes.

    Returns:
        Zero for a complete current registry, otherwise one.

    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("registry", type=Path)
    parser.add_argument("source_pins", type=Path)
    parser.add_argument("inventory", type=Path)
    arguments = parser.parse_args()
    try:
        count = validate(
            load(arguments.registry),
            load(arguments.source_pins),
            load(arguments.inventory),
        )
    except (OSError, UnicodeError, ValueError, TypeError) as error:
        print(f"ArtCraft patch lifecycle: {error}", file=sys.stderr)
        return 1
    print(f"Validated lifecycle decisions for {count} ArtCraft patches")
    return 0


if __name__ == "__main__":
    sys.exit(main())
