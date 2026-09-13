#!/usr/bin/env python3
"""Materialize a lockfile-less stage's node_modules from the main workspace.

The upstream artifact script stages a lockfile-less workspace and installs it
with plain ``pnpm install``, which needs registry metadata even when every
tarball is already vendored. Instead of resolving anything over the network,
this helper reuses the already installed, already patched main workspace
tree: starting from the stage's dependencies, it repeatedly locates each
required package in the main install, verifies the version, and copies it
(dereferencing symlinks) into a flat stage ``node_modules`` until the
runtime closure is complete. Ranged specifiers resolve through the main
lockfile. Edges through ``optionalDependencies`` (and optional peers) may
be skipped with a warning when the target is uninstallable here: pnpm
itself skips host-incompatible optionals, and workspace overrides remove
others entirely (the Claude SDK platform binaries, which the app never
loads). Anything else missing, ambiguous, or version-skewed fails loudly
instead of silently drifting.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path
from typing import TYPE_CHECKING, NoReturn

if TYPE_CHECKING:
    from collections.abc import Sequence

EXACT_RE: re.Pattern[str] = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$")
SECTION_RE: re.Pattern[str] = re.compile(r"^    (dependencies|optionalDependencies):$")
DEP_RE: re.Pattern[str] = re.compile(r"^      (\S[^:]*):$")
SHORT_DEP_RE: re.Pattern[str] = re.compile(r"^      (\S[^:]*): \S")
SPECIFIER_RE: re.Pattern[str] = re.compile(r"^        specifier: (.*)$")
VERSION_RE: re.Pattern[str] = re.compile(r"^        version: (.*)$")
PEER_SUFFIX_RE: re.Pattern[str] = re.compile(r"\(.*\)$")
SNAPSHOT_KEY_RE: re.Pattern[str] = re.compile(r"^  '?(?=\S)([^':]*?)'?:$")
# Importers that provide the staged closure, in lookup order.
IMPORTER_DIRS: tuple[str, ...] = (
    "apps/desktop/node_modules",
    "apps/server/node_modules",
    "node_modules",
)
# Manifest sections that must be present for a flat runtime tree.
RUNTIME_SECTIONS: tuple[str, ...] = (
    "dependencies",
    "optionalDependencies",
    "peerDependencies",
)


def _fail(message: str) -> NoReturn:
    sys.stderr.write(f"error: {message}\n")
    raise SystemExit(1)


def _strip(value: str) -> str:
    return value.strip().strip("'\"")


def _read_manifest(manifest_path: Path) -> dict:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        _fail(f"cannot parse {manifest_path}: {exc}")
    if not isinstance(manifest, dict):
        _fail(f"{manifest_path} is not a JSON object")
    return manifest


def _read_lockfile(lockfile: Path) -> str:
    try:
        return lockfile.read_text(encoding="utf-8")
    except OSError as exc:
        _fail(f"cannot read {lockfile}: {exc}")


def _locked_versions(text: str) -> dict[tuple[str, str], str]:
    """Map (dependency, specifier) to locked version across the lockfile."""
    exact: dict[tuple[str, str], str] = {}
    section: str | None = None
    dep: str | None = None
    specifier: str | None = None
    for line in text.splitlines():
        section_match = SECTION_RE.match(line)
        if section_match is not None:
            section = section_match.group(1)
            dep = None
            continue
        if re.match(r"^  \S", line) is not None and not line.startswith("    "):
            section = None
            dep = None
            continue
        if section is None:
            continue
        dep_match = DEP_RE.match(line)
        if dep_match is not None:
            dep = _strip(dep_match.group(1))
            specifier = None
            continue
        if dep is None:
            continue
        spec_match = SPECIFIER_RE.match(line)
        if spec_match is not None:
            specifier = _strip(spec_match.group(1))
            continue
        version_match = VERSION_RE.match(line)
        if version_match is not None and specifier is not None:
            version = PEER_SUFFIX_RE.sub("", _strip(version_match.group(1)))
            exact.setdefault((dep, specifier), version)
            specifier = None
    return exact


def _snapshot_versions(text: str) -> dict[str, str]:
    """Map names to their version when the snapshots agree on exactly one."""
    snapshots = text.split("\nsnapshots:", 1)
    if len(snapshots) != 2:
        return {}
    versions: dict[str, set[str]] = {}
    for line in snapshots[1].splitlines():
        key_match = SNAPSHOT_KEY_RE.match(line)
        if key_match is None:
            continue
        key = key_match.group(1)
        name, _, version = key.partition("@")
        if not name:
            name, _, version = version.partition("@")
            name = "@" + name
        version = PEER_SUFFIX_RE.sub("", version)
        if name and version:
            versions.setdefault(name, set()).add(version)
    return {
        name: next(iter(found)) for name, found in versions.items() if len(found) == 1
    }


def _snapshot_graph(text: str) -> dict[str, dict[str, tuple[str, bool]]]:
    """Map snapshot keys to their exact dependencies and optionality."""
    snapshots = text.split("\nsnapshots:", 1)
    if len(snapshots) != 2:
        return {}
    graph: dict[str, dict[str, tuple[str, bool]]] = {}
    key: str | None = None
    section: str | None = None
    for line in snapshots[1].splitlines():
        key_match = SNAPSHOT_KEY_RE.match(line)
        if key_match is not None:
            key = key_match.group(1)
            graph[key] = {}
            section = None
            continue
        if key is None:
            continue
        section_match = SECTION_RE.match(line)
        if section_match is not None:
            section = section_match.group(1)
            continue
        if section is None:
            continue
        dep_match = DEP_RE.match(line)
        if dep_match is None:
            dep_match = SHORT_DEP_RE.match(line)
        if dep_match is None:
            continue
        dep_name = _strip(dep_match.group(1))
        # Short-form entries carry the resolved version; expanded importer
        # entries never appear here.
        version_match = SHORT_DEP_RE.match(line)
        if version_match is None:
            continue
        version = PEER_SUFFIX_RE.sub("", _strip(line.split(":", 1)[1]))
        graph[key][dep_name] = (version, section == "optionalDependencies")
    return graph


def _graph_versions(
    graph: dict[str, dict[str, tuple[str, bool]]], name: str, version: str
) -> dict[str, tuple[str, bool]] | None:
    """Exact dependencies for a merged package, preferring the bare key."""
    bare = f"{name}@{version}"
    if bare in graph:
        return graph[bare]
    prefixed = sorted(key for key in graph if key.startswith((bare + "(", bare + "_")))
    if prefixed:
        return graph[prefixed[0]]
    return None


def _optional_names(text: str) -> set[str]:
    """Collect dependencies only ever referenced as optional in the lockfile."""
    optional: set[str] = set()
    required: set[str] = set()
    section: str | None = None
    for line in text.splitlines():
        section_match = SECTION_RE.match(line)
        if section_match is not None:
            section = section_match.group(1)
            continue
        if re.match(r"^  \S", line) is not None and not line.startswith("    "):
            section = None
            continue
        if section is None:
            continue
        dep_match = DEP_RE.match(line)
        if dep_match is None:
            dep_match = SHORT_DEP_RE.match(line)
        if dep_match is None:
            continue
        name = _strip(dep_match.group(1))
        if section == "optionalDependencies":
            optional.add(name)
        else:
            required.add(name)
    return optional - required


def _resolve_version(
    name: str,
    spec: str,
    locked: dict[tuple[str, str], str],
    snapshots: dict[str, str],
) -> str:
    if EXACT_RE.fullmatch(spec) is not None:
        return spec
    version = locked.get((name, spec))
    if version is not None:
        sys.stdout.write(f"[farm-pin] {name}@{spec} -> {version}\n")
        return version
    version = snapshots.get(name)
    if version is not None:
        sys.stdout.write(f"[farm-pin] {name}@{spec} -> {version} (unique snapshot)\n")
        return version
    _fail(f"cannot resolve {name}@{spec} from the lockfile")


def _manifest_version(directory: Path) -> str | None:
    manifest_path = directory / "package.json"
    if not manifest_path.is_file():
        return None
    manifest = _read_manifest(manifest_path)
    version = manifest.get("version")
    return version if isinstance(version, str) else None


def _host_compatible(directory: Path) -> bool:
    """Mirror pnpm's os/cpu/libc filtering for this x86_64 glibc builder."""
    manifest = _read_manifest(directory / "package.json")
    host = {"os": "linux", "cpu": "x64", "libc": "glibc"}
    for field, value in host.items():
        entries = manifest.get(field)
        if entries is None:
            continue
        if isinstance(entries, str):
            entries = [entries]
        if not isinstance(entries, list):
            continue
        positives = [e for e in entries if isinstance(e, str) and not e.startswith("!")]
        negatives = [e[1:] for e in entries if isinstance(e, str) and e.startswith("!")]
        if positives and value not in positives:
            return False
        if value in negatives:
            return False
    return True


