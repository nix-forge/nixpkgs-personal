#!/usr/bin/env python3
"""Refresh a Moonfin release, Flutter lock, Git hashes, and macOS asset."""

from __future__ import annotations

import argparse
import base64
import importlib
import json
import os
import re
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from notification_process import run as run_command
from update_transaction import commit_files, preview

PACKAGE = Path(__file__).resolve().parent
REPO = "Moonfin-Client/Moonfin-Core"
GITHUB_REPOSITORY_PARTS = 2


def command(*args: str) -> str:
    result = run_command(
        args, check=False, capture_output=True, text=True, timeout=1800
    )
    if result.returncode:
        raise RuntimeError(f"{' '.join(args[:2])}: {result.stderr.strip()}")
    return result.stdout.strip()


def github_json(path: str) -> dict:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "nix-conf-updater",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/{path}", headers=headers
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        value = json.load(response)
    if not isinstance(value, dict):
        raise TypeError("unexpected GitHub API response")
    return value


def release(version: str | None) -> tuple[str, dict]:
    path = (
        "releases/latest"
        if version is None
        else f"releases/tags/{urllib.parse.quote(version, safe='')}"
    )
    data = github_json(path)
    tag = data["tag_name"]
    if (
        data.get("draft")
        or data.get("prerelease")
        or not re.fullmatch(r"\d+\.\d+\.\d+", tag)
    ):
        raise ValueError(f"unsupported release: {tag}")
    return tag, data


def tag_commit(tag: str) -> str:
    refs = command(
        "git",
        "ls-remote",
        f"https://github.com/{REPO}.git",
        f"refs/tags/{tag}",
        f"refs/tags/{tag}^{{}}",
    ).splitlines()
    if not refs:
        raise ValueError(f"release tag does not exist: {tag}")
    commits = dict(line.split("\t", 1)[::-1] for line in refs)
    revision = commits.get(f"refs/tags/{tag}^{{}}") or commits.get(f"refs/tags/{tag}")
    if revision is None or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"cannot resolve release tag: {tag}")
    return revision


def prefetch(url: str, *, unpack: bool = True) -> dict:
    args = ["nix", "store", "prefetch-file", "--json"]
    if unpack:
        args.append("--unpack")
    result = json.loads(command(*args, url))
    if not result.get("hash", "").startswith("sha256-"):
        raise ValueError(f"missing source hash for {url}")
    return result


def git_hashes(lock: dict) -> dict[str, str]:
    hashes: dict[str, str] = {}
    sources: dict[tuple[str, str], str] = {}
    for name, package in lock["packages"].items():
        if package["source"] != "git":
            continue
        description = package["description"]
        url = urllib.parse.urlsplit(description["url"])
        parts = url.path.removesuffix(".git").strip("/").split("/")
        revision = description["resolved-ref"]
        if (
            url.scheme != "https"
            or url.hostname != "github.com"
            or len(parts) != GITHUB_REPOSITORY_PARTS
        ):
            raise ValueError(f"Git dependency {name} is not a GitHub repository")
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError(f"Git dependency {name} has no immutable revision")
        key = ("/".join(parts), revision)
        if key not in sources:
            sources[key] = prefetch(
                f"https://github.com/{key[0]}/archive/{revision}.tar.gz"
            )["hash"]
        hashes[name] = sources[key]
    return hashes


def check_flutter_sdk(lock: dict) -> None:
    constraint = lock.get("sdks", {}).get("flutter", "")
    minimum = re.match(r"^>=(\d+)\.(\d+)\.\d+", constraint)
    if minimum is None:
        raise ValueError(f"unsupported Flutter SDK constraint: {constraint!r}")
    required = tuple(map(int, minimum.groups()))
    builders = re.findall(
        r"(?m)^flutter(\d)(\d{2})\.buildFlutterApplication \{$",
        (PACKAGE / "linux.nix").read_text(),
    )
    if len(builders) != 1:
        raise ValueError("cannot identify the pinned Flutter builder in linux.nix")
    pinned = tuple(map(int, builders[0]))
    if required > pinned:
        raise ValueError(
            f"Flutter SDK {required[0]}.{required[1]} is required; update linux.nix builder"
        )


