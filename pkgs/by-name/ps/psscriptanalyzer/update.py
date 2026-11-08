#!/usr/bin/env python3
"""Prepare a complete PSScriptAnalyzer release update."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

from notification_process import run as run_command
from update_nix import candidate_expression
from update_transaction import commit_files, preview

PACKAGE = Path(__file__).resolve().parent
API = "https://api.github.com/repos/PowerShell/PSScriptAnalyzer/releases/latest"


def run(*argv: str) -> str:
    result = run_command(
        argv, check=False, text=True, capture_output=True, timeout=3600
    )
    if result.returncode:
        raise RuntimeError(f"{' '.join(argv[:2])}: {result.stderr.strip()}")
    return result.stdout.strip()


def latest_version() -> str:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "nix-conf-updater",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        API,
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        release = json.load(response)
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("latest GitHub release is not stable")
    return release["tag_name"]


def tag_commit(tag: str) -> str:
    refs = run(
        "git",
        "ls-remote",
        "https://github.com/PowerShell/PSScriptAnalyzer.git",
        f"refs/tags/{tag}",
        f"refs/tags/{tag}^{{}}",
    ).splitlines()
    commits = dict(line.split("\t", 1)[::-1] for line in refs)
    revision = commits.get(f"refs/tags/{tag}^{{}}") or commits.get(f"refs/tags/{tag}")
    if revision is None or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"cannot resolve release tag {tag}")
    return revision


def source_field(source: str, name: str) -> str:
    matches = re.findall(rf'^  {re.escape(name)} = "([^"]+)";$', source, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"expected one {name} field in source.nix")
    return matches[0]


def replace_field(source: str, name: str, value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9+./=:_-]+", value):
        raise ValueError(f"invalid {name}: {value!r}")
    old = source_field(source, name)
    return source.replace(f'  {name} = "{old}";', f'  {name} = "{value}";', 1)


def prefetch(url: str, *, unpack: bool = False) -> str:
    argv = ["nix", "store", "prefetch-file", "--json"]
    if unpack:
        argv.append("--unpack")
    result = json.loads(run(*argv, url))
    return result["hash"]


def regenerate_deps(staged: Path) -> None:
    expression = candidate_expression(staged, "package.nix", "fetch-deps")
    script = run(
        "nix",
        "build",
        "--impure",
        "--no-link",
        "--print-out-paths",
        "--expr",
        expression,
    ).splitlines()[-1]
    run_command([script, str(staged / "deps.json")], check=True, timeout=3600)
    deps = json.loads((staged / "deps.json").read_text())
    if not isinstance(deps, list) or not deps:
        raise ValueError("generated NuGet dependency graph is empty")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="select an upstream release tag")
    parser.add_argument(
        "--dry-run", action="store_true", help="show pins without changing files"
    )
    args = parser.parse_args(argv)

    source = (PACKAGE / "source.nix").read_text()
    version = args.version or latest_version()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError(f"unexpected release tag: {version!r}")
    current = source_field(source, "version")
    if version == current:
        print(f"PSScriptAnalyzer {version} is current")
        return 0

    revision = tag_commit(version)
    source_hash = prefetch(
        f"https://github.com/PowerShell/PSScriptAnalyzer/archive/{revision}.tar.gz",
        unpack=True,
    )
    help_hash = prefetch(
        f"https://www.powershellgallery.com/api/v2/package/PSScriptAnalyzer/{version}"
    )
    updated = replace_field(source, "version", version)
    updated = replace_field(updated, "sourceRev", revision)
    updated = replace_field(updated, "hash", source_hash)
    updated = replace_field(updated, "helpHash", help_hash)
    print(f"PSScriptAnalyzer {current} -> {version}")
    print(f"source: {source_hash}\nGallery help: {help_hash}")

    with tempfile.TemporaryDirectory(prefix="psscriptanalyzer-update-") as temporary:
        staged = Path(temporary) / "package"
        shutil.copytree(PACKAGE, staged)
        (staged / "source.nix").write_text(updated)
        regenerate_deps(staged)
        changes = {
            PACKAGE / "source.nix": updated.encode(),
            PACKAGE / "deps.json": (staged / "deps.json").read_bytes(),
        }
        preview(changes)
        if args.dry_run:
            return 0
        commit_files(changes)
    print("Updated source.nix and deps.json; run the package build and consumer checks")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"update failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
