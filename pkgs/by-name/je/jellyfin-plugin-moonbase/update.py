#!/usr/bin/env python3
"""Prepare a Moonbase plugin and matching Moonfin Web source update."""

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
PLUGIN = "Moonfin-Client/Plugin"
WEB = "Moonfin-Client/Moonfin-Core"
GITHUB_REPOSITORY_PARTS = 2


class MissingReleaseEntryError(ValueError):
    """The tagged manifest predates its release metadata."""


def command(*args: str) -> str:
    result = run_command(
        args, check=False, capture_output=True, text=True, timeout=3600
    )
    if result.returncode:
        raise RuntimeError(f"{' '.join(args[:2])}: {result.stderr.strip()}")
    return result.stdout.strip()


def github_json(repository: str, path: str) -> dict:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "nix-conf-updater",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/{path}", headers=headers
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        value = json.load(response)
    if not isinstance(value, dict):
        raise TypeError("unexpected GitHub API response")
    return value


def release_tag(version: str | None) -> str:
    path = (
        "releases/latest"
        if version is None
        else f"releases/tags/{urllib.parse.quote(version, safe='')}"
    )
    release = github_json(PLUGIN, path)
    tag = release["tag_name"]
    if (
        release.get("draft")
        or release.get("prerelease")
        or not re.fullmatch(r"\d+\.\d+\.\d+", tag)
    ):
        raise ValueError(f"unsupported plugin release: {tag}")
    return tag


def tag_commit(repository: str, tag: str) -> str:
    refs = command(
        "git",
        "ls-remote",
        f"https://github.com/{repository}.git",
        f"refs/tags/{tag}",
        f"refs/tags/{tag}^{{}}",
    ).splitlines()
    commits = dict(line.split("\t", 1)[::-1] for line in refs)
    revision = commits.get(f"refs/tags/{tag}^{{}}") or commits.get(f"refs/tags/{tag}")
    if revision is None or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"cannot resolve {repository} tag {tag}")
    return revision


def default_branch_commit(repository: str) -> str:
    lines = command(
        "git", "ls-remote", f"https://github.com/{repository}.git", "HEAD"
    ).splitlines()
    if len(lines) != 1:
        raise ValueError(f"cannot resolve {repository} default branch")
    revision, name = lines[0].split("\t", 1)
    if name != "HEAD" or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"invalid {repository} default branch")
    return revision


def prefetch(repository: str, revision: str) -> dict:
    result = json.loads(
        command(
            "nix",
            "store",
            "prefetch-file",
            "--json",
            "--unpack",
            f"https://github.com/{repository}/archive/{revision}.tar.gz",
        )
    )
    if (
        not result.get("hash", "").startswith("sha256-")
        or not Path(result["storePath"]).is_dir()
    ):
        raise ValueError(f"could not prefetch {repository} at {revision}")
    return result


def prefetch_manifest(revision: str) -> dict:
    result = json.loads(
        command(
            "nix",
            "store",
            "prefetch-file",
            "--json",
            f"https://raw.githubusercontent.com/{PLUGIN}/{revision}/Jellyfin/manifest.json",
        )
    )
    if (
        not result.get("hash", "").startswith("sha256-")
        or not Path(result["storePath"]).is_file()
    ):
        raise ValueError(f"could not prefetch Moonbase manifest at {revision}")
    return result


def source_field(source: str, name: str) -> str:
    values = re.findall(rf'^  {re.escape(name)} = "([^"]+)";$', source, re.MULTILINE)
    if len(values) != 1:
        raise ValueError(f"expected one {name} field in source.nix")
    return values[0]


def replace_field(source: str, name: str, value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9+./=:_-]+", value):
        raise ValueError(f"invalid {name}: {value!r}")
    old = source_field(source, name)
    return source.replace(f'  {name} = "{old}";', f'  {name} = "{value}";', 1)


def selected_manifest(
    manifest_file: Path, tag: str, previous_abi: str
) -> tuple[str, str, str]:
    manifest = json.loads(manifest_file.read_text(encoding="utf-8"))
    if (
        not isinstance(manifest, list)
        or len(manifest) != 1
        or not isinstance(manifest[0], dict)
        or not isinstance(manifest[0].get("versions"), list)
    ):
        raise ValueError("unexpected Moonbase manifest shape")
    entries = [
        entry
        for entry in manifest[0]["versions"]
        if f"/releases/download/{tag}/" in entry.get("sourceUrl", "")
    ]
    if not entries:
        raise MissingReleaseEntryError(f"manifest has no entry for release {tag}")
    if len(entries) != 1:
        raise ValueError(f"expected one manifest version for release {tag}")
    entry = entries[0]
    if entry["sourceUrl"] != (
        f"https://github.com/{PLUGIN}/releases/download/{tag}/"
        f"Moonfin.Server-{entry['version']}.zip"
    ):
        raise ValueError("manifest asset does not match selected release")
    abi = entry["targetAbi"]
    if abi != previous_abi:
        raise ValueError(
            f"Jellyfin target ABI changed from {previous_abi} to {abi}; review required"
        )
    matches = set(
        re.findall(
            r"(?:bundled web client|web app|Moonfin Web)[^\n.]{0,100}?Moonfin\s+(\d+\.\d+\.\d+)",
            entry["changelog"],
            re.IGNORECASE,
        )
    )
    if len(matches) != 1:
        raise ValueError("release notes do not identify one Moonfin Web version")
    return entry["version"], abi, matches.pop()