def field(source: str, name: str) -> str:
    values = re.findall(rf'^  {re.escape(name)} = "([^"]+)";$', source, re.MULTILINE)
    if len(values) != 1:
        raise ValueError(f"expected one {name} field in source.nix")
    return values[0]


def replace(source: str, name: str, value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9+./=:_-]+", value):
        raise ValueError(f"invalid {name}: {value!r}")
    old = field(source, name)
    return source.replace(f'  {name} = "{old}";', f'  {name} = "{value}";', 1)


def asset_hash(data: dict, tag: str) -> tuple[str, str]:
    name = f"Moonfin_macOS_v{tag}.dmg"
    assets = [asset for asset in data["assets"] if asset["name"] == name]
    if len(assets) != 1:
        raise ValueError(f"expected one macOS asset named {name}")
    asset = assets[0]
    expected = f"https://github.com/{REPO}/releases/download/{tag}/{name}"
    if asset.get("browser_download_url") != expected:
        raise ValueError("macOS asset must use the exact selected GitHub release URL")
    digest = asset.get("digest", "")
    if re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        digest_hash = "sha256-" + base64.b64encode(bytes.fromhex(digest[7:])).decode()
    else:
        digest_hash = prefetch(asset["browser_download_url"], unpack=False)["hash"]
    return asset["browser_download_url"], digest_hash


def main(argv: list[str] | None = None) -> int:  # ruff: ignore[too-many-locals]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="select a stable release tag")
    parser.add_argument(
        "--dry-run", action="store_true", help="preview without editing"
    )
    args = parser.parse_args(argv)
    source_path = PACKAGE / "source.nix"
    source = source_path.read_text()
    tag, data = release(args.version)
    current = field(source, "version")
    if tag == current:
        print(f"Moonfin {tag} is current")
        return 0

    revision = tag_commit(tag)
    fetched = prefetch(f"https://github.com/{REPO}/archive/{revision}.tar.gz")
    # Nixpkgs' Flutter builder consumes parsed lock data. Keep upstream's
    # committed lock instead of creating a second, independent upgrade.
    try:
        yaml = importlib.import_module("yaml")
    except ImportError as error:
        raise RuntimeError("PyYAML is required; run inside `nix develop`") from error
    lock = yaml.safe_load((Path(fetched["storePath"]) / "pubspec.lock").read_text())
    if (
        not isinstance(lock, dict)
        or not isinstance(lock.get("packages"), dict)
        or not lock["packages"]
    ):
        raise ValueError("upstream Flutter lock is missing or empty")
    check_flutter_sdk(lock)
    hashes = git_hashes(lock)
    url, dmg_hash = asset_hash(data, tag)
    updated = source
    for name, value in (
        ("version", tag),
        ("releaseTag", tag),
        ("sourceRev", revision),
        ("sourceHash", fetched["hash"]),
    ):
        updated = replace(updated, name, value)
    old_url = re.search(r'      url = "([^"]+)";', updated)
    old_hash = re.search(r'      hash = "([^"]+)";', updated)
    if old_url is None or old_hash is None:
        raise ValueError("expected one macOS source URL and hash")
    updated = updated.replace(old_url.group(0), f'      url = "{url}";', 1)
    updated = updated.replace(old_hash.group(0), f'      hash = "{dmg_hash}";', 1)

    lock_json = json.dumps(lock, indent=2, sort_keys=True) + "\n"
    hashes_json = json.dumps(hashes, indent=2, sort_keys=True) + "\n"
    print(f"Moonfin {current} -> {tag} ({revision})")
    print(f"Linux source: {fetched['hash']}\nmacOS asset: {dmg_hash}")
    print(f"Flutter packages: {len(lock['packages'])}; Git dependencies: {len(hashes)}")
    changes = {
        source_path: updated,
        PACKAGE / "pubspec.lock.json": lock_json,
        PACKAGE / "git-hashes.json": hashes_json,
    }
    preview(changes)
    if args.dry_run:
        return 0
    commit_files(changes)
    print("Updated all release pins; build on Linux and macOS before adoption")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        OSError,
        RuntimeError,
        TypeError,
        ValueError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"update failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
