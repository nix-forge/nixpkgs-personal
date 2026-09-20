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
from pathlib import Path

from font_support import inventory, sha256
from unpack import parse_xml, unpack
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


def package_versions(root: Path) -> list[str]:
    versions = []
    for path in root.rglob("PackageInfo"):
        if path.stat().st_size > 1024 * 1024:
            raise ValueError(f"Installer metadata is too large: {path}")
        package = parse_xml(path.read_bytes(), path)
        version = package.attrib.get("version")
        if version:
            versions.append(version)
    return sorted(set(versions))


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
            versions = package_versions(root)
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


def developer_entries() -> list[dict]:
    return [
        {
            "name": "apple-" + ("new-york" if name == "NY" else name.lower()),
            "kind": "dmg",
            "url": f"https://devimages-cdn.apple.com/design/resources/download/{name}.dmg",
        }
        for name in DEVELOPER
    ]


def inspect_sources(
    entries: list[dict], cache: Path, previous: dict[str, dict], max_workers: int = 4
) -> list[dict]:
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
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
    return sources


def update(cache: Path, old: dict, developers_only: bool = False) -> dict:
    developer = developer_entries()
    developer_names = {entry["name"] for entry in developer}
    previous = {e["url"]: e for e in old.get("sources", [])}
    if developers_only:
        if not old.get("sources"):
            raise ValueError("--developers-only requires an existing sources.json")
        catalog = [
            entry for entry in old["sources"] if entry["name"] not in developer_names
        ]
        sources = catalog + inspect_sources(developer, cache, previous, max_workers=1)
        catalog_url = old.get("catalog", CATALOG)
        catalog_hash = old.get("catalogHash")
        selection = old.get("selection", sorted(DELIVERY))
    else:
        content = fetch(CATALOG)
        catalog_data = plistlib.loads(content)
        catalog_url = CATALOG
        catalog_hash = hashlib.sha256(content).hexdigest()
        catalog = []
        for asset in select_assets(catalog_data):
            if asset["_MeasurementAlgorithm"] != "SHA-1":
                raise ValueError("Unsupported Apple asset measurement algorithm")
            first_name = asset["FontInfo4"][0]["PostScriptFontName"]
            slug = re.sub(r"[^a-z0-9]+", "-", first_name.lower()).strip("-")
            catalog.append({
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
        names = [entry["name"] for entry in catalog + developer]
        if len(names) != len(set(names)):
            raise ValueError("Generated package names collide")
        # Developer DMGs are much larger than catalog ZIPs. Keep their
        # extraction serial so a full refresh does not exhaust TMPDIR.
        sources = inspect_sources(catalog, cache, previous)
        sources += inspect_sources(developer, cache, previous, max_workers=1)
        selection = sorted(DELIVERY)
    result = {
        "schema": 1,
        "catalog": catalog_url,
        "catalogHash": catalog_hash,
        "selection": selection,
        "sources": sorted(sources, key=operator.itemgetter("name")),
    }
    comparable = {k: v for k, v in old.items() if k != "version"}
    result["version"] = (
        old["version"]
        if result == comparable
        else datetime.datetime.now(datetime.UTC).date().isoformat()
    )
    return result


def replace_files(updates: dict[Path, str]) -> None:
    temporary = []
    try:
        for path, content in updates.items():
            target = path.with_name(f".{path.name}.tmp")
            target.write_text(content)
            temporary.append((target, path))
        for target, path in temporary:
            target.replace(path)
    finally:
        for target, _ in temporary:
            target.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--developers-only",
        action="store_true",
        help="refresh mutable developer DMGs without querying the Font8 catalog",
    )
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
    original_data = json.loads(original or "{}")
    result = update(
        args.cache_dir,
        original_data,
        developers_only=args.developers_only,
    )
    updated = (
        original
        if original and original_data == result
        else json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    )
    updates = {args.source_file: updated}
    changes = {
        path: (path.read_text() if path.exists() else "", content)
        for path, content in updates.items()
    }
    changed = {path: pair for path, pair in changes.items() if pair[0] != pair[1]}
    if not changed:
        print("Apple font sources are up to date")
        return 0
    if args.check or args.dry_run:
        for path, (before, after) in changed.items():
            sys.stdout.writelines(
                difflib.unified_diff(
                    before.splitlines(True),
                    after.splitlines(True),
                    fromfile=str(path),
                    tofile=str(path),
                )
            )
        return int(args.check)
    replace_files({path: after for path, (_, after) in changed.items()})
    for path in changed:
        print(f"Updated {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
