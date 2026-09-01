#!/usr/bin/env python3
"""Update Vorssaint from its latest stable GitHub release."""

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
from http import HTTPStatus
from pathlib import Path
from typing import TYPE_CHECKING, Final, NoReturn
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from scripts.update_support import HTTPS_CONTEXT

if TYPE_CHECKING:
    from collections.abc import Sequence


GITHUB_API: Final = "https://api.github.com/repos/vorssaint/vorssaint-utils"
VERSION_PATTERN: Final = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
SOURCE_PATTERN: Final = re.compile(
    r"""\{\n  version = "([^"]+)";\n  src = \{\n    owner = "vorssaint";\n    repo = "vorssaint-utils";\n    rev = "([0-9a-f]{40})";\n    hash = "(sha256-[A-Za-z0-9+/=]+)";\n  \};\n\}\n"""
)


@dataclass(frozen=True)
class _Release:
    version: str
    rev: str
    hash_sri: str


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _fetch_json(url: str, *, label: str) -> object:
    parsed_url = urlparse(url)
    if parsed_url.scheme != "https":
        _fail(f"unsupported URL scheme for {label}: {parsed_url.scheme!r}")

    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "nix-forge-nixpkgs-personal-updater",
    }
    github_token = os.environ.get("GITHUB_TOKEN")
    if github_token:
        headers["Authorization"] = f"Bearer {github_token}"

    try:
        request = Request(url, headers=headers)
        with urlopen(request, timeout=30, context=HTTPS_CONTEXT) as response:
            return json.load(response)
    except HTTPError as exc:
        if (
            exc.code == HTTPStatus.FORBIDDEN
            and exc.headers.get("X-RateLimit-Remaining") == "0"
        ):
            _fail(
                f"GitHub API rate limit exhausted while fetching {label}; "
                "provide GITHUB_TOKEN when running the updater"
            )
        _fail(f"failed to fetch {label} from {url}: HTTP {exc.code}")
    except (json.JSONDecodeError, URLError) as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")


def _resolve_tag(tag: str) -> str:
    reference = _fetch_json(
        f"{GITHUB_API}/git/ref/tags/{quote(tag, safe='')}",
        label="Vorssaint release tag",
    )
    if not isinstance(reference, dict):
        _fail("Vorssaint release tag was not a JSON object")

    target = reference.get("object")
    if not isinstance(target, dict):
        _fail("Vorssaint release tag did not have an object")

    target_type = target.get("type")
    target_sha = target.get("sha")
    if target_type == "commit" and isinstance(target_sha, str):
        return target_sha
    if target_type != "tag" or not isinstance(target_sha, str):
        _fail("Vorssaint release tag did not point to a commit or annotated tag")

    annotated_tag = _fetch_json(
        f"{GITHUB_API}/git/tags/{target_sha}",
        label="annotated Vorssaint release tag",
    )
    if not isinstance(annotated_tag, dict):
        _fail("annotated Vorssaint release tag was not a JSON object")

    commit = annotated_tag.get("object")
    if not isinstance(commit, dict) or commit.get("type") != "commit":
        _fail("annotated Vorssaint release tag did not point to a commit")
    commit_sha = commit.get("sha")
    if (
        not isinstance(commit_sha, str)
        or re.fullmatch(r"[0-9a-f]{40}", commit_sha) is None
    ):
        _fail(f"annotated Vorssaint release tag had an invalid commit: {commit_sha!r}")
    return commit_sha


def _prefetch_source(rev: str) -> str:
    nix_binary = shutil.which("nix")
    if nix_binary is None:
        _fail("`nix` executable not found in PATH")

    url = f"https://github.com/vorssaint/vorssaint-utils/archive/{rev}.tar.gz"
    completed = subprocess.run(
        [
            nix_binary,
            "store",
            "prefetch-file",
            "--unpack",
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
        _fail(f"failed to prefetch Vorssaint source:\n{completed.stderr.strip()}")

    try:
        response = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse Nix prefetch response: {exc}")
    hash_sri = response.get("hash") if isinstance(response, dict) else None
    if (
        not isinstance(hash_sri, str)
        or re.fullmatch(r"sha256-[A-Za-z0-9+/=]+", hash_sri) is None
    ):
        _fail(f"Nix prefetch returned an invalid SHA-256: {hash_sri!r}")
    return hash_sri


def _discover_release(existing: _Release, *, refresh: bool) -> _Release:
    latest = _fetch_json(
        f"{GITHUB_API}/releases/latest", label="latest Vorssaint release"
    )
    if not isinstance(latest, dict):
        _fail("latest Vorssaint release was not a JSON object")
    if latest.get("draft") is not False or latest.get("prerelease") is not False:
        _fail("latest Vorssaint release is not stable and published")

    tag = latest.get("tag_name")
    if not isinstance(tag, str) or not tag.startswith("v"):
        _fail(f"latest Vorssaint release has an invalid tag: {tag!r}")
    version = tag.removeprefix("v")
    if VERSION_PATTERN.fullmatch(version) is None:
        _fail(f"latest Vorssaint release has an invalid version: {version!r}")

    rev = _resolve_tag(tag)
    if version == existing.version and rev == existing.rev and not refresh:
        return existing
    return _Release(version=version, rev=rev, hash_sri=_prefetch_source(rev))


def _render_source(release: _Release) -> str:
    return (
        "{\n"
        f'  version = "{release.version}";\n'
        "  src = {\n"
        '    owner = "vorssaint";\n'
        '    repo = "vorssaint-utils";\n'
        f'    rev = "{release.rev}";\n'
        f'    hash = "{release.hash_sri}";\n'
        "  };\n"
        "}\n"
    )


def _write_atomic(path: Path, content: str) -> None:
    file_descriptor, temporary_path = tempfile.mkstemp(
        prefix=f"{path.name}.", dir=path.parent
    )
    try:
        os.close(file_descriptor)
        Path(temporary_path).write_text(content, encoding="utf-8", newline="\n")
        Path(temporary_path).replace(path)
    finally:
        with contextlib.suppress(OSError):
            Path(temporary_path).unlink(missing_ok=True)


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true", help="exit non-zero when an update is available"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="print a diff without writing source.nix"
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="re-download and verify source even when the release is unchanged",
    )
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    old_content = source_path.read_text(encoding="utf-8")
    match = SOURCE_PATTERN.fullmatch(old_content)
    if match is None:
        _fail("could not parse source.nix")

    current = _Release(
        version=match.group(1), rev=match.group(2), hash_sri=match.group(3)
    )
    updated = _discover_release(current, refresh=args.refresh)
    new_content = _render_source(updated)
    if new_content == old_content:
        _stdout("[update] vorssaint is already up to date")
        return 0

    diff = "".join(
        difflib.unified_diff(
            old_content.splitlines(keepends=True),
            new_content.splitlines(keepends=True),
            fromfile=str(source_path),
            tofile=str(source_path),
        )
    )
    if args.check:
        _stdout(diff)
        return 1
    if args.dry_run:
        _stdout(diff)
        return 0

    _write_atomic(source_path, new_content)
    _stdout(f"[update] vorssaint: {current.version} -> {updated.version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
