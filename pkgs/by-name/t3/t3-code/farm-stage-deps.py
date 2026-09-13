#!/usr/bin/env python3
"""Stage the installed pnpm runtime graph without re-resolving or downloading it.

Keep pnpm's isolated layout: a package's identity includes its peer context,
not just its version. Relative links preserve that context and allow cycles.
The staged lock metadata lets electron-builder's pnpm collector enumerate the
same closure. Package contents come from the patched workspace installation.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from collections import deque
from pathlib import Path
from typing import TYPE_CHECKING

import yaml

if TYPE_CHECKING:
    from collections.abc import Sequence

IMPORTERS = ("apps/desktop", "apps/server", ".")


def read_yaml(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise TypeError(f"expected a YAML object in {path}")
    return data


def manifest(path: Path) -> dict:
    return json.loads((path / "package.json").read_text(encoding="utf-8"))


def compatible(package: dict) -> bool:
    for field, host in {"os": "linux", "cpu": "x64", "libc": "glibc"}.items():
        entries = package.get(field, [])
        if isinstance(entries, str):
            entries = [entries]
        positive = [value for value in entries if not value.startswith("!")]
        if f"!{host}" in entries or (positive and host not in positive):
            return False
    return True


def base_version(reference: str) -> str:
    return reference.split("(", 1)[0]


def snapshot_key(name: str, reference: str) -> str:
    # pnpm writes aliases as actual-name@version rather than just version.
    return f"{name}@{reference}" if re.match(r"^\d", reference) else reference


def seed(source: Path, lock: dict, name: str, spec: str) -> tuple[Path, str]:
    candidates: list[tuple[Path, str]] = []
    for importer in IMPORTERS:
        data = lock["importers"].get(importer, {})
        for section in ("dependencies", "optionalDependencies", "devDependencies"):
            record = data.get(section, {}).get(name)
            if not isinstance(record, dict):
                continue
            reference = str(record["version"])
            if spec not in {str(record["specifier"]), base_version(reference)}:
                continue
            path = source / importer / "node_modules" / name
            if path.is_dir() and compatible(manifest(path)):
                candidates.append((path.resolve(), reference))
    if candidates:
        # Desktop dependencies override server dependencies in the staged
        # manifest, so use the same importer precedence as upstream.
        return candidates[0]
    keys = [
        key
        for key in lock["snapshots"]
        if key == f"{name}@{spec}" or key.startswith(f"{name}@{spec}(")
    ]
    if len(keys) != 1:
        raise ValueError(f"cannot unambiguously resolve staged {name}@{spec}")
    reference = keys[0][len(name) + 1 :]
    store = source / "node_modules/.pnpm"
    paths = []
    for context in store.iterdir():
        path = context / "node_modules" / name
        if (
            path.is_dir()
            and manifest(path).get("version") == base_version(reference)
            and compatible(manifest(path))
        ):
            paths.append(path.resolve())
    if len(set(paths)) != 1:
        raise ValueError(f"no unique installed copy of staged {name}@{spec}")
    return paths[0], reference


def link(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.symlink_to(os.path.relpath(source, destination.parent))


def stage(source: Path, target: Path, lockfile: Path) -> int:
    lock = read_yaml(lockfile)
    staged = manifest(target)
    modules = target / "node_modules"
    if modules.exists():
        raise ValueError(f"refusing to overwrite {modules}")
    modules.mkdir()
    installed_store = (source / "node_modules/.pnpm").resolve()
    importer: dict = {}
    pending: deque[tuple[Path, str, str]] = deque()
    copied: dict[Path, Path] = {}

    def materialize(installed: Path, name: str, reference: str) -> Path:
        installed = installed.resolve(strict=True)
        expected = base_version(reference).rsplit("@", 1)[-1]
        if manifest(installed).get("version") != expected:
            raise ValueError(f"installed version differs from {name}@{reference}")
        if installed in copied:
            return copied[installed]
        relative = installed.relative_to(installed_store)
        # A virtual store member must be <context>/node_modules/<package>.
        if len(relative.parts) < 3 or relative.parts[1] != "node_modules":
            raise ValueError(f"unexpected pnpm package location: {installed}")
        destination = modules / ".pnpm" / relative
        shutil.copytree(installed, destination, symlinks=False)
        copied[installed] = destination
        pending.append((installed, name, reference))
        return destination

    for section in ("dependencies", "optionalDependencies", "devDependencies"):
        for name, spec in staged.get(section, {}).items():
            key = f"{name}@{spec}"
            # Upstream promotes both GNU and musl fff binaries to direct
            # dependencies. Retain only the compatible optional prebuild.
            if lock["snapshots"].get(key, {}).get("optional") and not compatible(
                lock["packages"].get(key, {})
            ):
                continue
            try:
                installed, reference = seed(source, lock, name, spec)
            except ValueError:
                if section == "optionalDependencies":
                    continue
                raise
            destination = materialize(installed, name, reference)
            link(destination, modules / name)
            importer.setdefault(section, {})[name] = {
                "specifier": spec,
                "version": reference,
            }

    while pending:
        installed, name, reference = pending.popleft()
        key = snapshot_key(name, reference)
        if key not in lock["snapshots"]:
            raise ValueError(f"no resolved snapshot for {key}")
        relative = installed.relative_to(installed_store)
        source_modules = installed_store / relative.parts[0] / "node_modules"
        target_modules = modules / ".pnpm" / relative.parts[0] / "node_modules"
        snapshot = lock["snapshots"][key]
        for section in ("dependencies", "optionalDependencies"):
            for dependency, child_reference in snapshot.get(section, {}).items():
                child = source_modules / dependency
                if not child.is_dir() or not compatible(manifest(child)):
                    if section == "optionalDependencies":
                        continue
                    raise ValueError(f"missing required {dependency} for {key}")
                destination = materialize(child, dependency, str(child_reference))
                dependency_link = target_modules / dependency
                if dependency_link == destination:
                    continue  # A self-reference already has its package directory.
                if dependency_link.is_symlink():
                    if dependency_link.resolve() != destination:
                        raise ValueError(f"conflicting link at {dependency_link}")
                    continue
                link(destination, dependency_link)

    lock["importers"] = {".": importer}
    serialized = yaml.safe_dump(lock, sort_keys=False)
    (target / "pnpm-lock.yaml").write_text(serialized, encoding="utf-8")
    (modules / ".pnpm/lock.yaml").write_text(serialized, encoding="utf-8")
    settings = read_yaml(source / "node_modules/.modules.yaml")
    settings.update({"virtualStoreDir": ".pnpm", "hoistedDependencies": {}})
    (modules / ".modules.yaml").write_text(
        yaml.safe_dump(settings, sort_keys=False), encoding="utf-8"
    )
    return len(copied)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--lockfile", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        count = stage(args.source_root, args.stage, args.lockfile)
    except (OSError, ValueError, KeyError, yaml.YAMLError) as exc:
        sys.stderr.write(f"error: {exc}\n")
        return 1
    print(f"[farm] materialized {count} package contexts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
