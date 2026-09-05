#!/usr/bin/env python3
"""Update ``wootility`` from Wooting's latest stable Apple Silicon release."""

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
from html.parser import HTMLParser
from pathlib import Path
from typing import TYPE_CHECKING, Final, NoReturn, cast
from urllib.error import URLError
from urllib.parse import parse_qs, urljoin, urlparse
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from scripts.update_support import HTTPS_CONTEXT

if TYPE_CHECKING:
    from collections.abc import Sequence


LANDING_URL: Final = "https://wooting.io/wootility"
EXPECTED_DOWNLOAD_HOST: Final = "wootility-updates.ams3.cdn.digitaloceanspaces.com"
VERSION_PATTERN: Final = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
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


class _NextDataParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._capturing = False
        self._parts: list[str] = []

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        attributes = dict(attrs)
        self._capturing = tag == "script" and attributes.get("id") == "__NEXT_DATA__"

    def handle_endtag(self, tag: str) -> None:
        if tag == "script":
            self._capturing = False

    def handle_data(self, data: str) -> None:
        if self._capturing:
            self._parts.append(data)

    @property
    def payload(self) -> str:
        return "".join(self._parts)


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    sys.stderr.write(f"error: {message}\n")
    raise SystemExit(1)


def _fetch_landing_page() -> str:
    request = Request(LANDING_URL, headers={"User-Agent": HTTP_USER_AGENT})
    try:
        with urlopen(request, timeout=30, context=HTTPS_CONTEXT) as response:
            return response.read().decode("utf-8")
    except (URLError, UnicodeDecodeError) as exc:
        _fail(f"failed to fetch Wootility release metadata: {exc}")


def _release_metadata(page: str) -> dict[str, object]:
    parser = _NextDataParser()
    parser.feed(page)
    if not parser.payload:
        _fail("Wootility page did not contain Next.js release metadata")

    try:
        data = json.loads(parser.payload)
        metadata = data["props"]["pageProps"]["wootilityLatestMeta"]
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        _fail(f"failed to parse Wootility release metadata: {exc}")

    if not isinstance(metadata, dict):
        _fail("Wootility release metadata was not an object")
    return cast("dict[str, object]", metadata)


def _apple_silicon_link(release_data: dict[str, object]) -> str:
    links = release_data.get("links")
    if not isinstance(links, list):
        _fail("Wootility release metadata did not contain a links list")

    matches: list[str] = []
    for item in links:
        if not isinstance(item, dict):
            continue
        link = cast("dict[str, object]", item)
        if link.get("os") != "mac" or link.get("platform") != "arm64":
            continue
        url = link.get("url")
        if isinstance(url, str):
            matches.append(url)

    if len(matches) != 1:
        _fail(f"expected one Apple Silicon download link, found {len(matches)}")
    return matches[0]


def _discovery_url(release_data: dict[str, object], version: str) -> str:
    discovery_url = urljoin(LANDING_URL, _apple_silicon_link(release_data))
    parsed = urlparse(discovery_url)
    try:
        query = parse_qs(parsed.query, strict_parsing=True)
    except ValueError as exc:
        _fail(f"invalid Wootility discovery query: {exc}")
    if parsed.scheme != "https" or parsed.netloc != "wooting.io":
        _fail(f"unexpected Wootility discovery origin: {discovery_url}")
    if parsed.path != "/_backend/public/wootility/download":
        _fail(f"unexpected Wootility discovery path: {parsed.path!r}")
    if query != {"os": ["mac"], "platform": ["arm64"], "version": [version]}:
        _fail(f"unexpected Wootility discovery query: {parsed.query!r}")
    if parsed.fragment:
        _fail("Wootility discovery URL must not contain a fragment")
    return discovery_url


def _extract_release(page: str) -> _Release:
    release_data = _release_metadata(page)
    version = release_data.get("version")
    if not isinstance(version, str) or VERSION_PATTERN.fullmatch(version) is None:
        _fail(f"Wootility release has an unexpected version: {version!r}")
    discovery_url = _discovery_url(release_data, version)
    request = Request(discovery_url, headers={"User-Agent": HTTP_USER_AGENT})
    try:
        with urlopen(request, timeout=30, context=HTTPS_CONTEXT) as response:
            download_url = response.geturl()
    except URLError as exc:
        _fail(f"failed to resolve Wootility download: {exc}")

    expected_path = f"/wootility-mac/Wootility-{version}-arm64.dmg"
    resolved = urlparse(download_url)
    if resolved.scheme != "https" or resolved.netloc != EXPECTED_DOWNLOAD_HOST:
        _fail(f"unexpected Wootility download origin: {download_url}")
    if resolved.path != expected_path or resolved.query or resolved.fragment:
        _fail(f"unexpected Wootility download URL: {download_url}")

    return _Release(version=version, url=download_url)


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
        _fail(f"failed to prefetch Wootility DMG hash:\n{detail}")
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
        _fail("could not parse existing Wootility source metadata")
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
    release = _extract_release(_fetch_landing_page())

    if not args.refresh and (existing.version, existing.url) == (
        release.version,
        release.url,
    ):
        _stdout("[update] wootility is already up to date")
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
