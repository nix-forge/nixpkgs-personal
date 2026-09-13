#!/usr/bin/env python3
"""Update ``t3-code`` from T3 Code's latest stable GitHub release.

The macOS build uses the official signed ZIP. The Linux build compiles the
application from the tagged source with the workspace's own artifact script,
so this updater also refreshes the offline pnpm/cargo mirrors and the pinned
Electron runtime that the Linux recipe needs.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import difflib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Final, NoReturn
from urllib.error import URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

from update_support import HTTPS_CONTEXT, github_api_headers

if TYPE_CHECKING:
    from collections.abc import Sequence


REPOSITORY: Final = "pingdotgg/t3code"
API_HOST: Final = "api.github.com"
DOWNLOAD_HOST: Final = "github.com"
LATEST_RELEASE_URL: Final = f"https://{API_HOST}/repos/{REPOSITORY}/releases/latest"
ELECTRON_RELEASE_HOST: Final = "github.com"
ELECTRON_OWNER_REPO: Final = "electron/electron"
ELECTRON_HEADERS_HOST: Final = "www.electronjs.org"
ARM64_ZIP_PATTERN: Final = re.compile(r"^T3-Code-([0-9]+\.[0-9]+\.[0-9]+)-arm64\.zip$")
VERSION_PATTERN: Final = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
ELECTRON_VERSION_PATTERN: Final = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
DIGEST_PATTERN: Final = re.compile(r"^sha256:([0-9a-f]{64})$")
SOURCE_PATTERN: Final = re.compile(
    r"\A\{\n"
    r'  version = "([^"]+)";\n'
    r'  appName = "([^"]+)";\n'
    r"  darwin = \{\n"
    r'    url = "([^"]+)";\n'
    r'    hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"  \};\n"
    r"  linux = \{\n"
    r'    rev = "([^"]+)";\n'
    r'    hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r'    pnpmHash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r'    cargoHash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r'    electronVersion = "([^"]+)";\n'
    r'    electronDistUrl = "([^"]+)";\n'
    r'    electronDistHash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r'    electronShasumsUrl = "([^"]+)";\n'
    r'    electronShasumsHash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r'    electronHeadersUrl = "([^"]+)";\n'
    r'    electronHeadersHash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"  };\n"
    r"\}\n\Z"
)
HTTP_USER_AGENT: Final = "nix-conf-updater/1.0 (+https://github.com/NixOS/nixpkgs)"
EXPECTED_APP_NAME: Final = "T3 Code (Alpha)"
FAKE_HASH: Final = "sha256-" + "A" * 43 + "="


@dataclass(frozen=True)
class _ReleaseMeta:
    version: str
    darwin_url: str
    darwin_hash_sri: str
    linux_rev: str


@dataclass(frozen=True)
class _Release:
    version: str
    darwin_url: str
    darwin_hash_sri: str
    linux_rev: str
    electron_version: str
    electron_dist_url: str
    electron_shasums_url: str
    electron_headers_url: str


@dataclass(frozen=True)
class _ExistingSource:
    version: str
    app_name: str
    darwin_url: str
    darwin_hash: str
    linux_rev: str
    linux_hash: str
    pnpm_hash: str
    cargo_hash: str
    electron_version: str
    electron_dist_url: str
    electron_dist_hash: str
    electron_shasums_url: str
    electron_shasums_hash: str
    electron_headers_url: str
    electron_headers_hash: str


@dataclass(frozen=True)
class _ResolvedSource:
    existing: _ExistingSource
    release: _Release
    darwin_hash_sri: str
    linux_hash_sri: str
    pnpm_hash_sri: str
    cargo_hash_sri: str
    electron_dist_hash_sri: str
    electron_shasums_hash_sri: str
    electron_headers_hash_sri: str


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


def _prefetch_hash(url: str, *, label: str, unpack: bool = False) -> str:
    args = [
        _get_nix_binary(),
        "store",
        "prefetch-file",
        "--json",
        "--hash-type",
        "sha256",
    ]
    if unpack:
        # fetchFromGitHub pins the unpacked source tree, not the tarball.
        args.append("--unpack")
    args.append(url)
    completed = subprocess.run(
        args,
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "(no output)"
        _fail(f"failed to prefetch {label} from {url}:\n{detail}")

    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    hash_value = data.get("hash")
    if not isinstance(hash_value, str) or not re.fullmatch(
        r"sha256-[A-Za-z0-9+/=]+", hash_value
    ):
        _fail(f"nix prefetch returned an unexpected hash: {hash_value!r}")
    store_path = data.get("storePath")
    if not isinstance(store_path, str):
        _fail("nix prefetch JSON did not include a string `storePath`")
    return hash_value


def _prefetch_store_path(url: str, *, label: str) -> Path:
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
        _fail(f"failed to prefetch {label} from {url}:\n{detail}")

    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    store_path = data.get("storePath")
    if not isinstance(store_path, str):
        _fail("nix prefetch JSON did not include a string `storePath`")
    path = Path(store_path)
    if not path.is_absolute() or not path.is_file():
        _fail(f"nix returned an unusable store path: {store_path!r}")
    return path


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


def _nix_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("${", "\\${")


def _resolve_nixpkgs(selector: str) -> Path:
    completed = subprocess.run(
        [
            _get_nix_binary(),
            "flake",
            "metadata",
            "--json",
            "--no-write-lock-file",
            selector,
        ],
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        _fail(
            f"could not resolve upstream Nixpkgs {selector!r}:\n{completed.stderr.strip()}"
        )
    try:
        metadata = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"could not parse Nixpkgs metadata: {exc}")
    store_path = metadata.get("path") if isinstance(metadata, dict) else None
    if not isinstance(store_path, str) or not Path(store_path).is_absolute():
        _fail("Nixpkgs metadata did not include an absolute source path")
    return Path(store_path)


def _nix_build_fod_hash(
    *, package_dir: Path, nixpkgs_path: Path, attr: str, label: str
) -> str:
    # Always instantiate Linux, even when the updater is run on Darwin.
    # Dependency fetchers can use the caller's configured remote builders.
    expression = (
        f"let pkgs = import (builtins.toPath {_nix_string(str(nixpkgs_path))}) "
        '{ system = "x86_64-linux"; }; '
        f"in (pkgs.callPackage (builtins.toPath "
        f"{_nix_string(str(package_dir / 'package.nix'))}) {{ }}).passthru.{attr}"
    )
    completed = subprocess.run(
        [
            _get_nix_binary(),
            "build",
            "--no-link",
            "--print-out-paths",
            "--impure",
            "--expr",
            expression,
        ],
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode == 0:
        _fail(
            f"expected {label} to fail with a hash mismatch, but the build "
            "succeeded; the pinned hash may already be current"
        )
    match = re.search(r"got:\s+(sha256-[A-Za-z0-9+/=]+)", completed.stderr)
    if match is None:
        detail = completed.stderr.strip()[-4000:] or "(no output)"
        _fail(f"could not determine the fresh {label} hash:\n{detail}")
    return match.group(1)


def _electron_version_from_tarball(tarball: Path, *, rev: str) -> str:
    try:
        with tarfile.open(tarball, "r:gz") as archive:
            member = next(
                (
                    m
                    for m in archive.getmembers()
                    if m.isfile()
                    and m.name.endswith("apps/desktop/package.json")
                    and m.size < 1024 * 1024
                ),
                None,
            )
            if member is None:
                _fail(
                    f"{rev} source archive has no apps/desktop/package.json; "
                    "cannot pin the Electron runtime"
                )
            extracted = archive.extractfile(member)
            if extracted is None:
                _fail(f"could not read apps/desktop/package.json from {rev}")
            with io.TextIOWrapper(extracted, encoding="utf-8") as handle:
                manifest = json.load(handle)
    except tarfile.TarError as exc:
        _fail(f"failed to inspect the {rev} source archive: {exc}")
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse apps/desktop/package.json from {rev}: {exc}")

    dependencies = manifest.get("dependencies")
    version = dependencies.get("electron") if isinstance(dependencies, dict) else None
    if (
        not isinstance(version, str)
        or ELECTRON_VERSION_PATTERN.fullmatch(version) is None
    ):
        _fail(f"{rev} has an unexpected Electron version: {version!r}")
    return version


def _electron_artifact_urls(electron_version: str) -> tuple[str, str, str]:
    base = (
        f"https://{ELECTRON_RELEASE_HOST}/{ELECTRON_OWNER_REPO}"
        f"/releases/download/v{electron_version}"
    )
    return (
        f"{base}/electron-v{electron_version}-linux-x64.zip",
        f"{base}/SHASUMS256.txt",
        (
            f"https://{ELECTRON_HEADERS_HOST}/headers/v{electron_version}/"
            f"node-v{electron_version}-headers.tar.gz"
        ),
    )


def _discover_release_meta() -> _ReleaseMeta:
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
    linux_rev = f"v{version}"
    return _ReleaseMeta(
        version=version,
        darwin_url=asset_url,
        darwin_hash_sri=_digest_to_sri(digest),
        linux_rev=linux_rev,
    )


def _discover_release(meta: _ReleaseMeta) -> _Release:
    tarball_url = (
        f"https://{DOWNLOAD_HOST}/{REPOSITORY}/archive/{meta.linux_rev}.tar.gz"
    )
    tarball_path = _prefetch_store_path(tarball_url, label="T3 Code source archive")
    electron_version = _electron_version_from_tarball(tarball_path, rev=meta.linux_rev)
    electron_dist_url, electron_shasums_url, electron_headers_url = (
        _electron_artifact_urls(electron_version)
    )
    return _Release(
        version=meta.version,
        darwin_url=meta.darwin_url,
        darwin_hash_sri=meta.darwin_hash_sri,
        linux_rev=meta.linux_rev,
        electron_version=electron_version,
        electron_dist_url=electron_dist_url,
        electron_shasums_url=electron_shasums_url,
        electron_headers_url=electron_headers_url,
    )


def _parse_existing(content: str) -> _ExistingSource:
    match = SOURCE_PATTERN.fullmatch(content)
    if match is None:
        _fail("source.nix does not match the updater-owned format")
    (
        version,
        app_name,
        darwin_url,
        darwin_hash,
        linux_rev,
        linux_hash,
        pnpm_hash,
        cargo_hash,
        electron_version,
        electron_dist_url,
        electron_dist_hash,
        electron_shasums_url,
        electron_shasums_hash,
        electron_headers_url,
        electron_headers_hash,
    ) = match.groups()
    return _ExistingSource(
        version=version,
        app_name=app_name,
        darwin_url=darwin_url,
        darwin_hash=darwin_hash,
        linux_rev=linux_rev,
        linux_hash=linux_hash,
        pnpm_hash=pnpm_hash,
        cargo_hash=cargo_hash,
        electron_version=electron_version,
        electron_dist_url=electron_dist_url,
        electron_dist_hash=electron_dist_hash,
        electron_shasums_url=electron_shasums_url,
        electron_shasums_hash=electron_shasums_hash,
        electron_headers_url=electron_headers_url,
        electron_headers_hash=electron_headers_hash,
    )


def _render_source(resolved: _ResolvedSource) -> str:
    release = resolved.release
    return (
        "{\n"
        f'  version = "{release.version}";\n'
        f'  appName = "{EXPECTED_APP_NAME}";\n'
        "  darwin = {\n"
        f'    url = "{release.darwin_url}";\n'
        f'    hash = "{resolved.darwin_hash_sri}";\n'
        "  };\n"
        "  linux = {\n"
        f'    rev = "{release.linux_rev}";\n'
        f'    hash = "{resolved.linux_hash_sri}";\n'
        f'    pnpmHash = "{resolved.pnpm_hash_sri}";\n'
        f'    cargoHash = "{resolved.cargo_hash_sri}";\n'
        f'    electronVersion = "{release.electron_version}";\n'
        f'    electronDistUrl = "{release.electron_dist_url}";\n'
        f'    electronDistHash = "{resolved.electron_dist_hash_sri}";\n'
        f'    electronShasumsUrl = "{release.electron_shasums_url}";\n'
        f'    electronShasumsHash = "{resolved.electron_shasums_hash_sri}";\n'
        f'    electronHeadersUrl = "{release.electron_headers_url}";\n'
        f'    electronHeadersHash = "{resolved.electron_headers_hash_sri}";\n'
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


def _resolve_hashes(
    existing: _ExistingSource, release: _Release, *, nixpkgs: str
) -> _ResolvedSource:
    darwin_hash_sri = _prefetch_hash(release.darwin_url, label="T3 Code macOS archive")
    if darwin_hash_sri != release.darwin_hash_sri:
        _fail(
            "prefetched macOS archive hash does not match GitHub's published digest: "
            f"{darwin_hash_sri!r} != {release.darwin_hash_sri!r}",
        )

    tarball_url = (
        f"https://{DOWNLOAD_HOST}/{REPOSITORY}/archive/{release.linux_rev}.tar.gz"
    )
    linux_hash_sri = _prefetch_hash(
        tarball_url, label="T3 Code source archive", unpack=True
    )
    electron_dist_hash_sri = _prefetch_hash(
        release.electron_dist_url, label="Electron distribution archive"
    )
    electron_shasums_hash_sri = _prefetch_hash(
        release.electron_shasums_url, label="Electron checksums"
    )
    # fetchzip pins the unpacked headers tree, not the tarball.
    electron_headers_hash_sri = _prefetch_hash(
        release.electron_headers_url, label="Electron headers", unpack=True
    )

    _stdout(
        "[update] resolving offline pnpm and cargo mirrors (this downloads "
        "the full dependency closures once per revision)..."
    )
    # Seed only a temporary package copy. Preview, failure, and interruption
    # must never expose placeholder hashes in the working package.
    package_dir = Path(__file__).resolve().parent
    nixpkgs_path = _resolve_nixpkgs(nixpkgs)
    seed = _render_source(
        _ResolvedSource(
            existing=existing,
            release=release,
            darwin_hash_sri=darwin_hash_sri,
            linux_hash_sri=linux_hash_sri,
            pnpm_hash_sri=FAKE_HASH,
            cargo_hash_sri=FAKE_HASH,
            electron_dist_hash_sri=electron_dist_hash_sri,
            electron_shasums_hash_sri=electron_shasums_hash_sri,
            electron_headers_hash_sri=electron_headers_hash_sri,
        )
    )
    with tempfile.TemporaryDirectory(prefix="t3-code-update-") as temporary:
        candidate = Path(temporary) / "t3-code"
        shutil.copytree(package_dir, candidate)
        # A preview may start from a read-only source, including a Nix store
        # copy. Only the temporary candidate needs to accept replacement pins.
        candidate.chmod(candidate.stat().st_mode | 0o700)
        _write_atomic(candidate / "source.nix", seed)
        pnpm_hash_sri = _nix_build_fod_hash(
            package_dir=candidate,
            nixpkgs_path=nixpkgs_path,
            attr="pnpmDeps",
            label="pnpm mirror",
        )
        cargo_hash_sri = _nix_build_fod_hash(
            package_dir=candidate,
            nixpkgs_path=nixpkgs_path,
            attr="cargoDeps",
            label="cargo vendor",
        )

    return _ResolvedSource(
        existing=existing,
        release=release,
        darwin_hash_sri=darwin_hash_sri,
        linux_hash_sri=linux_hash_sri,
        pnpm_hash_sri=pnpm_hash_sri,
        cargo_hash_sri=cargo_hash_sri,
        electron_dist_hash_sri=electron_dist_hash_sri,
        electron_shasums_hash_sri=electron_shasums_hash_sri,
        electron_headers_hash_sri=electron_headers_hash_sri,
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
        help="re-download and verify every artifact even when release metadata is unchanged",
    )
    parser.add_argument(
        "--nixpkgs",
        default="nixpkgs",
        help="upstream Nixpkgs flake reference for dependency hashes (default: nixpkgs registry)",
    )
    return parser.parse_args(list(argv))


def _quick_matches(existing: _ExistingSource, meta: _ReleaseMeta) -> bool:
    # Every remaining pin (hashes, Electron runtime) is a pure function of the
    # revision, so matching release metadata means the pins are current.
    return (
        existing.version == meta.version
        and existing.app_name == EXPECTED_APP_NAME
        and existing.darwin_url == meta.darwin_url
        and existing.linux_rev == meta.linux_rev
    )


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    old_content = source_path.read_text(encoding="utf-8")
    existing = _parse_existing(old_content)
    meta = _discover_release_meta()

    if not args.refresh and _quick_matches(existing, meta):
        _stdout("[update] t3-code is already up to date")
        return 0

    if args.check:
        _stdout(f"[update] update available for: {meta.linux_rev}")
        return 1

    release = _discover_release(meta)
    resolved = _resolve_hashes(existing, release, nixpkgs=args.nixpkgs)
    new_content = _render_source(resolved)
    diff_text = _build_diff(old_content, new_content, source_path)
    if diff_text:
        sys.stdout.write(diff_text)

    if not diff_text:
        _stdout("[update] t3-code is already up to date")
        return 0
    if args.dry_run:
        return 0

    _write_atomic(source_path, new_content)
    _stdout("[update] updated t3-code")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
