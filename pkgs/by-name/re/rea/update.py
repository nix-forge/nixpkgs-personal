#!/usr/bin/env python3
"""Refresh matching REA, native PTY and npm-cache pins without lifecycle scripts."""

from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
from pathlib import Path

from notification_process import run as run_command
from provenance import verify_registry_source
from update_support import HTTPS_CONTEXT, github_api_headers
from update_transaction import commit_files, preview

PACKAGE = Path(__file__).resolve().parent
VERSION = re.compile(r"\d+\.\d+\.\d+")
REVISION = re.compile(r"[0-9a-f]{40}")
NODE_VERSION = "24.22.1"
NODE_HASH = "sha256-T1N5eWKAza6wwvNY/QS2oWzE+336g7WoyRqdljtDUjE="
BROTLI_VERSION = "1.2.1"
BROTLI_HASH = "sha256-llY72cYffDv0ugsH0p89xIPEbElV4L8u7U/Fe8hT3gI="
HASH = re.compile(r"sha256-[A-Za-z0-9+/]{43}=")


def command(*arguments: str, cwd: Path | None = None) -> str:
    """Run declared native tools with a deadline and checked exit status.

    Returns:
        The command's stripped stdout.

    """
    return run_command(
        arguments, cwd=cwd, check=True, capture_output=True, text=True, timeout=1800
    ).stdout.strip()


def fetch_json(url: str) -> dict:
    """Read bounded first-party metadata without executing registry code.

    Returns:
        The decoded metadata object.

    Raises:
        TypeError: The response is not a JSON object.

    """
    headers = {"User-Agent": "rea-nix-updater"}
    if urllib.parse.urlsplit(url).netloc == "api.github.com":
        headers = github_api_headers("rea-nix-updater")
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, context=HTTPS_CONTEXT, timeout=30) as response:
        result = json.load(response)
    if not isinstance(result, dict):
        raise TypeError(f"Expected a JSON object from {url}")
    return result


def checked_hash(value: str) -> str:
    """Reject placeholder or malformed fixed-output hashes.

    Returns:
        The validated SHA256 SRI hash.

    Raises:
        ValueError: The hash is malformed or a placeholder.

    """
    if not HASH.fullmatch(value) or value == "sha256-" + "A" * 43 + "=":
        raise ValueError(f"Invalid SHA256 SRI hash: {value}")
    return value


def tag_commit(repository: str, tag: str) -> str:
    """Resolve annotated or lightweight immutable release tags.

    Returns:
        The release's full commit SHA.

    Raises:
        ValueError: The tag does not identify a commit.

    """
    lines = command(
        "git",
        "ls-remote",
        f"https://github.com/{repository}.git",
        f"refs/tags/{tag}",
        f"refs/tags/{tag}^{{}}",
    )
    refs = dict(line.split("\t", 1)[::-1] for line in lines.splitlines())
    revision = refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}", "")
    if not REVISION.fullmatch(revision):
        raise ValueError(f"Release tag {repository}/{tag} does not resolve to a commit")
    return revision


def prefetch(url: str, *, unpack: bool = False) -> dict:
    """Use flat download hashes or recursive hashes matching the recipe's fetcher.

    Returns:
        The fixed-output hash and staged Nix store path.

    """
    arguments = ["nix", "store", "prefetch-file", "--json"]
    if unpack:
        arguments.append("--unpack")
    result = json.loads(command(*arguments, url))
    checked_hash(result["hash"])
    return result


def github_source(repository: str, revision: str) -> dict:
    """Stage immutable source independently of the caller's checkout or flake.

    Returns:
        The unpacked source hash and staged store path.

    """
    return prefetch(
        f"https://github.com/{repository}/archive/{revision}.tar.gz", unpack=True
    )


def native_version(lock: dict) -> str:
    """Find the exact PTY version selected by the application's upstream lock.

    Returns:
        The locked native fork version.

    Raises:
        ValueError: The version is not a stable release.

    """
    version = lock["packages"]["node_modules/@lydell/node-pty"]["version"]
    if not VERSION.fullmatch(version):
        raise ValueError("Native PTY dependency is not a stable version")
    return version


def header_version(source: Path) -> str:
    """Keep the Node-API header version chosen by the native source's Yarn lock.

    Returns:
        The single locked header version.

    Raises:
        ValueError: The header selection is missing or ambiguous.

    """
    matches = re.findall(
        r'^node-addon-api@[^\n]+:\n  version "(\d+\.\d+\.\d+)"$',
        (source / "yarn.lock").read_text(),
        re.MULTILINE,
    )
    if len(matches) != 1:
        raise ValueError(
            "Expected one locked node-addon-api version; review native packaging"
        )
    return matches[0]


def render(application: dict, native: dict, headers: dict) -> str:
    """Render all related pins into the single transactional source file.

    Returns:
        The complete source.nix contents.

    """
    return (
        "{\n"
        f'  version = "{application["version"]}";\n'
        f'  rev = "{application["rev"]}";\n'
        f'  hash = "{checked_hash(application["hash"])}";\n'
        f'  npmDepsHash = "{checked_hash(application["npmDepsHash"])}";\n'
        "  nodejs = {\n"
        f'    version = "{NODE_VERSION}";\n'
        f'    hash = "{checked_hash(NODE_HASH)}";\n'
        "  };\n"
        "  nodePty = {\n"
        f'    version = "{native["version"]}";\n'
        f'    rev = "{native["rev"]}";\n'
        f'    hash = "{checked_hash(native["hash"])}";\n'
        "  };\n"
        "  nodeAddonApi = {\n"
        f'    version = "{headers["version"]}";\n'
        f'    hash = "{checked_hash(headers["hash"])}";\n'
        "  };\n"
        "  brotli = {\n"
        f'    version = "{BROTLI_VERSION}";\n'
        f'    hash = "{checked_hash(BROTLI_HASH)}";\n'
        "  };\n"
        "}\n"
    )


