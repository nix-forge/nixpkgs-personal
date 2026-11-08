#!/usr/bin/env python3
"""Refresh Wardrowbe's paired release pins and locked npm cache without npm scripts."""

from __future__ import annotations

import argparse
import base64
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
from update_transaction import commit_files

PACKAGE = Path(__file__).resolve().parent
UPSTREAM = "Anyesh/wardrowbe"
TAG_PATTERN = re.compile(r"wardrowbe-v(\d+)\.(\d+)\.(\d+)")


def command(*args: str, cwd: Path | None = None) -> str:
    result = run_command(
        args, cwd=cwd, check=False, capture_output=True, text=True, timeout=1800
    )
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def api(path: str) -> object:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "wardrowbe-nix-updater",
    }
    if token := os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(
        f"https://api.github.com/repos/{UPSTREAM}/{path}", headers=headers
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def release_version(release: dict) -> tuple[int, ...] | None:
    match = TAG_PATTERN.fullmatch(release.get("tag_name", ""))
    if release.get("draft") or release.get("prerelease") or match is None:
        return None
    return tuple(map(int, match.groups()))


def github_release(tag: str | None) -> dict:
    if tag is not None:
        release = api(f"releases/tags/{urllib.parse.quote(tag, safe='')}")
        if not isinstance(release, dict) or release_version(release) is None:
            raise ValueError("requested tag is not a stable Wardrowbe release")
        return release
    # The Releases API sorts by creation date, not semantic version. Inspect all
    # pages and fail rather than select from a truncated release inventory.
    candidates = []
    page_size = 100
    for page in range(1, 11):
        releases = api(f"releases?per_page={page_size}&page={page}")
        if not isinstance(releases, list):
            raise TypeError("unexpected release response")
        candidates.extend(
            r for r in releases if isinstance(r, dict) and release_version(r)
        )
        if len(releases) < page_size:
            break
    else:
        raise ValueError("release inventory exceeds pagination limit")
    if not candidates:
        raise ValueError("no stable Wardrowbe release found")
    return max(candidates, key=lambda r: release_version(r) or ())


def tag_commit(tag: str) -> str:
    refs = command(
        "git",
        "ls-remote",
        f"https://github.com/{UPSTREAM}.git",
        f"refs/tags/{tag}",
        f"refs/tags/{tag}^{{}}",
    )
    commits = dict(line.split("\t", 1)[::-1] for line in refs.splitlines())
    revision = commits.get(f"refs/tags/{tag}^{{}}") or commits.get(f"refs/tags/{tag}")
    if revision is None or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("release tag does not resolve to a commit")
    return revision


def field(source: str, name: str) -> str:
    matches = re.findall(rf'^  {re.escape(name)} = "([^"]+)";$', source, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"expected one {name} field in source.nix")
    return matches[0]


def sri(value: str) -> str:
    if not re.fullmatch(r"sha256-[A-Za-z0-9+/]{43}=", value):
        raise ValueError(f"invalid SHA256 SRI hash: {value!r}")
    return value


def pypi(name: str, version: str | None = None) -> dict:
    suffix = "" if version is None else f"/{urllib.parse.quote(version, safe='')}"
    request = urllib.request.Request(
        f"https://pypi.org/pypi/{name}{suffix}/json",
        headers={"User-Agent": "wardrowbe-nix-updater"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        result = json.load(response)
    if not isinstance(result, dict):
        raise TypeError("unexpected PyPI response")
    return result


def redis_versions(specifier) -> list:
    parse_sdist_filename = importlib.import_module(
        "packaging.utils"
    ).parse_sdist_filename
    request = urllib.request.Request(
        "https://pypi.org/simple/redis/",
        headers={
            "Accept": "application/vnd.pypi.simple.v1+json",
            "User-Agent": "wardrowbe-nix-updater",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        index = json.load(response)
    versions = []
    for entry in index["files"]:
        filename = entry["filename"]
        if entry.get("yanked") or not filename.endswith((".tar.gz", ".zip")):
            continue
        _name, version = parse_sdist_filename(filename)
        if (
            specifier.contains(version)
            and not version.is_prerelease
            and not version.is_devrelease
        ):
            versions.append(version)
    return versions


def python_source(metadata: dict, allowed_dependencies: set[str]) -> tuple[str, str]:
    version = importlib.import_module("packaging.version").Version(
        metadata["info"]["version"]
    )
    requirement_type = importlib.import_module("packaging.requirements").Requirement
    specifier_type = importlib.import_module("packaging.specifiers").SpecifierSet
    if version.is_prerelease or version.is_devrelease:
        raise ValueError("fallback dependency is not a stable release")
    if not specifier_type(metadata["info"].get("requires_python") or "").contains(
        ".".join(map(str, sys.version_info[:3]))
    ):
        raise ValueError("fallback dependency needs a different Python interpreter")
    for text in metadata["info"].get("requires_dist") or []:
        requirement = requirement_type(text)
        if (
            requirement.marker is None or requirement.marker.evaluate({"extra": ""})
        ) and requirement.name.lower() not in allowed_dependencies:
            raise ValueError(
                f"new fallback dependency requires packaging review: {text}"
            )
    sources = [
        f
        for f in metadata["urls"]
        if f["packagetype"] == "sdist" and not f.get("yanked")
    ]
    if len(sources) != 1:
        raise ValueError("expected exactly one non-yanked Python source archive")
    digest = sources[0]["digests"]["sha256"]
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("invalid Python source digest")
    return str(version), "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode()


def fallback_sources() -> dict[str, str]:
    sqlalchemy_version, sqlalchemy_hash = python_source(
        pypi("sqlalchemy"), {"typing-extensions", "greenlet"}
    )
    cython_version, cython_hash = python_source(pypi("cython"), set())
    certifi_source = python_source(pypi("certifi"), set())
    requirement_type = importlib.import_module("packaging.requirements").Requirement
    arq = pypi("arq")
    arq_version, arq_hash = python_source(arq, {"redis", "click"})
    requirements = [requirement_type(text) for text in arq["info"]["requires_dist"]]
    redis_requirements = [r for r in requirements if r.name.lower() == "redis"]
    if len(redis_requirements) != 1:
        raise ValueError(
            "ARQ must declare exactly one Redis requirement; packaging review required"
        )
    redis_requirement = redis_requirements[0]
    candidates = redis_versions(redis_requirement.specifier)
    if not candidates:
        raise ValueError("no stable Redis source satisfies ARQ's dependency constraint")
    redis_version, redis_hash = python_source(
        pypi("redis", str(max(candidates))), {"pyjwt", "async-timeout"}
    )
    return {
        "certifiVersion": certifi_source[0],
        "certifiHash": certifi_source[1],
        "cythonVersion": cython_version,
        "cythonHash": cython_hash,
        "arqVersion": arq_version,
        "arqHash": arq_hash,
        "redisVersion": redis_version,
        "redisHash": redis_hash,
        "sqlalchemyVersion": sqlalchemy_version,
        "sqlalchemyHash": sqlalchemy_hash,
    }


def render(
    version: str,
    revision: str,
    source_hash: str,
    npm_hash: str,
    fallbacks: dict[str, str],
) -> str:
    return (
        "{\n"
        f'  version = "{version}";\n'
        f'  rev = "{revision}";\n'
        f'  hash = "{sri(source_hash)}";\n'
        f'  npmDepsHash = "{sri(npm_hash)}";\n'
        + "".join(
            f'  {name} = "{value}";\n' for name, value in sorted(fallbacks.items())
        )
        + "}\n"
    )


def packages(package: Path) -> list[Path]:
    result = [package]
    # Both recipes remain independently copyable. In the repository, either
    # updater refreshes the pair; the second scheduled invocation is a no-op.
    for name in ("wardrowbe-backend", "wardrowbe-frontend"):
        sibling = package.with_name(name)
        if sibling != package and (sibling / "source.nix").is_file():
            result.append(sibling)
    return result


def validate_source(root: Path, targets: list[Path]) -> None:
    for name in (
        "LICENSE",
        "backend/requirements.txt",
        "backend/app/main.py",
        "backend/migrations/env.py",
        "frontend/package.json",
        "frontend/package-lock.json",
    ):
        if not (root / name).is_file():
            raise ValueError(f"release lacks required file: {name}")
    package = json.loads((root / "frontend/package.json").read_text())
    lock = json.loads((root / "frontend/package-lock.json").read_text())
    if lock.get("name") != package.get("name") or not lock.get("packages"):
        raise ValueError("frontend lockfile does not describe the application")
    # Upstream's package.json version is not its release version.
    if package.get("scripts", {}).get("build") != "next build":
        raise ValueError("frontend build command changed; packaging review required")
    # Check the complete patch stack in derivation order. Later application
    # features can depend on earlier provider patches; independent pristine
    # checks would miss conflicts between patches or reject valid dependencies.
    for target in targets:
        with tempfile.TemporaryDirectory(prefix="wardrowbe-patch-check-") as temporary:
            patched = Path(temporary) / "source"
            shutil.copytree(root, patched, symlinks=True)
            # Prefetched Nix sources have read-only modes. Only this disposable
            # copy becomes writable; retain symlinks without following them.
            for directory, _, files in os.walk(patched, followlinks=False):
                path = Path(directory)
                path.chmod(path.stat().st_mode | 0o700)
                for name in files:
                    path = Path(directory) / name
                    if not path.is_symlink():
                        path.chmod(path.stat().st_mode | 0o600)
            patch_root = (
                patched / "frontend" if target.name == "wardrowbe-frontend" else patched
            )
            for patch in package_patches(target):
                command("git", "apply", "--check", str(patch), cwd=patch_root)
                command("git", "apply", str(patch), cwd=patch_root)


def package_patches(target: Path) -> list[Path]:
    """Read the recipe's explicit local patch list.

    Returns:
        Local patch paths in the exact order used by the derivation.

    Raises:
        ValueError: The list has unsupported syntax, missing files or undeclared patches.

    """
    recipe = (target / "package.nix").read_text()
    recipe = re.sub(r"#[^\n]*", "", recipe)
    match = re.search(r"\bpatches\s*=\s*\[(.*?)\];", recipe, re.DOTALL)
    if match is None:
        raise ValueError("Wardrowbe recipe lacks an explicit patch list")
    entries = match[1].split()
    if any(not re.fullmatch(r"\./[A-Za-z0-9_-]+\.patch", entry) for entry in entries):
        raise ValueError(
            "Wardrowbe patch expression changed; packaging review required"
        )
    patches = [(target / entry.removeprefix("./")).resolve() for entry in entries]
    if len(set(patches)) != len(patches) or any(not path.is_file() for path in patches):
        raise ValueError("Wardrowbe patch list contains duplicates or missing files")
    if set(patches) != {path.resolve() for path in target.glob("*.patch")}:
        raise ValueError("Wardrowbe has undeclared patches; packaging review required")
    return patches


def commit_sources(changes: dict[Path, str]) -> None:
    commit_files(changes)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--version", help="select a stable wardrowbe-vX.Y.Z release tag"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="resolve and preview without editing"
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="regenerate hashes even for the current release",
    )
    parser.add_argument(
        "--paired",
        action="store_true",
        help="refresh both local repository recipes together",
    )
    args = parser.parse_args(argv)
    targets = packages(PACKAGE) if args.paired else [PACKAGE]
    originals = {
        target / "source.nix": (target / "source.nix").read_text() for target in targets
    }
    release = github_release(args.version)
    tag = release["tag_name"]
    version = tag.removeprefix("wardrowbe-v")
    fallbacks = fallback_sources()
    for source in originals.values():
        current = tuple(map(int, field(source, "version").split(".")))
        if (release_version(release) or ()) < current:
            raise ValueError("refusing a release downgrade")
    if (
        not args.refresh
        and len(set(originals.values())) == 1
        and all(
            field(source, "version") == version
            and '  rev = "' in source
            and all(
                f'  {name} = "{value}";' in source for name, value in fallbacks.items()
            )
            for source in originals.values()
        )
    ):
        print(f"Wardrowbe {version} is current")
        return 0
    revision = tag_commit(tag)
    fetched = json.loads(
        command(
            "nix",
            "store",
            "prefetch-file",
            "--json",
            "--unpack",
            f"https://github.com/{UPSTREAM}/archive/{revision}.tar.gz",
        )
    )
    root = Path(fetched["storePath"])
    validate_source(root, targets)
    source_hash = sri(fetched["hash"])
    npm_hash = sri(
        command("prefetch-npm-deps", str(root / "frontend/package-lock.json"))
    )
    updated = render(version, revision, source_hash, npm_hash, fallbacks)
    print(f"Wardrowbe -> {version} ({revision})")
    print(f"source: {source_hash}; npm: {npm_hash}")
    print(
        f"fallbacks: ARQ {fallbacks['arqVersion']}, Redis {fallbacks['redisVersion']}, "
        f"SQLAlchemy {fallbacks['sqlalchemyVersion']}, Cython {fallbacks['cythonVersion']}, "
        f"certifi {fallbacks['certifiVersion']}"
    )
    for path, original in originals.items():
        print(f"{path.parent.name}: {field(original, 'version')} -> {version}")
    if args.dry_run:
        print("Preview only; no files changed")
        return 0
    # Downloads and patch checks finish before either checkout file is changed.
    commit_sources(dict.fromkeys(originals, updated))
    print(
        "Updated paired pins; read-only CI builds and install checks validate the release"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        OSError,
        RuntimeError,
        ValueError,
        TypeError,
        KeyError,
        subprocess.SubprocessError,
    ) as error:
        print(f"update failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
