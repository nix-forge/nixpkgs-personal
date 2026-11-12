#!/usr/bin/env python3
"""Refresh Subtitle Extract source and NuGet pins after manifest checks."""

from __future__ import annotations

import argparse
import importlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

from notification_process import run as run_command
from update_nix import candidate_expression
from update_transaction import commit_files, preview

PACKAGE = Path(__file__).resolve().parent
UPSTREAM = "jellyfin/jellyfin-plugin-subtitleextract"


def command(*args: str) -> str:
    result = run_command(
        args, check=False, capture_output=True, text=True, timeout=3600
    )
    if result.returncode:
        raise RuntimeError(f"{' '.join(args[:2])}: {result.stderr.strip()}")
    return result.stdout.strip()


def github_release(version: str | None) -> dict:
    path = (
        "latest" if version is None else f"tags/{urllib.parse.quote(version, safe='')}"
    )
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "nix-conf-updater",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"https://api.github.com/repos/{UPSTREAM}/releases/{path}", headers=headers
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        release = json.load(response)
    tag = release["tag_name"]
    if (
        release.get("draft")
        or release.get("prerelease")
        or not re.fullmatch(r"v\d+", tag)
    ):
        raise ValueError(f"unsupported release tag: {tag}")
    if not re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ", release["published_at"]):
        raise ValueError("release has no precise publication timestamp")
    return release


def tag_commit(tag: str) -> str:
    refs = command(
        "git",
        "ls-remote",
        f"https://github.com/{UPSTREAM}.git",
        f"refs/tags/{tag}",
        f"refs/tags/{tag}^{{}}",
    ).splitlines()
    commits = dict(line.split("\t", 1)[::-1] for line in refs)
    revision = commits.get(f"refs/tags/{tag}^{{}}") or commits.get(f"refs/tags/{tag}")
    if revision is None or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"cannot resolve release tag {tag}")
    return revision


def prefetch(revision: str) -> dict:
    result = json.loads(
        command(
            "nix",
            "store",
            "prefetch-file",
            "--json",
            "--unpack",
            f"https://github.com/{UPSTREAM}/archive/{revision}.tar.gz",
        )
    )
    if (
        not result.get("hash", "").startswith("sha256-")
        or not Path(result["storePath"]).is_dir()
    ):
        raise ValueError("could not prefetch tagged source")
    return result


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


def manifest_version(root: Path, expected_abi: str) -> str:
    try:
        yaml = importlib.import_module("yaml")
    except ImportError as error:
        raise RuntimeError("PyYAML is required; run inside `nix develop`") from error
    manifest = yaml.safe_load((root / "build.yaml").read_text())
    if manifest["targetAbi"] != expected_abi:
        raise ValueError(
            f"Jellyfin target ABI changed from {expected_abi} to {manifest['targetAbi']}; review required"
        )
    if manifest["framework"] != "net10.0":
        raise ValueError(f"unexpected target framework: {manifest['framework']}")
    if manifest["artifacts"] != ["Jellyfin.Plugin.SubtitleExtract.dll"]:
        raise ValueError("upstream plugin artifact inventory changed")
    version = str(manifest["version"])
    if re.fullmatch(r"\d+", version):
        return f"{version}.0.0.0"
    if re.fullmatch(r"\d+(?:\.\d+){3}", version):
        return version
    raise ValueError(f"unexpected manifest version: {version}")


def regenerate_deps(staged: Path) -> None:
    expression = candidate_expression(staged, "package.nix", "fetch-deps")
    script = command(
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
    parser.add_argument("--version", help="select upstream tag such as v8")
    parser.add_argument(
        "--dry-run", action="store_true", help="preview without editing"
    )
    args = parser.parse_args(argv)
    source_path = PACKAGE / "source.nix"
    source = source_path.read_text()
    release = github_release(args.version)
    tag = release["tag_name"]
    if tag == field(source, "tag"):
        print(f"Subtitle Extract {tag} is current")
        return 0
    revision = tag_commit(tag)
    fetched = prefetch(revision)
    version = manifest_version(Path(fetched["storePath"]), field(source, "targetAbi"))
    if tag != "v" + version.split(".")[0]:
        raise ValueError("release tag and build manifest version disagree")
    updated = source
    for name, value in (
        ("version", version),
        ("tag", tag),
        ("sourceRev", revision),
        ("sourceHash", fetched["hash"]),
        ("releaseTimestamp", release["published_at"]),
    ):
        updated = replace(updated, name, value)
    print(f"Subtitle Extract {field(source, 'version')} -> {version} ({revision})")
    print(f"source: {fetched['hash']}; ABI: {field(source, 'targetAbi')}")
    with tempfile.TemporaryDirectory(prefix="subtitle-extract-update-") as temporary:
        staged = Path(temporary) / "package"
        shutil.copytree(PACKAGE, staged)
        (staged / "source.nix").write_text(updated)
        regenerate_deps(staged)
        changes = {
            source_path: updated.encode(),
            PACKAGE / "deps.json": (staged / "deps.json").read_bytes(),
        }
        preview(changes)
        if args.dry_run:
            return 0
        commit_files(changes)
    print("Updated source and NuGet graph; build and test plugin loading")
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
