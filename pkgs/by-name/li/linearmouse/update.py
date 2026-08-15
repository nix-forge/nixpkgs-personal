#!/usr/bin/env python3
"""Update ``linearmouse`` from its latest stable GitHub release."""

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


RELEASE_API_URL: Final = (
    "https://api.github.com/repos/linearmouse/linearmouse/releases/latest"
)
EXPECTED_ASSET_NAME: Final = "LinearMouse.dmg"
EXPECTED_DOWNLOAD_HOST: Final = "github.com"
EXPECTED_DOWNLOAD_PATH: Final = re.compile(
    r"^/linearmouse/linearmouse/releases/download/v([^/]+)/LinearMouse\.dmg$"
)
VERSION_PATTERN: Final = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"


@dataclass(frozen=True)
class _Release:
    version: str
    url: str


@dataclass(frozen=True)
class _UpstreamState:
    version: str
    url: str
    hash_sri: str


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _fetch_json(url: str, *, label: str, timeout: int = 30) -> object:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"unsupported URL scheme for {label}: {parsed_url.scheme!r}")

    try:
        request = Request(url, headers=github_api_headers(HTTP_USER_AGENT))
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
            return json.load(response)
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse JSON for {label} from {url}: {exc}")


def _extract_asset_url(assets: object) -> str:
    if not isinstance(assets, list):
        _fail("latest release did not include an assets list")

    matches: list[str] = []
    for asset in assets:
        if not isinstance(asset, dict):
            continue
        asset_dict = cast("dict[str, object]", asset)
        if asset_dict.get("name") != EXPECTED_ASSET_NAME:
            continue
        url = asset_dict.get("browser_download_url")
        if isinstance(url, str):
            matches.append(url)

    if len(matches) != 1:
        _fail(
            f"expected exactly one {EXPECTED_ASSET_NAME!r} release asset, "
            f"found {len(matches)}",
        )
    return matches[0]


def _extract_release(data: object) -> _Release:
    if not isinstance(data, dict):
        _fail("GitHub latest release response was not an object")

    release = cast("dict[str, object]", data)
    if release.get("draft") is not False or release.get("prerelease") is not False:
        _fail("GitHub latest release response was not a stable published release")

    tag_name = release.get("tag_name")
    if not isinstance(tag_name, str) or not tag_name.startswith("v"):
        _fail("latest release did not include a version tag beginning with `v`")

    version = tag_name.removeprefix("v")
    if VERSION_PATTERN.fullmatch(version) is None:
        _fail(f"latest release tag has an unexpected version format: {tag_name!r}")

    return _Release(
        version=version,
        url=_extract_asset_url(release.get("assets")),
    )


def _validate_download_url(release: _Release) -> None:
    parsed_url = urlparse(release.url)
    if parsed_url.scheme != "https":
        _fail(f"LinearMouse download URL must use HTTPS: {release.url}")
    if parsed_url.netloc != EXPECTED_DOWNLOAD_HOST:
        _fail(f"unexpected LinearMouse download host: {parsed_url.netloc!r}")

    match = EXPECTED_DOWNLOAD_PATH.fullmatch(parsed_url.path)
    if match is None:
        _fail(f"unexpected LinearMouse DMG path format: {parsed_url.path!r}")
    if match.group(1) != release.version:
        _fail(
            "LinearMouse release version does not match DMG path version: "
            f"{release.version!r} != {match.group(1)!r}",
        )


def _prefetch_hash(url: str) -> str:
    nix_binary = shutil.which("nix")
    if nix_binary is None:
        _fail("`nix` executable not found in PATH")

    completed = subprocess.run(
        [
            nix_binary,
            "store",
            "prefetch-file",
            "--json",
            "--hash-type",
            "sha256",
            url,
        ],
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "(no output)"
        _fail(f"failed to prefetch LinearMouse DMG hash:\n{detail}")

    try:
        hash_value = json.loads(completed.stdout).get("hash")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    if not isinstance(hash_value, str):
        _fail("nix prefetch JSON did not include a string `hash` field")
    if re.fullmatch(r"sha256-[A-Za-z0-9+/=]+", hash_value) is None:
        _fail(f"nix prefetch returned an unexpected hash format: {hash_value!r}")
    return hash_value


def _parse_existing(content: str) -> _UpstreamState:
    version_match = re.search(r'^  version = "([^"]+)";$', content, re.MULTILINE)
    url_match = re.search(r'^    url = "([^"]+)";$', content, re.MULTILINE)
    hash_match = re.search(r'^    hash = "([^"]+)";$', content, re.MULTILINE)
    if version_match is None or url_match is None or hash_match is None:
        _fail("could not parse existing LinearMouse source metadata")
    return _UpstreamState(
        version=version_match.group(1),
        url=url_match.group(1),
        hash_sri=hash_match.group(1),
    )


def _render_source(upstream: _UpstreamState) -> str:
    return (
        "{\n"
        f'  version = "{upstream.version}";\n'
        "  src = {\n"
        f'    url = "{upstream.url}";\n'
        f'    hash = "{upstream.hash_sri}";\n'
        "  };\n"
        "}\n"
    )


def _write_atomic(path: Path, content: str) -> None:
    fd, temp_path = tempfile.mkstemp(prefix=f"{path.name}.", dir=path.parent)
    try:
        os.close(fd)
        Path(temp_path).write_text(content, encoding="utf-8", newline="\n")
        Path(temp_path).replace(path)
    finally:
        with contextlib.suppress(OSError):
            Path(temp_path).unlink(missing_ok=True)


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print diff but do not write",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero when updates are available",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="re-download and re-hash the current release",
    )
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    old_content = source_path.read_text(encoding="utf-8")
    existing = _parse_existing(old_content)
    release = _extract_release(
        _fetch_json(RELEASE_API_URL, label="LinearMouse latest GitHub release"),
    )
    _validate_download_url(release)

    if not args.refresh and (existing.version, existing.url) == (
        release.version,
        release.url,
    ):
        _stdout("[update] linearmouse is already up to date")
        return 0

    upstream = _UpstreamState(
        version=release.version,
        url=release.url,
        hash_sri=_prefetch_hash(release.url),
    )
    new_content = _render_source(upstream)
    diff_text = "".join(
        difflib.unified_diff(
            old_content.splitlines(keepends=True),
            new_content.splitlines(keepends=True),
            fromfile=str(source_path),
            tofile=str(source_path),
        ),
    )
    if diff_text:
        sys.stdout.write(diff_text)

    if args.check:
        return 1 if diff_text else 0
    if args.dry_run:
        return 0

    _write_atomic(source_path, new_content)
    _stdout("[update] updated linearmouse")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