def _locate(source_root: Path, name: str, version: str) -> Path | None:
    """Find the installed directory with the exact version, if present.

    Candidates whose manifests declare another os/cpu/libc are skipped,
    exactly like pnpm skips incompatible optional dependencies.
    """
    candidates: list[Path] = []
    for importer in IMPORTER_DIRS:
        candidate = source_root / importer / name
        candidate_version = candidate.is_dir() and _manifest_version(candidate)
        if candidate_version == version and _host_compatible(candidate):
            candidates.append(candidate)
    if not candidates:
        escaped = name.replace("/", "+")
        wanted = escaped + "@" + version
        for importer in IMPORTER_DIRS:
            store = source_root / importer / ".pnpm"
            if not store.is_dir():
                continue
            for version_dir in sorted(store.iterdir()):
                if not version_dir.is_dir():
                    continue
                # Peer variants append suffixes: "_" in current pnpm, "(" in
                # older layouts.
                if version_dir.name != wanted and not version_dir.name.startswith((
                    wanted + "_",
                    wanted + "(",
                )):
                    continue
                candidate = version_dir / "node_modules" / name
                if (
                    candidate.is_dir()
                    and _manifest_version(candidate) == version
                    and _host_compatible(candidate)
                ):
                    candidates.append(candidate)
    if not candidates:
        return None
    # Same version installed for several importers: prefer the lookup order,
    # which favors the desktop app over the server and the root.
    return candidates[0]


