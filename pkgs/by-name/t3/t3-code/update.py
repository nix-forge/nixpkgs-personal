#!/usr/bin/env python3
"""Update ``t3-code`` from T3 Code's latest stable GitHub release."""

from __future__ import annotations

import argparse
import base64
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
from typing import TYPE_CHECKING, Final, NoReturn
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from scripts.update_support import HTTPS_CONTEXT, github_api_headers

if TYPE_CHECKING:
    from collections.abc import Sequence


REPOSITORY: Final = "pingdotgg/t3code"
API_HOST: Final = "api.github.com"
DOWNLOAD_HOST: Final = "github.com"
LATEST_RELEASE_URL: Final = f"https://{API_HOST}/repos/{REPOSITORY}/releases/latest"
ARM64_ZIP_PATTERN: Final = re.compile(r"^T3-Code-([0-9]+\.[0-9]+\.[0-9]+)-arm64\.zip$")
VERSION_PATTERN: Final = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
DIGEST_PATTERN: Final = re.compile(r"^sha256:([0-9a-f]{64})$")
SOURCE_PATTERN: Final = re.compile(
    r"\A\{\n"
    r'  version = "([^"]+)";\n'
    r"  src = \{\n"
    r'    url = "([^"]+)";\n'
    r'    hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"  \};\n"
    r"\}\n\Z"
)
HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"


@dataclass(frozen=True)
class _Release:
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
    if parsed_url.scheme != "https" or parsed_url.netloc != API_HOST:
        _fail(f"unexpected URL for {label}: {url!r}")

    headers = github_api_headers(HTTP_USER_AGENT)
    try:
        request = Request(url, headers=headers)
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
            return json.load(response)
    except URLError as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse JSON for {label} from {url}: {exc}")


def _get_nix_binary() -> str:
    nix_binary = shutil.which("nix")
    if isinstance(nix_binary, str):
        return nix_binary

    _fail("`nix` executable not found in PATH")


def _prefetch_hash(url: str) -> str:
    completed = subprocess.run(
        [
            _get_nix_binary(),
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
        _fail(f"failed to prefetch T3 Code archive hash:\n{detail}")

    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    hash_value = data.get("hash")
    if not isinstance(hash_value, str) or not re.fullmatch(
        r"sha256-[A-Za-z0-9+/=]+", hash_value
    ):
        _fail(f"nix prefetch returned an unexpected hash: {hash_value!r}")
    return hash_value


def _digest_to_sri(digest: str) -> str:
    match = DIGEST_PATTERN.fullmatch(digest)
    if match is None:
        _fail(f"unexpected GitHub asset digest: {digest!r}")
    return "sha256-" + base64.b64encode(bytes.fromhex(match.group(1))).decode("ascii")


def _validate_download_url(url: str, version: str) -> None:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https" or parsed_url.netloc != DOWNLOAD_HOST:
        _fail(f"unexpected T3 Code download URL: {url!r}")

    expected_path = (
        f"/{REPOSITORY}/releases/download/v{version}/T3-Code-{version}-arm64.zip"
    )
    if (
        parsed_url.path != expected_path
        or parsed_url.params
        or parsed_url.query
        or parsed_url.fragment
    ):
        _fail(f"unexpected T3 Code download path: {url!r}")


def _discover_release() -> _Release:
    data = _fetch_json(LATEST_RELEASE_URL, label="latest T3 Code release")
    if not isinstance(data, dict):
        _fail("latest T3 Code release was not a JSON object")
    if data.get("draft") is not False or data.get("prerelease") is not False:
        _fail("latest T3 Code release is not a stable published release")

    tag_name = data.get("tag_name")
    if not isinstance(tag_name, str) or not tag_name.startswith("v"):
        _fail(f"latest T3 Code release has an unexpected tag: {tag_name!r}")
    version = tag_name.removeprefix("v")
    if VERSION_PATTERN.fullmatch(version) is None:
        _fail(f"latest T3 Code release has an unexpected version: {version!r}")

    assets = data.get("assets")
    if not isinstance(assets, list):
        _fail("latest T3 Code release did not include an asset list")

    expected_name = f"T3-Code-{version}-arm64.zip"
    candidates = [
        asset
        for asset in assets
        if isinstance(asset, dict) and asset.get("name") == expected_name
    ]
    if len(candidates) != 1:
        _fail(f"expected exactly one {expected_name!r} asset, found {len(candidates)}")

    asset = candidates[0]
    asset_name = asset.get("name")
    if (
        not isinstance(asset_name, str)
        or ARM64_ZIP_PATTERN.fullmatch(asset_name) is None
    ):
        _fail(f"unexpected T3 Code ARM64 ZIP asset name: {asset_name!r}")
    asset_url = asset.get("browser_download_url")
    digest = asset.get("digest")
    if not isinstance(asset_url, str):
        _fail("T3 Code ARM64 ZIP asset did not include a download URL")
    if not isinstance(digest, str):
        _fail("T3 Code ARM64 ZIP asset did not include a SHA-256 digest")

    _validate_download_url(asset_url, version)
    return _Release(version=version, url=asset_url, hash_sri=_digest_to_sri(digest))


def _source_matches_release(content: str, release: _Release) -> bool:
    match = SOURCE_PATTERN.fullmatch(content)
    if match is None:
        return False
    return match.groups() == (release.version, release.url, release.hash_sri)


def _render_source(release: _Release) -> str:
    return (
        "{\n"
        f'  version = "{release.version}";\n'
        "  src = {\n"
        f'    url = "{release.url}";\n'
        f'    hash = "{release.hash_sri}";\n'
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


def _build_diff(old: str, new: str, path: Path) -> str:
    return "".join(
        difflib.unified_diff(
            old.splitlines(keepends=True),
            new.splitlines(keepends=True),
            fromfile=str(path),
            tofile=str(path),
        ),
    )


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run", action="store_true", help="print diff but do not write"
    )
    parser.add_argument(
        "--check", action="store_true", help="exit non-zero when updates are available"
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="re-download and verify the archive even when release metadata is unchanged",
    )
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    old_content = source_path.read_text(encoding="utf-8")
    release = _discover_release()

    if not args.refresh and _source_matches_release(old_content, release):
        _stdout("[update] t3-code is already up to date")
        return 0

    prefetched_hash = _prefetch_hash(release.url)
    if prefetched_hash != release.hash_sri:
        _fail(
            "prefetched T3 Code archive hash does not match GitHub's published digest: "
            f"{prefetched_hash!r} != {release.hash_sri!r}",
        )

    new_content = _render_source(release)
    diff_text = _build_diff(old_content, new_content, source_path)
    if diff_text:
        sys.stdout.write(diff_text)

    if not diff_text:
        _stdout("[update] t3-code is already up to date")
        return 0
    if args.check:
        return 1
    if args.dry_run:
        return 0

    _write_atomic(source_path, new_content)
    _stdout("[update] updated t3-code")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
