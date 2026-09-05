#!/usr/bin/env python3
"""Update ``openai-codex-desktop`` from OpenAI's official release feeds."""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import contextlib
import difflib
import gzip
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Final, NoReturn
from urllib.error import URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
from scripts.update_support import HTTPS_CONTEXT

if TYPE_CHECKING:
    from collections.abc import Sequence


APPCAST_URL: Final = "https://persistent.oaistatic.com/codex-app-prod/appcast.xml"
LINUX_REPOSITORY_URL: Final = (
    "https://persistent.oaistatic.com/codex-app-prod/linux/deb/"
)
APT_INDEX_URLS: Final = {
    "aarch64-linux": urljoin(
        LINUX_REPOSITORY_URL, "dists/stable/main/binary-arm64/Packages.gz"
    ),
    "x86_64-linux": urljoin(
        LINUX_REPOSITORY_URL, "dists/stable/main/binary-amd64/Packages.gz"
    ),
}
DEBIAN_ARCHITECTURES: Final = {
    "aarch64-linux": "arm64",
    "x86_64-linux": "amd64",
}
SUPPORTED_SYSTEMS: Final = (
    "aarch64-darwin",
    "aarch64-linux",
    "x86_64-linux",
)
EXPECTED_HOST: Final = "persistent.oaistatic.com"
EXPECTED_MACOS_PATH: Final = re.compile(
    r"^/codex-app-prod/([A-Za-z][A-Za-z0-9_-]*)-darwin-arm64-"
    r"([0-9][0-9A-Za-z._-]*)\.zip$"
)
EXPECTED_ARCHIVE_NAMES: Final = frozenset({"ChatGPT", "Codex"})
VERSION_PATTERN: Final = re.compile(r"[0-9][0-9A-Za-z.+:~-]*")
HEX_SHA256_PATTERN: Final = re.compile(r"[0-9a-f]{64}")
ED25519_SIGNATURE_BYTES: Final = 64
AR_MEMBER_HEADER_BYTES: Final = 60
SRI_SHA256_PATTERN: Final = re.compile(r"sha256-[A-Za-z0-9+/]{43}=")
SPARKLE_NAMESPACE: Final = {
    "sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"
}
HTTP_USER_AGENT: Final = (
    "nixpkgs-personal-updater/1.0 (+https://github.com/nix-forge/nixpkgs-personal)"
)
SOURCE_PATTERN: Final = re.compile(
    r"\A\{\n"
    r'  appName = "([^"]+)";\n'
    r"  sources = \{\n"
    r"    aarch64-darwin = \{\n"
    r'      version = "([^"]+)";\n'
    r'      url = "([^"]+)";\n'
    r'      hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"    \};\n"
    r"    aarch64-linux = \{\n"
    r'      version = "([^"]+)";\n'
    r'      url = "([^"]+)";\n'
    r'      hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"    \};\n"
    r"    x86_64-linux = \{\n"
    r'      version = "([^"]+)";\n'
    r'      url = "([^"]+)";\n'
    r'      hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"    \};\n"
    r"  \};\n"
    r"\}\n\Z"
)


@dataclass(frozen=True)
class _Source:
    version: str
    url: str
    hash_sri: str


@dataclass(frozen=True)
class _DiscoveredSource:
    version: str
    url: str
    expected_size: int
    published_sha256: str | None = None


@dataclass(frozen=True)
class _Release:
    app_name: str
    sources: dict[str, _DiscoveredSource]


@dataclass(frozen=True)
class _UpstreamState:
    app_name: str
    sources: dict[str, _Source]


@dataclass(frozen=True)
class _PrefetchedSource:
    hash_sri: str
    store_path: Path


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _validate_feed_url(url: str, *, label: str) -> None:
    parsed_url = urlparse(url)
    if (
        parsed_url.scheme != "https"
        or parsed_url.netloc != EXPECTED_HOST
        or parsed_url.query
        or parsed_url.fragment
    ):
        _fail(f"unexpected URL for {label}: {url}")


def _fetch_bytes(url: str, *, label: str, timeout: int = 30) -> bytes:
    _validate_feed_url(url, label=label)
    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(request, timeout=timeout, context=HTTPS_CONTEXT) as response:
            return response.read()
    except (OSError, URLError) as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")


def _fetch_xml(url: str, *, label: str) -> ET.Element:
    try:
        return ET.fromstring(_fetch_bytes(url, label=label))
    except ET.ParseError as exc:
        _fail(f"failed to parse XML for {label} from {url}: {exc}")


def _positive_integer(value: str | None, *, label: str) -> int:
    try:
        result = int(value or "")
    except ValueError:
        _fail(f"{label} is not an integer: {value!r}")
    if result <= 0:
        _fail(f"{label} is not positive: {result}")
    return result