def _copy_self_contained(source: Path, target: Path) -> None:
    """Copy a package without its pnpm link farm.

    Nested ``node_modules`` entries that are symlinks belong to the main
    tree's isolated layout; they resolve through the farmed flat tree
    instead. Real nested directories (vendored content shipped inside the
    tarball) are kept. All other symlinks are dereferenced so nothing
    below the stage points back into the main checkout.
    """
    target.mkdir(parents=True, exist_ok=True)
    for entry in sorted(source.iterdir()):
        destination = target / entry.name
        if entry.name == "node_modules" and entry.is_symlink() and not entry.exists():
            # Dangling links cannot contribute content; real ones are links.
            continue
        if entry.is_symlink():
            if entry.is_dir():
                if entry.name == "node_modules":
                    continue
                shutil.copytree(entry, destination, symlinks=False)
            else:
                shutil.copy2(entry, destination, follow_symlinks=True)
        elif entry.is_dir():
            _copy_self_contained(entry, destination)
        else:
            shutil.copy2(entry, destination)


def _visible_version(parent: Path, name: str, stage_modules: Path) -> str | None:
    """Follow Node's nearest-ancestor lookup, including nested version cycles."""
    for directory in (parent, *parent.parents):
        if directory.name != "node_modules":
            version = _manifest_version(directory / "node_modules" / name)
            if version is not None:
                return version
        if directory == stage_modules.parent:
            break
    return None


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--lockfile", type=Path, required=True)
    return parser.parse_args(list(argv))


