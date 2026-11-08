"""Bounded release discovery, verified downloads and safe source-pin publication."""

from __future__ import annotations

import base64
import difflib
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, HTTPSHandler, Request, build_opener

from notification_process import run
from update_support import HTTPS_CONTEXT, github_api_headers
from update_transaction import commit_files

MAX_METADATA = 4 * 1024 * 1024
USER_AGENT = "Mozilla/5.0 nixpkgs-personal-release-updater/1.0"
FAKE_HASH = "sha256-" + "A" * 43 + "="


class SameOriginRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # ruff: ignore[too-many-arguments,too-many-positional-arguments] - urllib override signature.
        if urlsplit(req.full_url).netloc != urlsplit(newurl).netloc:
            raise ValueError("Release metadata redirected to another origin")
        if urlsplit(newurl).scheme != "https":
            raise ValueError("Release metadata redirected outside HTTPS")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def metadata(url: str) -> bytes:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in {
        "api.github.com",
        "raw.githubusercontent.com",
        "persistent.oaistatic.com",
    }:
        raise ValueError("Release metadata must come from an official HTTPS origin")
    headers = {"User-Agent": USER_AGENT}
    if urlsplit(url).hostname == "api.github.com":
        headers = github_api_headers(USER_AGENT)
    opener = build_opener(HTTPSHandler(context=HTTPS_CONTEXT), SameOriginRedirect())
    with opener.open(Request(url, headers=headers), timeout=30) as response:  # ruff: ignore[suspicious-url-open-usage] - HTTPS origins checked above.
        data = response.read(MAX_METADATA + 1)
    if len(data) > MAX_METADATA:
        raise ValueError("Release metadata exceeds the size limit")
    return data


def json_metadata(url: str) -> dict:
    value = json.loads(metadata(url))
    if not isinstance(value, dict):
        raise TypeError("Expected a release metadata object")
    return value


def version_key(value: str) -> tuple[int, ...]:
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2,3}", value):
        raise ValueError(f"Not a stable release version: {value!r}")
    return tuple(map(int, value.split(".")))


def sri(digest: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Expected an SHA-256 hexadecimal checksum")
    return "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode("ascii")


def validate_sri(value: str) -> str:
    if not re.fullmatch(r"sha256-[A-Za-z0-9+/]{43}=", value):
        raise ValueError("Nix did not return an SHA-256 SRI checksum")
    if base64.b64decode(value[7:], validate=True) == bytes(32):
        raise ValueError("A placeholder checksum cannot be published")
    return value


def prefetch(url: str, *, unpack: bool = False) -> tuple[str, Path]:
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in {
        "github.com",
        "persistent.oaistatic.com",
    }:
        raise ValueError("Release artifacts must come from an official HTTPS origin")
    arguments = ["nix", "store", "prefetch-file", "--json", "--hash-type", "sha256"]
    if unpack:
        arguments.append("--unpack")
    result = run(
        [*arguments, url], check=True, capture_output=True, text=True, timeout=1800
    )
    value = json.loads(result.stdout)
    return validate_sri(value["hash"]), Path(value["storePath"])


def nix_value(value, indent: int = 0) -> str:
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False).replace("${", r"\${")
    if isinstance(value, int):
        return str(value)
    if isinstance(value, dict):
        lines = ["{"]
        for key, child in sorted(value.items()):
            lines.append(
                " " * (indent + 2)
                + f"{nix_value(key)} = {nix_value(child, indent + 2)};"
            )
        return "\n".join([*lines, " " * indent + "}"])
    raise TypeError(f"Unsupported source-pin value: {type(value)}")


def render(pins: dict) -> str:
    return nix_value(pins) + "\n"


def load_pins(path: Path) -> dict:
    result = run(
        ["nix", "eval", "--json", "--file", str(path)],
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    )
    value = json.loads(result.stdout)
    if not isinstance(value, dict):
        raise TypeError("Source pins must be an attribute set")
    return value


def reject_downgrade(current: str, candidate: str) -> None:
    if version_key(candidate) < version_key(current):
        raise ValueError(f"Refusing release downgrade from {current} to {candidate}")


def publish(path: Path, original: bytes, pins: dict, *, dry_run: bool) -> None:
    if path.read_bytes() != original:
        raise ValueError("Source pins changed while preparing the update")
    previous = load_pins(path)
    if previous == pins:
        sys.stdout.write("Already up to date\n")
        return
    prepared = run(
        ["nixfmt"],
        input=render(pins),
        check=True,
        capture_output=True,
        text=True,
        timeout=30,
    ).stdout
    sys.stdout.write(
        "".join(
            difflib.unified_diff(
                original.decode().splitlines(keepends=True),
                prepared.splitlines(keepends=True),
                fromfile="source.nix",
                tofile="source.nix",
            )
        )
    )
    if path.read_bytes() != original:
        raise ValueError("Source pins changed while preparing the update")
    if not dry_run:
        commit_files({path: prepared})