def _validate_macos_url(version: str, url: str) -> str:
    _validate_feed_url(url, label="macOS archive")
    parsed_url = urlparse(url)
    match = EXPECTED_MACOS_PATH.fullmatch(parsed_url.path)
    if match is None:
        _fail(f"unexpected macOS archive path: {parsed_url.path!r}")

    archive_name, version_from_path = match.groups()
    if archive_name not in EXPECTED_ARCHIVE_NAMES:
        _fail(f"unexpected macOS application name: {archive_name!r}")
    if version_from_path != version:
        _fail(
            "appcast version does not match the macOS archive path: "
            f"{version!r} != {version_from_path!r}"
        )
    return archive_name


def _parse_debian_fields(content: str, *, label: str) -> list[dict[str, str]]:
    paragraphs: list[dict[str, str]] = []
    fields: dict[str, str] = {}
    current_field: str | None = None

    for line in [*content.splitlines(), ""]:
        if not line:
            if fields:
                paragraphs.append(fields)
                fields = {}
            current_field = None
            continue
        if line.startswith((" ", "\t")):
            if current_field is None:
                _fail(f"{label} starts a paragraph with a continuation line")
            fields[current_field] = f"{fields[current_field]}\n{line[1:]}"
            continue

        name, separator, value = line.partition(":")
        if not separator or not name or name in fields:
            _fail(f"{label} contains a malformed or duplicate field")
        current_field = name
        fields[name] = value.lstrip()

    return paragraphs


def _discover_macos_source() -> tuple[str, _DiscoveredSource]:
    root = _fetch_xml(APPCAST_URL, label="Codex appcast")
    item = root.find("./channel/item")
    if item is None:
        _fail("Codex appcast does not include any items")

    version_element = item.find("./sparkle:shortVersionString", SPARKLE_NAMESPACE)
    enclosure = item.find("./enclosure")
    if (
        version_element is None
        or version_element.text is None
        or VERSION_PATTERN.fullmatch(version_element.text.strip()) is None
    ):
        _fail("latest Codex appcast item has no valid short version")
    if enclosure is None:
        _fail("latest Codex appcast item has no enclosure")

    version = version_element.text.strip()
    url = enclosure.attrib.get("url")
    if not isinstance(url, str) or not url:
        _fail("latest Codex appcast enclosure has no URL")
    app_name = _validate_macos_url(version, url)
    expected_size = _positive_integer(
        enclosure.attrib.get("length"), label="macOS appcast archive length"
    )
    signature = enclosure.attrib.get(f"{{{SPARKLE_NAMESPACE['sparkle']}}}edSignature")
    try:
        decoded_signature = base64.b64decode(signature or "", validate=True)
    except ValueError:
        _fail("latest Codex appcast item has an invalid Sparkle signature")
    if len(decoded_signature) != ED25519_SIGNATURE_BYTES:
        _fail("latest Codex appcast item has no valid Ed25519 Sparkle signature")

    return app_name, _DiscoveredSource(
        version=version,
        url=url,
        expected_size=expected_size,
    )


def _discover_linux_source(system: str) -> _DiscoveredSource:
    architecture = DEBIAN_ARCHITECTURES[system]
    index_url = APT_INDEX_URLS[system]
    try:
        content = gzip.decompress(
            _fetch_bytes(index_url, label=f"{system} APT package index")
        ).decode("utf-8")
    except (gzip.BadGzipFile, UnicodeDecodeError) as exc:
        _fail(f"failed to decode {system} APT package index: {exc}")

    packages = [
        fields
        for fields in _parse_debian_fields(content, label=f"{system} APT index")
        if fields.get("Package") == "chatgpt"
        and fields.get("Architecture") == architecture
    ]
    if len(packages) != 1:
        _fail(
            f"expected one chatgpt/{architecture} record in the APT index, "
            f"found {len(packages)}"
        )

    fields = packages[0]
    version = fields.get("Version", "")
    filename = fields.get("Filename", "")
    published_sha256 = fields.get("SHA256", "")
    if VERSION_PATTERN.fullmatch(version) is None:
        _fail(f"unexpected {system} package version: {version!r}")
    expected_filename = f"pool/main/c/chatgpt/chatgpt_{version}_{architecture}.deb"
    if filename != expected_filename:
        _fail(f"unexpected {system} package filename: {filename!r}")
    if HEX_SHA256_PATTERN.fullmatch(published_sha256) is None:
        _fail(f"unexpected {system} package SHA256: {published_sha256!r}")
    if fields.get("Maintainer") != "OpenAI <support@openai.com>":
        _fail(f"unexpected {system} package maintainer")

    return _DiscoveredSource(
        version=version,
        url=urljoin(LINUX_REPOSITORY_URL, filename),
        expected_size=_positive_integer(
            fields.get("Size"), label=f"{system} package size"
        ),
        published_sha256=published_sha256,
    )