def _main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    if not args.source_root.is_dir():
        _fail(f"source root not found: {args.source_root}")
    if not args.lockfile.is_file():
        _fail(f"lockfile not found: {args.lockfile}")
    manifest = _read_manifest(args.stage / "package.json")

    text = _read_lockfile(args.lockfile)
    locked = _locked_versions(text)
    snapshots = _snapshot_versions(text)
    optional = _optional_names(text)
    graph = _snapshot_graph(text)

    wanted: dict[str, str] = {}
    for section in ("dependencies", "devDependencies"):
        dependencies = manifest.get(section)
        if isinstance(dependencies, dict):
            for name, spec in dependencies.items():
                if isinstance(spec, str):
                    wanted.setdefault(name, spec)
    if not wanted:
        _fail(f"{args.stage}/package.json has no dependencies to materialize")

    stage_modules = args.stage / "node_modules"
    stage_modules.mkdir(parents=True, exist_ok=True)
    # (parent directory, name) -> version for every materialized copy.
    # parent None is the stage root; anything else nests below its requester
    # exactly like pnpm's isolated layout when the flat root cannot host a
    # second version.
    merged: dict[tuple[str | None, str], str] = {}
    skipped: set[str] = set()
    required: set[str] = set()
    # Stage entries are required unless the lockfile knows them as
    # optional-only (host-incompatible prebuilds the script lists anyway).
    # The parent of a seed is the stage root itself (None).
    worklist: list[tuple[str, str, bool, Path | None]] = [
        (name, spec, name not in optional, None)
        for name, spec in sorted(wanted.items())
    ]
    graphs: dict[tuple[str, str], dict[str, tuple[str, bool]] | None] = {}
    while worklist:
        name, spec, is_required, parent = worklist.pop(0)
        if is_required:
            required.add(name)
        if name in skipped and name not in required:
            continue
        if name in skipped:
            skipped.remove(name)
        # Versions arrive exact from the snapshot graph or the stage; only
        # manifest-only edges without any snapshot still need range
        # resolution through the lockfile-wide fallbacks.
        version: str | None = None
        if EXACT_RE.fullmatch(spec) is not None:
            version = spec
        if version is None:
            try:
                version = _resolve_version(name, spec, locked, snapshots)
            except SystemExit:
                if name in required:
                    raise
                sys.stdout.write(
                    f"[farm-skip] cannot resolve optional {name}@{spec}; omitting it\n"
                )
                skipped.add(name)
                continue
        parent_key = str(parent) if parent is not None else None
        if parent is None:
            # Seeds always live at the root, like a real install.
            target_base = stage_modules
        else:
            if _visible_version(parent, name, stage_modules) == version:
                continue
            top_version = merged.get((None, name))
            if top_version is None:
                # First occurrence claims the root so the tree stays shared.
                parent_key = None
                target_base = stage_modules
            else:
                sys.stdout.write(
                    f"[farm-nest] {name}@{version} nests below "
                    f"{parent} (root hosts {top_version})\n"
                )
                target_base = parent / "node_modules"
        if (parent_key, name) in merged:
            if merged[parent_key, name] != version:
                _fail(
                    f"version conflict for {name} below {parent_key}: "
                    f"{merged[parent_key, name]} vs {version}"
                )
            continue
        installed = _locate(args.source_root, name, version)
        if installed is None:
            if name in required:
                _fail(f"no installed copy of {name}@{version} in the main tree")
            sys.stdout.write(
                f"[farm-skip] {name}@{version} is not installed "
                "for this host; omitting it from the stage\n"
            )
            skipped.add(name)
            continue
        installed_version = _read_manifest(installed / "package.json").get("version")
        if installed_version != version:
            _fail(
                f"installed {name}@{installed_version} does not match "
                f"the staged {version}; refresh the pnpm mirror"
            )
        target = target_base / name
        if target.exists() or target.is_symlink():
            _fail(f"refusing to overwrite existing {target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        _copy_self_contained(installed, target)
        merged[parent_key, name] = version
        sys.stdout.write(f"[farm] {name}@{version}\n")

        installed_manifest = _read_manifest(target / "package.json")
        peers_meta = installed_manifest.get("peerDependenciesMeta")
        if not isinstance(peers_meta, dict):
            peers_meta = {}
        # The snapshot graph is what pnpm resolved: an edge the snapshot
        # lacks was never installed (workspace override removals, unmet
        # peers), so it is skipped no matter what the tarball manifest
        # declares. Only edges without any snapshot fall back to the
        # manifest specifiers.
        key = (name, version)
        if key not in graphs:
            graphs[key] = _graph_versions(graph, name, version)
        snapshot_deps = graphs[key]
        manifest_edges: dict[str, tuple[str, bool]] = {}
        for section in RUNTIME_SECTIONS:
            dependencies = installed_manifest.get(section)
            if not isinstance(dependencies, dict):
                continue
            for dep_name, dep_spec in dependencies.items():
                if not isinstance(dep_spec, str):
                    continue
                if section == "optionalDependencies":
                    dep_required = False
                elif section == "peerDependencies":
                    meta = peers_meta.get(dep_name)
                    dep_required = not (
                        isinstance(meta, dict) and meta.get("optional") is True
                    )
                else:
                    dep_required = True
                manifest_edges[dep_name] = (dep_spec, dep_required)
        edges: dict[str, tuple[str, bool]] = {}
        if snapshot_deps is not None:
            for dep_name, (dep_version, dep_optional) in snapshot_deps.items():
                manifest_edge = manifest_edges.pop(dep_name, None)
                if manifest_edge is not None:
                    manifest_spec, manifest_required = manifest_edge
                    if (
                        EXACT_RE.fullmatch(manifest_spec) is not None
                        and manifest_spec != dep_version
                    ):
                        _fail(
                            f"version conflict for {dep_name}: "
                            f"{manifest_spec} vs {dep_version}"
                        )
                    dep_required = manifest_required and not dep_optional
                else:
                    dep_required = not dep_optional
                edges[dep_name] = (dep_version, dep_required)
        for dep_name, (dep_spec, dep_required) in manifest_edges.items():
            if snapshot_deps is not None:
                sys.stdout.write(
                    f"[farm-skip] {dep_name}@{dep_spec} is not in the resolved "
                    f"snapshot of {name}@{version}; omitting it\n"
                )
                skipped.add(dep_name)
                # electron-builder's traversal collector reads manifests,
                # without applying pnpm workspace overrides. Keep the staged
                # declaration consistent with the resolved, pruned closure.
                for section in RUNTIME_SECTIONS:
                    dependencies = installed_manifest.get(section)
                    if isinstance(dependencies, dict):
                        dependencies.pop(dep_name, None)
                (target / "package.json").write_text(
                    json.dumps(installed_manifest, indent=2) + "\n", encoding="utf-8"
                )
                continue
            edges[dep_name] = (dep_spec, dep_required)
        for dep_name, (dep_spec, dep_required) in edges.items():
            worklist.append((dep_name, dep_spec, dep_required, target))

    # The upstream stage promotes platform optionals into dependencies. A
    # package deliberately omitted for this host must not remain a required
    # declaration for electron-builder's filesystem traversal.
    for section in ("dependencies", "devDependencies"):
        dependencies = manifest.get(section)
        if isinstance(dependencies, dict):
            for name in list(dependencies):
                if name in skipped and not (stage_modules / name).is_dir():
                    del dependencies[name]
    (args.stage / "package.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )

    if skipped:
        sys.stdout.write(
            f"[farm] skipped {len(skipped)} host-incompatible optional(s)\n"
        )
    sys.stdout.write(f"[farm] materialized {len(merged)} package copies\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
