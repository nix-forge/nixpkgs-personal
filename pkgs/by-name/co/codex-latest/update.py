"""Refresh the stable Codex source, Cargo mirror and matching V8 artifacts together."""

from __future__ import annotations

import argparse
import copy
import hashlib
import os
import re
import tempfile
import tomllib
from pathlib import Path
from urllib.error import URLError

from notification_process import run
from release_support import (
    FAKE_HASH,
    json_metadata,
    load_pins,
    metadata,
    prefetch,
    publish,
    reject_downgrade,
    render,
    sri,
    validate_sri,
)

API = "https://api.github.com/repos/openai/codex"
CRATES_IO = "registry+https://github.com/rust-lang/crates.io-index"
V8_FORK = "https://github.com/seanh-oai/rusty_v8.git"
V8_PROFILE = "ptrcomp_sandbox_release"
MAX_CHECKSUM_BYTES = 4096
TARGETS = {
    "x86_64-linux": "x86_64-unknown-linux-gnu",
    "aarch64-linux": "aarch64-unknown-linux-gnu",
    "aarch64-darwin": "aarch64-apple-darwin",
}


def release_identity(release: dict) -> tuple[str, str]:
    tag = release["tag_name"]
    match = re.fullmatch(r"rust-v([0-9]+\.[0-9]+\.[0-9]+)", tag)
    if (
        match is None
        or release.get("draft") is not False
        or release.get("prerelease") is not False
    ):
        raise ValueError("Expected a published stable Codex release")
    return tag, match[1]


def v8_identity(lock: bytes) -> dict:
    """Accept the registry crate or the reviewed fork at a full immutable commit.

    Returns:
        The locked runtime version, dependency source, and artifact profile.

    Raises:
        ValueError: The dependency is ambiguous or outside the reviewed sources.

    """
    entries = [
        package
        for package in tomllib.loads(lock.decode("utf-8"))["package"]
        if package["name"] == "v8"
    ]
    if len(entries) != 1:
        raise ValueError("Expected exactly one V8 dependency in the selected release")
    version = entries[0]["version"]
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Unsupported V8 dependency version")
    source = entries[0].get("source", "")
    profile = "release"
    if source != CRATES_IO:
        match = re.fullmatch(
            re.escape(f"git+{V8_FORK}?rev=") + r"([0-9a-f]{40})#([0-9a-f]{40})",
            source,
        )
        if match is None or match[1] != match[2]:
            raise ValueError("Unsupported registry or immutable fork V8 dependency")
        profile = V8_PROFILE
    return {
        "version": version,
        "dependencySource": source,
        "artifactProfile": profile,
    }


def v8_version(lock: bytes) -> str:
    return v8_identity(lock)["version"]


def checksum_entries(contents: bytes) -> dict[str, str]:
    """Parse exact names and reject ambiguous or malformed checksum manifests.

    Returns:
        Artifact filenames mapped to hexadecimal SHA256 digests.

    Raises:
        ValueError: The manifest is empty, malformed, or contains duplicate names.

    """
    entries = {}
    for line in contents.decode("ascii").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
        if match is None or match[2] in entries:
            raise ValueError("Malformed or duplicate V8 checksum manifest entry")
        entries[match[2]] = match[1]
    if not entries:
        raise ValueError("Empty V8 checksum manifest")
    return entries


def fork_manifest(revision: str, runtime: dict) -> dict[str, str]:
    """Bind the reviewed artifact ABI to the immutable release source and lock.

    Returns:
        Source-trusted hashes of the target checksum manifests.

    Raises:
        ValueError: The source patch or sandbox feature disagrees with the lock.

    """
    base = f"https://raw.githubusercontent.com/openai/codex/{revision}"
    manifest = tomllib.loads(metadata(f"{base}/codex-rs/Cargo.toml").decode("utf-8"))
    fork_revision = runtime["dependencySource"].rsplit("#", 1)[1]
    if manifest.get("patch", {}).get("crates-io", {}).get("v8") != {
        "git": V8_FORK,
        "rev": fork_revision,
    } or manifest.get("workspace", {}).get("dependencies", {}).get("v8") != (
        "=" + runtime["version"]
    ):
        raise ValueError("V8 fork manifest disagrees with the immutable lock")
    consumer = tomllib.loads(
        metadata(f"{base}/codex-rs/code-mode-runtime/Cargo.toml").decode("utf-8")
    )
    dependency = consumer.get("dependencies", {}).get("v8", {})
    if dependency.get("workspace") is not True or dependency.get("features") != [
        "v8_enable_sandbox"
    ]:
        raise ValueError("V8 sandbox feature changed; review artifact compatibility")
    version = runtime["version"].replace(".", "_")
    return checksum_entries(
        metadata(f"{base}/third_party/v8/rusty_v8_{version}_release_manifests.sha256")
    )