def _discover_release() -> _Release:
    app_name, macos_source = _discover_macos_source()
    sources = {"aarch64-darwin": macos_source}
    sources.update({
        system: _discover_linux_source(system) for system in APT_INDEX_URLS
    })
    return _Release(app_name=app_name, sources=sources)


def _get_nix_binary() -> str:
    nix_binary = shutil.which("nix")
    if isinstance(nix_binary, str):
        return nix_binary
    _fail("`nix` executable not found in PATH")


def _prefetch_source(url: str) -> _PrefetchedSource:
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
        _fail(f"failed to prefetch {url}:\n{detail}")

    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"failed to parse nix prefetch JSON output: {exc}")

    hash_value = data.get("hash")
    store_path_value = data.get("storePath")
    if (
        not isinstance(hash_value, str)
        or SRI_SHA256_PATTERN.fullmatch(hash_value) is None
    ):
        _fail(f"nix returned an invalid source hash: {hash_value!r}")
    if not isinstance(store_path_value, str):
        _fail("nix prefetch JSON did not include a string `storePath`")

    store_path = Path(store_path_value)
    if not store_path.is_absolute() or not store_path.is_file():
        _fail(f"nix returned an unusable store path: {store_path_value!r}")
    return _PrefetchedSource(hash_sri=hash_value, store_path=store_path)


def _read_ar_member(path: Path, member_names: frozenset[str]) -> tuple[str, bytes]:
    with path.open("rb") as archive:
        if archive.read(8) != b"!<arch>\n":
            _fail(f"{path} is not an ar archive")

        while True:
            header = archive.read(AR_MEMBER_HEADER_BYTES)
            if not header:
                break
            if len(header) != AR_MEMBER_HEADER_BYTES or header[-2:] != b"`\n":
                _fail(f"{path} has a malformed ar member header")
            try:
                name = header[:16].decode("ascii").strip().removesuffix("/")
                size = int(header[48:58].decode("ascii").strip())
            except (UnicodeDecodeError, ValueError) as exc:
                _fail(f"{path} has an invalid ar member header: {exc}")
            if size < 0:
                _fail(f"{path} has a negative ar member size")

            if name in member_names:
                data = archive.read(size)
                if len(data) != size:
                    _fail(f"{path} has a truncated {name} member")
                return name, data
            archive.seek(size + (size % 2), io.SEEK_CUR)

    _fail(f"{path} does not contain a supported Debian control archive")


def _read_debian_control(path: Path) -> dict[str, str]:
    member_name, compressed_control = _read_ar_member(
        path, frozenset({"control.tar.gz", "control.tar.xz"})
    )
    mode = "r:gz" if member_name.endswith(".gz") else "r:xz"
    with tarfile.open(fileobj=io.BytesIO(compressed_control), mode=mode) as archive:
        members = {member.name.removeprefix("./"): member for member in archive}
        member = members.get("control")
        if member is None or not member.isfile() or member.size > 128 * 1024:
            _fail(f"{path} has no valid Debian control file")
        control_file = archive.extractfile(member)
        if control_file is None:
            _fail(f"could not read the Debian control file from {path}")
        try:
            content = control_file.read().decode("utf-8")
        except UnicodeDecodeError as exc:
            _fail(f"Debian control file in {path} is not UTF-8: {exc}")

    paragraphs = _parse_debian_fields(content, label=f"Debian control file in {path}")
    if len(paragraphs) != 1:
        _fail(f"Debian control file in {path} must contain exactly one paragraph")
    return paragraphs[0]


def _hex_sha256_to_sri(value: str) -> str:
    if HEX_SHA256_PATTERN.fullmatch(value) is None:
        _fail(f"invalid hexadecimal SHA256: {value!r}")
    return f"sha256-{base64.b64encode(bytes.fromhex(value)).decode('ascii')}"


def _validate_prefetched_source(
    system: str,
    discovered: _DiscoveredSource,
    prefetched: _PrefetchedSource,
) -> None:
    actual_size = prefetched.store_path.stat().st_size
    if actual_size != discovered.expected_size:
        _fail(
            f"unexpected size for {system}: expected {discovered.expected_size}, "
            f"got {actual_size}"
        )

    if discovered.published_sha256 is None:
        return
    published_sri = _hex_sha256_to_sri(discovered.published_sha256)
    if prefetched.hash_sri != published_sri:
        _fail(
            f"downloaded {system} hash does not match OpenAI's APT index: "
            f"{prefetched.hash_sri!r} != {published_sri!r}"
        )

    fields = _read_debian_control(prefetched.store_path)
    expected_fields = {
        "Package": "chatgpt",
        "Version": discovered.version,
        "Architecture": DEBIAN_ARCHITECTURES[system],
        "Maintainer": "OpenAI <support@openai.com>",
    }
    for field, expected in expected_fields.items():
        actual = fields.get(field)
        if actual != expected:
            _fail(
                f"unexpected {field} in {system} package: "
                f"expected {expected!r}, got {actual!r}"
            )