def choose_manifest(
    plugin_rev: str, tag: str, previous_abi: str
) -> tuple[str, dict, tuple[str, str, str]]:
    tagged = prefetch_manifest(plugin_rev)
    tagged_file = Path(tagged["storePath"])
    try:
        return plugin_rev, tagged, selected_manifest(tagged_file, tag, previous_abi)
    except MissingReleaseEntryError as error:
        print(error)
    # Release automation can update the branch manifest after cutting the tag.
    # Resolve the default branch once and pin that exact commit and file hash.
    manifest_rev = default_branch_commit(PLUGIN)
    fallback = prefetch_manifest(manifest_rev)
    tagged_meta = json.loads(tagged_file.read_text(encoding="utf-8"))[0]
    fallback_meta = json.loads(Path(fallback["storePath"]).read_text(encoding="utf-8"))[
        0
    ]
    if not isinstance(fallback_meta, dict):
        raise TypeError("fallback Moonbase manifest has an unexpected shape")
    for field in ("guid", "name", "owner", "category"):
        if not tagged_meta.get(field) or fallback_meta.get(field) != tagged_meta[field]:
            raise ValueError(f"fallback manifest changed plugin identity: {field}")
    selected = selected_manifest(Path(fallback["storePath"]), tag, previous_abi)
    print(f"tagged manifest lacks {tag}; using manifest from commit {manifest_rev}")
    return manifest_rev, fallback, selected


def git_hashes(lock: dict) -> dict[str, str]:
    hashes: dict[str, str] = {}
    cached: dict[tuple[str, str], str] = {}
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
        if key not in cached:
            cached[key] = prefetch(*key)["hash"]
        hashes[name] = cached[key]
    return hashes


def check_flutter_sdk(lock: dict) -> None:
    constraint = lock.get("sdks", {}).get("flutter", "")
    minimum = re.match(r"^>=(\d+)\.(\d+)\.\d+", constraint)
    if minimum is None:
        raise ValueError(f"unsupported Flutter SDK constraint: {constraint!r}")
    required = tuple(map(int, minimum.groups()))
    builders = re.findall(
        r"(?m)^flutter(\d)(\d{2})\.buildFlutterApplication \{$",
        (PACKAGE / "web.nix").read_text(),
    )
    if len(builders) != 1:
        raise ValueError("cannot identify the pinned Flutter builder in web.nix")
    pinned = tuple(map(int, builders[0]))
    if required > pinned:
        raise ValueError(
            f"Flutter SDK {required[0]}.{required[1]} is required; update web.nix builder"
        )


def regenerate_deps(staged: Path) -> None:
    expression = candidate_expression(staged, "server.nix", "fetch-deps")
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


def main(argv: list[str] | None = None) -> int:  # ruff: ignore[too-many-locals]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="select a stable plugin release tag")
    parser.add_argument(
        "--dry-run", action="store_true", help="preview without editing"
    )
    args = parser.parse_args(argv)
    source_path = PACKAGE / "source.nix"
    source = source_path.read_text()
    tag = release_tag(args.version)
    current = source_field(source, "releaseTag")
    if tag == current:
        print(f"Moonbase {tag} is current")
        return 0

    plugin_rev = tag_commit(PLUGIN, tag)
    plugin = prefetch(PLUGIN, plugin_rev)
    manifest_rev, manifest, (version, abi, web_version) = choose_manifest(
        plugin_rev, tag, source_field(source, "targetAbi")
    )
    web_rev = tag_commit(WEB, web_version)
    web = prefetch(WEB, web_rev)
    try:
        yaml = importlib.import_module("yaml")
    except ImportError as error:
        raise RuntimeError("PyYAML is required; run inside `nix develop`") from error
    lock = yaml.safe_load((Path(web["storePath"]) / "pubspec.lock").read_text())
    if (
        not isinstance(lock, dict)
        or not isinstance(lock.get("packages"), dict)
        or not lock["packages"]
    ):
        raise ValueError("upstream Flutter lock is missing or empty")
    check_flutter_sdk(lock)
    hashes = git_hashes(lock)
    updated = source
    for name, value in (
        ("version", version),
        ("releaseTag", tag),
        ("targetAbi", abi),
        ("pluginRev", plugin_rev),
        ("pluginHash", plugin["hash"]),
        ("manifestRev", manifest_rev),
        ("manifestHash", manifest["hash"]),
        ("webVersion", web_version),
        ("webRev", web_rev),
        ("webHash", web["hash"]),
    ):
        updated = replace_field(updated, name, value)

    print(
        f"Moonbase {current} -> {tag}: plugin {version}, web {web_version}, ABI {abi}"
    )
    print(f"plugin: {plugin['hash']}\nweb: {web['hash']}")
    print(f"Flutter packages: {len(lock['packages'])}; Git dependencies: {len(hashes)}")
    with tempfile.TemporaryDirectory(prefix="moonbase-update-") as temporary:
        staged = Path(temporary) / "package"
        shutil.copytree(PACKAGE, staged)
        (staged / "source.nix").write_text(updated)
        (staged / "pubspec.lock.json").write_text(
            json.dumps(lock, indent=2, sort_keys=True) + "\n"
        )
        (staged / "git-hashes.json").write_text(
            json.dumps(hashes, indent=2, sort_keys=True) + "\n"
        )
        regenerate_deps(staged)
        changes = {
            PACKAGE / name: (staged / name).read_bytes()
            for name in (
                "source.nix",
                "pubspec.lock.json",
                "git-hashes.json",
                "deps.json",
            )
        }
        preview(changes)
        if args.dry_run:
            return 0
        commit_files(changes)
    print("Updated all pins; build the combined plugin and test Jellyfin loading")
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