def runtime_sources(revision: str, runtime: dict) -> dict:
    """Verify every fork checksum file against source, then verify artifact bytes.

    Returns:
        Verified archive and binding pins for every supported target.

    Raises:
        ValueError: A checksum manifest or artifact fails its source-bound checks.

    """
    version = runtime["version"]
    profile = runtime["artifactProfile"]
    if profile == V8_PROFILE:
        base = f"https://github.com/openai/codex/releases/download/rusty-v8-v{version}"
        trusted = fork_manifest(revision, runtime)
    else:
        base = f"https://github.com/denoland/rusty_v8/releases/download/v{version}"
        trusted = {}
    sources = {}
    for system, target in sorted(TARGETS.items()):
        names = {
            "archive": f"librusty_v8_{profile}_{target}.a.gz",
            "binding": f"src_binding_{profile}_{target}.rs",
        }
        checksums = {}
        if profile == V8_PROFILE:
            filename = f"rusty_v8_{profile}_{target}.sha256"
            expected = trusted.get(filename)
            if expected is None:
                raise ValueError(f"Missing trusted V8 checksum manifest: {filename}")
            manifest_hash, path = prefetch(f"{base}/{filename}")
            if manifest_hash != sri(expected):
                raise ValueError(
                    "V8 checksum manifest hash disagrees with release source"
                )
            with path.open("rb") as stream:
                contents = stream.read(MAX_CHECKSUM_BYTES + 1)
            if (
                len(contents) > MAX_CHECKSUM_BYTES
                or hashlib.sha256(contents).hexdigest() != expected
            ):
                raise ValueError(
                    "V8 checksum manifest bytes disagree with release source"
                )
            checksums = checksum_entries(contents)
            if set(checksums) != set(names.values()):
                raise ValueError(
                    "V8 checksum manifest must contain exactly the asset pair"
                )
        assets = {}
        for kind, filename in names.items():
            url = f"{base}/{filename}"
            artifact_hash, _ = prefetch(url)
            if profile == V8_PROFILE and artifact_hash != sri(checksums[filename]):
                raise ValueError(
                    "V8 artifact hash disagrees with trusted checksum manifest"
                )
            assets[kind] = {"url": url, "hash": artifact_hash}
        sources[system] = assets
    return sources


def resolve_tag(tag: str) -> str:
    reference = json_metadata(f"{API}/git/ref/tags/{tag}")
    if reference.get("ref") != f"refs/tags/{tag}":
        raise ValueError("GitHub returned an unexpected release tag")
    target = reference["object"]
    # Support lightweight and annotated tags without resolving a same-named branch.
    for _ in range(4):
        revision = target["sha"]
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("Invalid release commit or tag object")
        if target["type"] == "commit":
            return revision
        if target["type"] != "tag":
            raise ValueError("Release tag does not point to a commit")
        target = json_metadata(f"{API}/git/tags/{revision}")["object"]
    raise ValueError("Release tag annotation chain is too deep")


def cargo_hash(pins: dict) -> str:
    scope = os.environ.get("NIXPKGS_UPDATE_SOURCE")
    if scope is None:
        scope = run(
            ["nix-instantiate", "--find-file", "nixpkgs"],
            check=True,
            capture_output=True,
            text=True,
            timeout=30,
        ).stdout.strip()
    if not Path(scope).is_absolute() or not (Path(scope) / "default.nix").is_file():
        raise ValueError(
            "Select an absolute Nixpkgs source with NIXPKGS_UPDATE_SOURCE or NIX_PATH"
        )
    with tempfile.TemporaryDirectory(prefix="codex-candidate-") as temporary:
        candidate = Path(temporary) / "source.nix"
        staged = copy.deepcopy(pins)
        staged["cargoHash"] = FAKE_HASH
        candidate.write_text(render(staged), encoding="utf-8")
        command = [
            "nix",
            "build",
            "--no-link",
            "--file",
            str(Path(__file__).with_name("cargo-deps.nix")),
            "--argstr",
            "nixpkgs",
            scope,
            "--argstr",
            "sourceFile",
            str(candidate),
        ]
        result = run(command, capture_output=True, text=True, timeout=3600)
        matches = re.findall(r"got:\s+(sha256-[A-Za-z0-9+/]{43}=)", result.stderr)
        if result.returncode == 0 or len(matches) != 1:
            raise ValueError(
                "Cargo dependency refresh did not produce one hash mismatch:\n"
                + result.stderr[-4000:]
            )
        digest = validate_sri(matches[0])
        staged["cargoHash"] = digest
        candidate.write_text(render(staged), encoding="utf-8")
        run(command, capture_output=True, text=True, check=True, timeout=3600)
        return digest


def candidate(current: dict, release: dict, revision: str, lock: bytes) -> dict:
    _, version = release_identity(release)
    reject_downgrade(current["version"], version)
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("GitHub did not resolve the release to a full commit")
    runtime = v8_identity(lock)
    if version == current["version"]:
        # Legacy registry pins did not record their source/profile. Never infer
        # a fork identity from a matching crate version alone.
        recorded = {
            "version": current["v8"]["version"],
            "dependencySource": current["v8"].get("dependencySource", CRATES_IO),
            "artifactProfile": current["v8"].get("artifactProfile", "release"),
        }
        if revision != current["rev"] or runtime != recorded:
            raise ValueError(
                "The published Codex release changed identity or dependencies"
            )
        return current
    digest, _ = prefetch(
        f"https://github.com/openai/codex/archive/{revision}.tar.gz", unpack=True
    )
    updated = {
        "version": version,
        "rev": revision,
        "hash": digest,
        "cargoHash": FAKE_HASH,
        "v8": {**runtime, "sources": runtime_sources(revision, runtime)},
    }
    updated["cargoHash"] = cargo_hash(updated)
    return updated


def discover(current: dict) -> dict:
    release = json_metadata(f"{API}/releases/latest")
    tag, _ = release_identity(release)
    revision = resolve_tag(tag)
    lock = metadata(
        f"https://raw.githubusercontent.com/openai/codex/{revision}/codex-rs/Cargo.lock"
    )
    return candidate(current, release, revision, lock)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="prepare dependencies and preview without editing pins",
    )
    arguments = parser.parse_args()
    path = Path(__file__).with_name("source.nix")
    original = path.read_bytes()
    try:
        pins = discover(load_pins(path))
        publish(path, original, pins, dry_run=arguments.dry_run)
    except (ValueError, TypeError, KeyError, OSError, URLError) as error:
        parser.exit(1, f"Codex update failed: {error}\n")


if __name__ == "__main__":
    main()
