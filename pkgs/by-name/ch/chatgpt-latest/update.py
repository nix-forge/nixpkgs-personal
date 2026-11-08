"""Refresh upstream ChatGPT sources from the official stable platform feeds."""

from __future__ import annotations

import argparse
import gzip
import io
import re
from dataclasses import dataclass
from pathlib import Path
from urllib.error import URLError

from release_support import (
    MAX_METADATA,
    load_pins,
    metadata,
    prefetch,
    publish,
    reject_downgrade,
    sri,
    version_key,
)

BASE = "https://persistent.oaistatic.com/codex-app-prod"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


@dataclass(frozen=True)
class Release:
    version: str
    url: str
    size: int
    expected_hash: str | None = None


def newest(releases: list[Release]) -> Release:
    if not releases:
        raise ValueError("The stable feed contains no supported release")
    version = max(version_key(item.version) for item in releases)
    selected = {item for item in releases if version_key(item.version) == version}
    if len(selected) != 1:
        raise ValueError("Conflicting metadata for the newest release")
    return selected.pop()


def linux_release(data: bytes, architecture: str) -> Release:
    if architecture not in {"amd64", "arm64"}:
        raise ValueError("Unsupported Debian architecture")
    with gzip.GzipFile(fileobj=io.BytesIO(data)) as compressed:
        text = compressed.read(MAX_METADATA + 1)
    if len(text) > MAX_METADATA:
        raise ValueError("Decompressed Debian index exceeds the size limit")
    releases = []
    for paragraph in re.split(r"\n\s*\n", text.decode("utf-8")):
        fields = {}
        for line in paragraph.splitlines():
            if not line or line.startswith((" ", "\t")):
                continue
            key, separator, value = line.partition(": ")
            if not separator or key in fields:
                raise ValueError("Malformed or duplicate Debian index field")
            fields[key] = value
        if (
            fields.get("Package") != "chatgpt"
            or fields.get("Architecture") != architecture
        ):
            continue
        version = fields["Version"]
        version_key(version)
        filename = f"pool/main/c/chatgpt/chatgpt_{version}_{architecture}.deb"
        if fields["Filename"] != filename:
            raise ValueError("Unexpected Debian artifact filename")
        size = int(fields["Size"])
        if size <= 0:
            raise ValueError("Debian artifact size must be positive")
        releases.append(
            Release(
                version, f"{BASE}/linux/deb/{filename}", size, sri(fields["SHA256"])
            )
        )
    return newest(releases)


def darwin_release(data: bytes) -> Release:
    # Keep standalone --help usable before optional parser dependencies are installed.
    from defusedxml import ElementTree  # ruff: ignore[import-outside-top-level]

    root = ElementTree.fromstring(data)
    releases = []
    for item in root.findall("./channel/item"):
        if item.findtext(f"{SPARKLE}channel") not in {None, "", "stable"}:
            continue
        if item.findtext(f"{SPARKLE}hardwareRequirements") != "arm64":
            continue
        version = item.findtext(f"{SPARKLE}shortVersionString", "")
        version_key(version)
        enclosures = item.findall("enclosure")
        if len(enclosures) != 1:
            raise ValueError("Expected exactly one full Darwin archive")
        enclosure = enclosures[0]
        url = f"{BASE}/ChatGPT-darwin-arm64-{version}.zip"
        if enclosure.attrib["url"] != url:
            raise ValueError("Unexpected Darwin download URL")
        size = int(enclosure.attrib["length"])
        if size <= 0:
            raise ValueError("Darwin artifact size must be positive")
        releases.append(Release(version, url, size))
    return newest(releases)


def candidate(current: dict, releases: dict[str, Release]) -> dict:
    if set(current) != set(releases):
        raise ValueError("Release feeds must cover every supported platform")
    updated = {}
    for system, release in sorted(releases.items()):
        previous = current[system]
        reject_downgrade(previous["version"], release.version)
        same = previous["version"] == release.version
        if same and previous["src"]["url"] != release.url:
            raise ValueError("A published version changed its download URL")
        if (
            same
            and release.expected_hash is not None
            and previous["src"]["hash"] != release.expected_hash
        ):
            raise ValueError("A published Linux artifact changed checksum")
        if same:
            updated[system] = previous
            continue
        digest, artifact = prefetch(release.url)
        if artifact.stat().st_size != release.size:
            raise ValueError(f"Artifact size disagrees with feed: {system}")
        if release.expected_hash is not None and digest != release.expected_hash:
            raise ValueError(f"Artifact checksum disagrees with feed: {system}")
        updated[system] = {
            "version": release.version,
            "src": {"url": release.url, "hash": digest},
        }
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run", action="store_true", help="verify and preview without editing pins"
    )
    arguments = parser.parse_args()
    path = Path(__file__).with_name("source.nix")
    original = path.read_bytes()
    try:
        releases = {"aarch64-darwin": darwin_release(metadata(f"{BASE}/appcast.xml"))}
        for system, architecture in [
            ("x86_64-linux", "amd64"),
            ("aarch64-linux", "arm64"),
        ]:
            releases[system] = linux_release(
                metadata(
                    f"{BASE}/linux/deb/dists/stable/main/binary-{architecture}/Packages.gz"
                ),
                architecture,
            )
        pins = candidate(load_pins(path), releases)
        publish(path, original, pins, dry_run=arguments.dry_run)
    except (ValueError, TypeError, KeyError, OSError, URLError) as error:
        parser.exit(1, f"ChatGPT update failed: {error}\n")


if __name__ == "__main__":
    main()
