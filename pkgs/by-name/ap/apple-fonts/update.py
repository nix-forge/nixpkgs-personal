#!/usr/bin/env python3
"""Pin Apple Font8 assets and developer DMGs; discovery happens only here."""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import datetime
import difflib
import hashlib
import json
import operator
import os
import plistlib
import re
import sys
import tempfile
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

from font_support import inventory, sha256
from unpack import unpack
from update_support import HTTPS_CONTEXT

CATALOG = "https://mesu.apple.com/assets/macos/com_apple_MobileAsset_Font8/com_apple_MobileAsset_Font8.xml"
DEVELOPER = [
    "SF-Pro",
    "SF-Compact",
    "SF-Mono",
    "SF-Arabic",
    "SF-Armenian",
    "SF-Georgian",
    "SF-Hebrew",
    "NY",
]
DELIVERY = {"macOS", "macOS-download", "macOS-autoactivated"}


def fetch(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=120, context=HTTPS_CONTEXT) as response:
        return response.read()


def select_assets(catalog: dict) -> list[dict]:
    candidates = [
        a
        for a in catalog["Assets"]
        if any(
            DELIVERY.intersection(f.get("PlatformDelivery", [])) for f in a["FontInfo4"]
        )
    ]
    candidates.sort(key=lambda a: (-int(a["_MasteredVersion"]), a["__RelativePath"]))
    if not candidates:
        raise ValueError("Catalog has no eligible macOS font assets")
    chosen, seen = [], set()
    revisions = {}
    for asset in candidates:
        names = {f["PostScriptFontName"] for f in asset["FontInfo4"]}
        overlap = names & seen
        if any(revisions[n] == int(asset["_MasteredVersion"]) for n in overlap):
            raise ValueError(f"Ambiguous same-version font assets: {sorted(overlap)}")
        if overlap == names:
            continue
        if overlap:
            raise ValueError(f"Ambiguous partial font replacement: {sorted(overlap)}")
        chosen.append(asset)
        seen.update(names)
        revisions.update(dict.fromkeys(names, int(asset["_MasteredVersion"])))
    return chosen


def inspect_source(entry: dict, cache: Path, previous: dict | None) -> dict:
    key = hashlib.sha256(entry["url"].encode()).hexdigest()
    cached = cache / key
    # Immutable catalog assets may reuse verified cache entries. Mutable DMGs
    # must be requested again, including during --check.
    if not cached.exists() or entry["kind"] == "dmg":
        content = fetch(entry["url"])
        temporary = cached.with_suffix(".tmp")
        temporary.write_bytes(content)
        temporary.replace(cached)
    digest = sha256(cached)
    if "measurement" in entry:
        content = cached.read_bytes()
        if (
            len(content) != entry["size"]
            or hashlib.sha1(content).hexdigest() != entry["measurement"]
        ):
            raise ValueError(f"Apple asset integrity mismatch: {entry['url']}")
    entry["hash"] = "sha256-" + base64.b64encode(bytes.fromhex(digest)).decode()
    # URL-keyed cache entries track current downloads. Keep a content-addressed
    # hard link as well so a later DMG update cannot erase an older source.
    retained = cache / f"{digest}.{entry['kind']}"
    if not retained.exists():
        os.link(cached, retained)
    if previous and all(previous.get(k) == v for k, v in entry.items()):
        return previous
    with tempfile.TemporaryDirectory(prefix="apple-font-inspect-") as directory:
        root = unpack(cached, Path(directory), entry["kind"])
        entry["files"] = inventory(root)
        if entry["kind"] == "dmg":
            versions = sorted({
                ET.parse(p).getroot().attrib["version"]
                for p in root.rglob("PackageInfo")
            })
            if not versions:
                raise ValueError("No developer installer version")
            entry["version"] = "+".join(versions)
        else:
            actual = {n for f in entry["files"] for n in f["faces"]}
            if actual != set(entry["expectedFaces"]):
                raise ValueError(
                    f"Catalog/payload face mismatch: {entry['name']}: {actual ^ set(entry['expectedFaces'])}"
                )
    return entry


def update(cache: Path, old: dict) -> dict:
    content = fetch(CATALOG)
    catalog = plistlib.loads(content)
    catalog_hash = hashlib.sha256(content).hexdigest()
    entries = []
    for asset in select_assets(catalog):
        if asset["_MeasurementAlgorithm"] != "SHA-1":
            raise ValueError("Unsupported Apple asset measurement algorithm")
        first_name = asset["FontInfo4"][0]["PostScriptFontName"]
        slug = re.sub(r"[^a-z0-9]+", "-", first_name.lower()).strip("-")
        entries.append({
            "name": "apple-asset-" + slug,
            "kind": "zip",
            "version": asset["Build"],
            "url": asset["__BaseURL"] + asset["__RelativePath"],
            "size": asset["_DownloadSize"],
            "measurement": asset["_Measurement"].hex(),
            "expectedFaces": sorted(
                f["PostScriptFontName"] for f in asset["FontInfo4"]
            ),
        })
    entries.extend(
        {
            "name": "apple-" + ("new-york" if name == "NY" else name.lower()),
            "kind": "dmg",
            "url": f"https://devimages-cdn.apple.com/design/resources/download/{name}.dmg",
        }
        for name in DEVELOPER
    )
    names = [e["name"] for e in entries]
    if len(names) != len(set(names)):
        raise ValueError("Generated package names collide")
    previous = {e["url"]: e for e in old.get("sources", [])}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = [
            executor.submit(inspect_source, e, cache, previous.get(e["url"]))
            for e in entries
        ]
        sources = []
        for i, future in enumerate(futures):
            sources.append(future.result())
            if i % 25 == 0:
                print(
                    f"Inspected {i + 1}/{len(entries)} font sources",
                    file=sys.stderr,
                    flush=True,
                )
    result = {
        "schema": 1,
        "catalog": CATALOG,
        "catalogHash": catalog_hash,
        "selection": sorted(DELIVERY),
        "sources": sorted(sources, key=operator.itemgetter("name")),
    }
    comparable = {k: v for k, v in old.items() if k != "version"}
    result["version"] = (
        old["version"]
        if result == comparable
        else datetime.datetime.now(datetime.UTC).date().isoformat()
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--source-file", type=Path, default=Path(__file__).with_name("sources.json")
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
        / "apple-font-sources",
    )
    args = parser.parse_args()
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    original = args.source_file.read_text() if args.source_file.exists() else ""
    updated = (
        json.dumps(
            update(args.cache_dir, json.loads(original or "{}")),
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    if original == updated:
        print("Apple font sources are up to date")
        return 0
    if args.check or args.dry_run:
        sys.stdout.writelines(
            difflib.unified_diff(
                original.splitlines(True),
                updated.splitlines(True),
                fromfile=str(args.source_file),
                tofile=str(args.source_file),
            )
        )
        return int(args.check)
    temporary = args.source_file.with_suffix(".json.tmp")
    temporary.write_text(updated)
    temporary.replace(args.source_file)
    print(f"Updated {args.source_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
