#!/usr/bin/env python3
"""Update the selected Parakeet GGUF from verified immutable Hugging Face content."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import difflib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen


def nix(*args: str) -> str:
    executable = shutil.which("nix")
    if executable is None:
        raise ValueError("Nix must be available; use the package's update.nix wrapper")
    result = subprocess.run(
        [executable, *args], check=True, capture_output=True, text=True
    )
    return result.stdout


def read_source(path: Path) -> dict:
    pins = json.loads(nix("eval", "--json", "--file", str(path)))
    required = {"version", "repo", "filename", "rev", "hash", "size"}
    if not isinstance(pins, dict) or set(pins) != required:
        raise ValueError("Unexpected source.nix schema; review before updating")
    if not isinstance(pins["repo"], str) or not re.fullmatch(
        r"[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+", pins["repo"]
    ):
        raise ValueError("Invalid Hugging Face repository")
    if not isinstance(pins["filename"], str) or not re.fullmatch(
        r"[A-Za-z0-9][A-Za-z0-9_.-]*\.gguf", pins["filename"]
    ):
        raise ValueError("Model filename must be a single GGUF filename")
    return pins


def latest(pins: dict) -> dict:
    # Resolve the branch once, then use that immutable commit for the download.
    url = (
        f"https://huggingface.co/api/models/{quote(pins['repo'], safe='/')}?blobs=true"
    )
    request = Request(url, headers={"User-Agent": "nixpkgs-personal-model-updater"})
    with urlopen(request, timeout=30) as response:
        document = json.load(response)
    if not isinstance(document, dict) or not isinstance(document.get("siblings"), list):
        raise TypeError("Unexpected Hub model metadata")
    revision = document.get("sha")
    if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Hub did not provide an immutable commit")
    files = [
        entry
        for entry in document.get("siblings", [])
        if isinstance(entry, dict) and entry.get("rfilename") == pins["filename"]
    ]
    if len(files) != 1:
        raise ValueError(
            "Selected model file is absent or ambiguous; refusing a model switch"
        )
    lfs = files[0].get("lfs", {})
    if not isinstance(lfs, dict):
        raise TypeError("Missing LFS metadata for selected weights")
    digest = lfs.get("sha256")
    size = lfs.get("size")
    if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
        raise ValueError("Hub did not provide a SHA-256 for the selected weights")
    if type(size) is not int or size <= 0 or files[0].get("size") != size:
        raise ValueError("Missing or inconsistent model size")
    modified = dt.datetime.fromisoformat(document["lastModified"])
    return pins | {
        "version": f"0-unstable-{modified.date().isoformat()}",
        "rev": revision,
        "hash": "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode("ascii"),
        "size": size,
    }


def verify(pins: dict) -> None:
    # Nix verifies the actual bytes against the Hub's LFS SHA-256. Metadata alone
    # must never become a committed hash for bytes that have not been fetched.
    url = f"https://huggingface.co/{pins['repo']}/resolve/{pins['rev']}/{pins['filename']}"
    result = json.loads(
        nix(
            "store",
            "prefetch-file",
            "--json",
            "--hash-type",
            "sha256",
            "--expected-hash",
            pins["hash"],
            "--connect-timeout",
            "30",
            "--stalled-download-timeout",
            "60",
            url,
        )
    )
    if result["hash"] != pins["hash"]:
        raise ValueError("Fetched bytes do not match Hub metadata")
    payload = Path(result["storePath"])
    if payload.stat().st_size != pins["size"]:
        raise ValueError("Fetched file size does not match Hub metadata")
    with payload.open("rb") as stream:
        header = stream.read(8)
    if header[:4] != b"GGUF" or int.from_bytes(header[4:], "little") not in {2, 3}:
        raise ValueError("Unsupported GGUF header; review engine compatibility")


def render(pins: dict) -> str:
    lines = ["{"]
    for key in ("version", "repo", "filename", "rev", "hash", "size"):
        value = json.dumps(pins[key]).replace("${", r"\${")
        lines.append(f"  {key} = {value};")
    return "\n".join([*lines, "}", ""])


def publish(path: Path, original: str, content: str) -> None:
    if path.is_symlink():
        raise ValueError("Refusing to replace a symlinked source.nix")
    mode = stat.S_IMODE(path.stat().st_mode)
    descriptor, name = tempfile.mkstemp(prefix=".source.nix.update-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(mode)
        if path.read_text(encoding="utf-8") != original:
            raise ValueError(
                "source.nix changed during update; refusing to overwrite it"
            )
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run", action="store_true", help="preview without changing pins"
    )
    parser.add_argument(
        "--check", action="store_true", help="exit 1 if new weights are available"
    )
    parser.add_argument(
        "--refresh", action="store_true", help="verify even unchanged weights"
    )
    args = parser.parse_args()
    source = Path(__file__).resolve().with_name("source.nix")
    if source.is_relative_to("/nix/store"):
        raise ValueError("Use --package-dir with the native updater to edit a checkout")
    original = source.read_text(encoding="utf-8")
    current = read_source(source)
    candidate = latest(current)
    # Model-card-only commits do not need a new model deployment.
    changed = (candidate["hash"], candidate["size"]) != (
        current["hash"],
        current["size"],
    )
    if changed or args.refresh:
        verify(candidate)
    if not changed:
        print("Parakeet Unified EN Q8 weights are already up to date")
        return 0
    content = render(candidate)
    print(
        "".join(
            difflib.unified_diff(
                original.splitlines(keepends=True),
                content.splitlines(keepends=True),
                fromfile=str(source),
                tofile=str(source),
            )
        ),
        end="",
    )
    if args.check:
        return 1
    if not args.dry_run:
        publish(source, original, content)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (
        OSError,
        ValueError,
        KeyError,
        TypeError,
        subprocess.CalledProcessError,
    ) as error:
        print(f"Model update failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