def _parse_existing(content: str) -> _UpstreamState:
    match = SOURCE_PATTERN.fullmatch(content)
    if match is None:
        _fail("source.nix does not match the updater-owned format")

    app_name, *source_values = match.groups()
    sources = {
        system: _Source(*source_values[index * 3 : index * 3 + 3])
        for index, system in enumerate(SUPPORTED_SYSTEMS)
    }
    return _UpstreamState(app_name=app_name, sources=sources)


def _source_matches_discovery(existing: _Source, discovered: _DiscoveredSource) -> bool:
    if existing.version != discovered.version or existing.url != discovered.url:
        return False
    return discovered.published_sha256 is None or existing.hash_sri == (
        _hex_sha256_to_sri(discovered.published_sha256)
    )


def _changed_systems(existing: _UpstreamState, release: _Release) -> list[str]:
    return [
        system
        for system in SUPPORTED_SYSTEMS
        if not _source_matches_discovery(
            existing.sources[system], release.sources[system]
        )
    ]


def _fetch_upstream(
    release: _Release,
    existing: _UpstreamState,
    systems_to_fetch: Sequence[str],
) -> _UpstreamState:
    if not systems_to_fetch:
        return _UpstreamState(app_name=release.app_name, sources=existing.sources)

    prefetched: dict[str, _PrefetchedSource] = {}
    with concurrent.futures.ThreadPoolExecutor(
        max_workers=len(systems_to_fetch)
    ) as pool:
        futures = {
            system: pool.submit(_prefetch_source, release.sources[system].url)
            for system in systems_to_fetch
        }
        for system in sorted(futures):
            prefetched[system] = futures[system].result()

    sources = dict(existing.sources)
    for system, result in prefetched.items():
        discovered = release.sources[system]
        _validate_prefetched_source(system, discovered, result)
        sources[system] = _Source(
            version=discovered.version,
            url=discovered.url,
            hash_sri=result.hash_sri,
        )
    return _UpstreamState(app_name=release.app_name, sources=sources)


def _render_source(upstream: _UpstreamState) -> str:
    lines = [
        "{",
        f'  appName = "{upstream.app_name}";',
        "  sources = {",
    ]
    for system in SUPPORTED_SYSTEMS:
        source = upstream.sources[system]
        lines.extend([
            f"    {system} = {{",
            f'      version = "{source.version}";',
            f'      url = "{source.url}";',
            f'      hash = "{source.hash_sri}";',
            "    };",
        ])
    lines.extend(["  };", "}"])
    return "\n".join(lines) + "\n"


def _write_atomic(path: Path, content: str) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=f"{path.name}.", dir=path.parent)
    try:
        os.close(descriptor)
        Path(temporary).write_text(content, encoding="utf-8", newline="\n")
        Path(temporary).replace(path)
    finally:
        with contextlib.suppress(OSError):
            Path(temporary).unlink(missing_ok=True)


def _build_diff(old: str, new: str, path: Path) -> str:
    return "".join(
        difflib.unified_diff(
            old.splitlines(keepends=True),
            new.splitlines(keepends=True),
            fromfile=str(path),
            tofile=str(path),
        )
    )


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="print changes only")
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero when an update is available",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="re-download and validate every artifact for the current release",
    )
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).with_name("source.nix")
    old_content = source_path.read_text(encoding="utf-8")
    existing = _parse_existing(old_content)
    release = _discover_release()
    changed_systems = _changed_systems(existing, release)
    app_name_changed = existing.app_name != release.app_name

    if not args.refresh and not changed_systems and not app_name_changed:
        _stdout("[update] openai-codex-desktop is already up to date")
        return 0
    if args.check and not args.refresh:
        changed = ", ".join(changed_systems) or "application metadata"
        _stdout(f"[update] update available for: {changed}")
        return 1

    systems_to_fetch = list(SUPPORTED_SYSTEMS) if args.refresh else changed_systems
    upstream = _fetch_upstream(release, existing, systems_to_fetch)
    if app_name_changed:
        upstream = _UpstreamState(app_name=release.app_name, sources=upstream.sources)
    new_content = _render_source(upstream)
    diff_text = _build_diff(old_content, new_content, source_path)
    if diff_text:
        sys.stdout.write(diff_text)

    if args.check:
        return 1 if diff_text else 0
    if args.dry_run:
        return 0

    _write_atomic(source_path, new_content)
    _stdout("[update] updated openai-codex-desktop")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
