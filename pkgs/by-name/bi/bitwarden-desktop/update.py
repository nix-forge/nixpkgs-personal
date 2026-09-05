#!/usr/bin/env python3
"""Update ``bitwarden-desktop`` from Bitwarden's latest stable desktop release."""

from __future__ import annotations

import argparse
import contextlib
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Final, NoReturn, cast
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from scripts.update_support import HTTPS_CONTEXT, github_api_headers

if TYPE_CHECKING:
    from collections.abc import Sequence


RELEASES_API_URL: Final = (
    "https://api.github.com/repos/bitwarden/clients/releases?per_page=100"
)
EXPECTED_DOWNLOAD_HOST: Final = "github.com"
VERSION_PATTERN: Final = re.compile(r"[0-9]{4}\.[0-9]+\.[0-9]+")
HTTP_USER_AGENT: Final = "nixpkgs-personal-updater/1.0"


@dataclass(frozen=True)
class _Release:
    version: str
    url: str


@dataclass(frozen=True)
class _UpstreamState:
    version: str
    url: str
    hash_sri: str


def _fail(message: str) -> NoReturn:
    sys.stderr.write(f"error: {message}\n")
    raise SystemExit(1)


def _fetch_releases() -> object:
    request = Request(
        RELEASES_API_URL,
        headers=github_api_headers(HTTP_USER_AGENT),
    )
    try:
        with urlopen(request, timeout=30, context=HTTPS_CONTEXT) as response:
            return json.load(response)
    except URLError as exc:
        _fail(f"failed to fetch Bitwarden releases: {exc}")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse Bitwarden release data: {exc}")


def _extract_release(data: object) -> _Release:
    if not isinstance(data, list):
        _fail("Bitwarden releases response was not a list")

    for item in data:
        if not isinstance(item, dict):
            continue
        release = cast("dict[str, object]", item)
        if release.get("draft") is not False or release.get("prerelease") is not False:
            continue

        tag = release.get("tag_name")
        if not isinstance(tag, str) or not tag.startswith("desktop-v"):
            continue
        version = tag.removeprefix("desktop-v")
        if VERSION_PATTERN.fullmatch(version) is None:
            continue

        expected_asset = f"Bitwarden-{version}-universal.dmg"
        assets = release.get("assets")
        if not isinstance(assets, list):
            _fail(f"Bitwarden {tag} did not include an assets list")

        urls = []
        for asset in assets:
            if not isinstance(asset, dict) or asset.get("name") != expected_asset:
                continue
            url = asset.get("browser_download_url")
            if isinstance(url, str):
                urls.append(url)

        if len(urls) != 1:
            _fail(f"expected one {expected_asset!r} asset, found {len(urls)}")
        return _Release(version=version, url=urls[0])

    _fail("no stable Bitwarden desktop release with a universal DMG was found")


def _validate_download_url(release: _Release) -> None:
    parsed = urlparse(release.url)
    if parsed.scheme != "https" or parsed.netloc != EXPECTED_DOWNLOAD_HOST:
        _fail(f"unexpected Bitwarden download origin: {release.url}")
    expected_path = (
        f"/bitwarden/clients/releases/download/desktop-v{release.version}/"
        f"Bitwarden-{release.version}-universal.dmg"
    )
    if parsed.path != expected_path or parsed.params or parsed.query or parsed.fragment:
        _fail(f"unexpected Bitwarden DMG URL: {release.url!r}")


def _prefetch_hash(url: str) -> str:
    nix = shutil.which("nix")
    if nix is None:
        _fail("`nix` executable not found in PATH")
    completed = subprocess.run(
        [nix, "store", "prefetch-file", "--json", "--hash-type", "sha256", url],
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "(no output)"
        _fail(f"failed to prefetch Bitwarden DMG hash:\n{detail}")
    try:
        hash_value = json.loads(completed.stdout).get("hash")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch output: {exc}")
    if (
        not isinstance(hash_value, str)
        or re.fullmatch(
            r"sha256-[A-Za-z0-9+/=]+",
            hash_value,
        )
        is None
    ):
        _fail(f"nix returned an invalid source hash: {hash_value!r}")
    return hash_value


def _parse_existing(content: str) -> _UpstreamState:
    version = re.search(r'^  version = "([^"]+)";$', content, re.MULTILINE)
    url = re.search(r'^    url = "([^"]+)";$', content, re.MULTILINE)
    hash_value = re.search(r'^    hash = "([^"]+)";$', content, re.MULTILINE)
    if version is None or url is None or hash_value is None:
        _fail("could not parse existing Bitwarden source metadata")
    return _UpstreamState(version.group(1), url.group(1), hash_value.group(1))


def _render_source(state: _UpstreamState) -> str:
    return (
        "{\n"
        f'  version = "{state.version}";\n'
        "  src = {\n"
        f'    url = "{state.url}";\n'
        f'    hash = "{state.hash_sri}";\n'
        "  };\n"
        "}\n"
    )


def _write_atomic(path: Path, content: str) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f"{path.name}.", dir=path.parent)
    try:
        os.close(descriptor)
        Path(temporary).write_text(content, encoding="utf-8", newline="\n")
        Path(temporary).replace(path)
    finally:
        with contextlib.suppress(OSError):
            Path(temporary).unlink(missing_ok=True)


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    old_content = source_path.read_text(encoding="utf-8")
    existing = _parse_existing(old_content)
    release = _extract_release(_fetch_releases())
    _validate_download_url(release)

    if not args.refresh and (existing.version, existing.url) == (
        release.version,
        release.url,
    ):
        sys.stdout.write("[update] bitwarden-desktop is already up to date\n")
        return 0

    updated = _UpstreamState(
        release.version,
        release.url,
        _prefetch_hash(release.url),
    )
    new_content = _render_source(updated)
    diff = "".join(
        difflib.unified_diff(
            old_content.splitlines(keepends=True),
            new_content.splitlines(keepends=True),
            fromfile=str(source_path),
            tofile=str(source_path),
        )
    )
    if diff:
        sys.stdout.write(diff)
    if args.check:
        return 1 if diff else 0
    if args.dry_run:
        return 0
    _write_atomic(source_path, new_content)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
