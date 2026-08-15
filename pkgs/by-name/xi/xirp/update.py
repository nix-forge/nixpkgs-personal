#!/usr/bin/env python3
"""Safely pin the current public Apple-silicon Xirp release."""

from __future__ import annotations

import argparse
import base64
import contextlib
import difflib
import hashlib
import importlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
HTTPS_CONTEXT = importlib.import_module("scripts.update_support").HTTPS_CONTEXT


CDN_HOST = "reckless-finch.spotifycdn.com"
CDN_DIRECTORY = "/external/"
FEED_URL = f"https://{CDN_HOST}{CDN_DIRECTORY}latest-mac.yml"
SEMVER = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")


def fetch_text(url: str) -> str:
    with urllib.request.urlopen(url, context=HTTPS_CONTEXT) as response:
        return response.read().decode("utf-8")


def parse_release(feed: str) -> tuple[str, str, bytes]:
    version_match = re.search(r"^version: (?P<version>[^\s]+)$", feed, re.MULTILINE)
    if version_match is None or SEMVER.fullmatch(version_match["version"]) is None:
        raise ValueError("latest-mac.yml does not contain a valid semantic version")

    version = version_match["version"]
    expected_name = f"Xirp-{version}-arm64-external.zip"
    file_matches = list(
        re.finditer(
            r"^  - url: (?P<url>[^\n]+)\n    sha512: (?P<sha512>[^\n]+)\n    size: [1-9][0-9]*$",
            feed,
            re.MULTILINE,
        )
    )
    matching_files = [match for match in file_matches if match["url"] == expected_name]
    if len(matching_files) != 1:
        raise ValueError(f"latest-mac.yml does not contain exactly one {expected_name}")

    try:
        expected_sha512 = base64.b64decode(matching_files[0]["sha512"], validate=True)
    except ValueError as error:
        raise ValueError("latest-mac.yml has an invalid SHA-512 value") from error
    if len(expected_sha512) != hashlib.sha512().digest_size:
        raise ValueError("latest-mac.yml SHA-512 has an unexpected length")

    url = f"https://{CDN_HOST}{CDN_DIRECTORY}{expected_name}"
    parsed = urllib.parse.urlparse(url)
    if (
        parsed.scheme != "https"
        or parsed.netloc != CDN_HOST
        or parsed.path != f"{CDN_DIRECTORY}{expected_name}"
        or parsed.params
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError("refusing an unexpected release URL")
    return version, url, expected_sha512


def parse_source(source_path: Path) -> dict[str, str]:
    source = source_path.read_text()
    version = re.search(r'^  version = "(?P<value>[^"]+)";$', source, re.MULTILINE)
    url = re.search(r'^    url = "(?P<value>[^"]+)";$', source, re.MULTILINE)
    hash_value = re.search(
        r'^    hash = "(?P<value>sha256-[A-Za-z0-9+/=]+)";$', source, re.MULTILINE
    )
    if (
        source.count('appName = "Xirp";') != 1
        or version is None
        or url is None
        or hash_value is None
    ):
        raise ValueError(f"{source_path} has an unexpected format")
    return {
        "version": version["value"],
        "url": url["value"],
        "hash": hash_value["value"],
    }


def prefetch(url: str, expected_sha512: bytes) -> str:
    result = subprocess.run(
        ["nix", "store", "prefetch-file", "--json", "--hash-type", "sha256", url],
        check=True,
        capture_output=True,
        text=True,
    )
    prefetched = json.loads(result.stdout)
    store_path = Path(prefetched["storePath"])
    hash_value = prefetched["hash"]
    if not store_path.is_file() or not isinstance(hash_value, str):
        raise ValueError("nix prefetch returned an invalid result")
    actual_sha512 = hashlib.sha512(store_path.read_bytes()).digest()
    if actual_sha512 != expected_sha512:
        raise ValueError("downloaded artifact does not match latest-mac.yml SHA-512")
    return hash_value


def render_source(version: str, url: str, hash_value: str) -> str:
    return (
        "{\n"
        f'  version = "{version}";\n'
        '  appName = "Xirp";\n'
        "  src = {\n"
        f'    url = "{url}";\n'
        f'    hash = "{hash_value}";\n'
        "  };\n"
        "}\n"
    )


def write_atomically(path: Path, contents: str) -> None:
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as temporary:
        temporary.write(contents)
        temporary_path = Path(temporary.name)
    try:
        shutil.copymode(path, temporary_path)
        temporary_path.replace(path)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            temporary_path.unlink()
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the source update without writing it",
    )
    parser.add_argument(
        "--check", action="store_true", help="fail if a newer release is available"
    )
    args = parser.parse_args()
    if args.dry_run and args.check:
        parser.error("--dry-run and --check cannot be used together")

    source_path = Path(__file__).with_name("source.nix")
    original = source_path.read_text()
    current = parse_source(source_path)
    version, url, expected_sha512 = parse_release(fetch_text(FEED_URL))

    if current["version"] == version and current["url"] == url:
        print(f"Xirp {version} is already pinned")
        return

    hash_value = prefetch(url, expected_sha512)
    updated = render_source(version, url, hash_value)
    if args.check:
        print(f"Xirp update available: {current['version']} -> {version}")
        raise SystemExit(1)
    if args.dry_run:
        print(
            "".join(
                difflib.unified_diff(
                    original.splitlines(keepends=True),
                    updated.splitlines(keepends=True),
                    fromfile=str(source_path),
                    tofile=str(source_path),
                )
            )
        )
        return

    write_atomically(source_path, updated)
    print(f"Updated Xirp {current['version']} -> {version}")


if __name__ == "__main__":
    main()