def native_pins(version: str) -> tuple[dict, dict]:
    """Stage the native source and its existing locked header selection.

    Returns:
        The native fork and Node-API header pins.

    Raises:
        ValueError: The fork version disagrees with the locked application dependency.

    """
    revision = tag_commit("lydell/node-pty", f"v{version}")
    native = github_source("lydell/node-pty", revision)
    root = Path(native["storePath"])
    if json.loads((root / "package.json").read_text())["forkVersion"] != version:
        raise ValueError("Native source does not match the locked PTY dependency")
    napi_version = header_version(root)
    headers = prefetch(
        f"https://registry.npmjs.org/node-addon-api/-/node-addon-api-{napi_version}.tgz"
    )
    return {"version": version, "rev": revision, "hash": native["hash"]}, {
        "version": napi_version,
        "hash": headers["hash"],
    }


def check_runtime_requirements(manifest: dict) -> None:
    """Require the reviewed optional provider and a compatible pinned Node.

    Raises:
        ValueError: Optional dependencies or the Node engine range need review.

    """
    optional = manifest.get("optionalDependencies", {})
    if optional not in ({}, {"frida": "17.23.2"}):
        raise ValueError("New optional runtime dependencies require a packaging review")
    # Accept only reviewed simple stable caret/minimum alternatives. Unknown npm
    # range syntax stops an update instead of silently bypassing engines.
    engine = manifest.get("engines", {}).get("node", "")
    alternatives = engine.split(" || ")
    current = tuple(map(int, NODE_VERSION.split(".")))
    compatible = False
    for alternative in alternatives:
        match = re.fullmatch(r"(\^|>=)(\d+)\.(\d+)\.(\d+)", alternative)
        if match is None:
            raise ValueError(
                "Node engine syntax changed; review the pinned Node source"
            )
        operator, *numbers = match.groups()
        minimum = tuple(map(int, numbers))
        if operator == ">=":
            compatible |= current >= minimum
        elif minimum[0] > 0:
            compatible |= minimum <= current < (minimum[0] + 1, 0, 0)
        elif minimum[1] > 0:
            compatible |= minimum <= current < (0, minimum[1] + 1, 0)
        else:
            compatible |= minimum <= current < (0, 0, minimum[2] + 1)
    if not compatible:
        raise ValueError(
            "Release Node engine is incompatible with the pinned Node source"
        )


def candidate(version: str | None) -> str:
    """Validate release identity and stage every input before offering new pins.

    Returns:
        A complete validated candidate source.nix.

    Raises:
        ValueError: Release identities disagree or runtime dependencies need review.

    """
    metadata = fetch_json(
        "https://registry.npmjs.org/rea-agents/" + (version or "latest")
    )
    version = metadata["version"]
    if not VERSION.fullmatch(version) or metadata["name"] != "rea-agents":
        raise ValueError("Expected a stable rea-agents registry release")
    tag = f"rea-agents-{version}"
    release = fetch_json(
        "https://api.github.com/repos/morluto/rea/releases/tags/"
        + urllib.parse.quote(tag, safe="")
    )
    if (
        release.get("draft")
        or release.get("prerelease")
        or release.get("tag_name") != tag
    ):
        raise ValueError("Expected a public stable GitHub release")
    revision = tag_commit("morluto/rea", tag)
    verify_registry_source(metadata, revision, fetch_json)
    application = github_source("morluto/rea", revision)
    root = Path(application["storePath"])
    manifest = json.loads((root / "package.json").read_text())
    if manifest["version"] != version or manifest["name"] != "rea-agents":
        raise ValueError("Source manifest disagrees with the selected release")
    if manifest.get("license") != "MIT":
        raise ValueError("Release licensing changed; review package metadata")
    if not {"rea", "rea-agents"}.issubset(manifest.get("bin", {})):
        raise ValueError(
            "Release commands changed; review mainProgram and install checks"
        )
    if "evmole" not in manifest.get("dependencies", {}):
        raise ValueError("EVM dependency changed; review bytecode provenance")
    check_runtime_requirements(manifest)
    # The npm cache can be prefetched directly, but the application also needs
    # this patch. Check compatibility before publishing any new pins.
    command(
        "patch",
        "--dry-run",
        "--fuzz=0",
        "-p1",
        "-i",
        str(PACKAGE / "prebuilt-darwin-helpers.patch"),
        cwd=root,
    )
    lock = json.loads((root / "package-lock.json").read_text())
    native, headers = native_pins(native_version(lock))
    return render(
        {
            "version": version,
            "rev": revision,
            "hash": application["hash"],
            "npmDepsHash": command(
                "prefetch-npm-deps", str(root / "package-lock.json")
            ),
        },
        native,
        headers,
    )


def main() -> None:
    """Preview a complete update or publish it with rollback on write failure."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="select an explicit stable release")
    parser.add_argument(
        "--check", action="store_true", help="preview changes without writing"
    )
    arguments = parser.parse_args()
    if arguments.version and not VERSION.fullmatch(arguments.version):
        parser.error("--version must be a stable MAJOR.MINOR.PATCH version")
    updated = candidate(arguments.version)
    changes = {PACKAGE / "source.nix": updated}
    preview(changes)
    if not arguments.check:
        commit_files(changes)


if __name__ == "__main__":
    main()
