#!/usr/bin/env python3
"""Pin a versioned Apple emoji Linux conversion after verifying its bytes."""

import argparse
import base64
import hashlib
import json
import re
import tempfile
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen

from font_support import faces
from update_support import HTTPS_CONTEXT

API = "https://api.github.com/repos/samuelngs/apple-emoji-ttf"


def fetch_json(url):
    with urlopen(
        Request(url, headers={"User-Agent": "nixpkgs-personal-font-updater"}),
        context=HTTPS_CONTEXT,
        timeout=30,
    ) as response:
        return json.load(response)


def source_entry(release, revision):
    tag = release["tag_name"]
    if not re.fullmatch(r"[A-Za-z0-9._-]+", tag) or not re.fullmatch(
        r"[0-9a-f]{40}", revision
    ):
        raise ValueError("Unexpected release tag or commit identity")
    assets = [a for a in release["assets"] if a["name"] == "AppleColorEmoji-Linux.ttf"]
    if len(assets) != 1:
        raise ValueError("Expected exactly one Linux font asset")
    asset = assets[0]
    expected_url = f"https://github.com/samuelngs/apple-emoji-ttf/releases/download/{tag}/AppleColorEmoji-Linux.ttf"
    digest = asset.get("digest", "")
    if asset["browser_download_url"] != expected_url or not re.fullmatch(
        r"sha256:[0-9a-f]{64}", digest
    ):
        raise ValueError("Asset is not a versioned download with a published SHA-256")
    hex_hash = digest.split(":")[1]
    return {
        "name": "apple-color-emoji",
        "version": tag.removeprefix("macos-"),
        "kind": "ttf",
        "url": expected_url,
        "hash": "sha256-" + base64.b64encode(bytes.fromhex(hex_hash)).decode(),
        "upstreamRevision": revision,
        "provenance": "Third-party Linux conversion of Apple Color Emoji, distributed by samuelngs/apple-emoji-ttf; not an Apple-hosted download. The font remains proprietary Apple artwork.",
        "files": [
            {"path": "font.ttf", "sha256": hex_hash, "faces": ["AppleColorEmoji"]}
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--version", help="Explicit upstream release tag; default discovers latest"
    )
    parser.add_argument(
        "--manifest", type=Path, default=Path(__file__).with_name("source.json")
    )
    args = parser.parse_args()
    endpoint = (
        "/releases/tags/" + quote(args.version, safe="")
        if args.version
        else "/releases/latest"
    )
    release = fetch_json(API + endpoint)
    revision = fetch_json(API + "/commits/" + quote(release["tag_name"], safe=""))[
        "sha"
    ]
    entry = source_entry(release, revision)
    current = json.loads(args.manifest.read_text())
    # Resolve the immutable asset on every check, including unchanged releases.
    with urlopen(
        Request(entry["url"], method="HEAD"), context=HTTPS_CONTEXT, timeout=30
    ):
        pass
    if entry == current:
        print("Apple emoji source is current and its versioned asset is available")
        return 0
    if args.check or args.dry_run:
        print(json.dumps(entry, indent=2))
        return int(args.check)
    with tempfile.TemporaryDirectory(prefix="apple-emoji-update-") as directory:
        font = Path(directory) / "font.ttf"
        digest = hashlib.sha256()
        with (
            urlopen(entry["url"], context=HTTPS_CONTEXT, timeout=60) as response,
            font.open("wb") as output,
        ):
            while block := response.read(1024 * 1024):
                digest.update(block)
                output.write(block)
        if digest.hexdigest() != entry["files"][0]["sha256"] or faces(font) != [
            "AppleColorEmoji"
        ]:
            raise ValueError(
                "Release bytes or font identity differ from the published asset"
            )
    temporary = args.manifest.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(entry, indent=2) + "\n")
    temporary.replace(args.manifest)
    print(
        "Updated pinned source; run the package and browser checks before accepting it"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
