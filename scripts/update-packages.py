#!/usr/bin/env python3
"""Run local package update scripts in ``pkgs/by-name/*/*/update.py``."""

from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Sequence


@dataclass(frozen=True)
class _PackageUpdater:
    name: str
    script: Path


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")
    sys.stdout.flush()


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _discover_updaters(repo_root: Path) -> dict[str, _PackageUpdater]:
    pkgs_dir = repo_root / "pkgs"
    if not pkgs_dir.is_dir():
        return {}

    updaters: dict[str, _PackageUpdater] = {}
    package_dirs = sorted(pkgs_dir.glob("by-name/*/*"))

    for package_dir in package_dirs:
        script_path = package_dir / "update.py"
        if script_path.is_file():
            updaters[package_dir.name] = _PackageUpdater(
                name=package_dir.name,
                script=script_path,
            )

    return updaters


def _parse_args(argv: Sequence[str]) -> tuple[argparse.Namespace, list[str]]:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--all",
        action="store_true",
        help="run all discovered updater scripts",
    )
    parser.add_argument(
        "--package",
        action="append",
        default=[],
        metavar="NAME",
        help="run updater script for a specific package (repeatable)",
    )
    parser.add_argument(
        "--keep-going",
        action="store_true",
        help="continue running remaining updates after a failure",
    )
    parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="submit successful updates if failed scripts left the tree unchanged",
    )

    args, child_args = parser.parse_known_args(list(argv))
    if args.allow_partial and not args.keep_going:
        parser.error("--allow-partial requires --keep-going")
    if child_args and child_args[0] == "--":
        child_args = child_args[1:]

    return args, child_args


def _select_targets(
    updaters: dict[str, _PackageUpdater],
    *,
    run_all: bool,
    package_names: list[str],
) -> list[_PackageUpdater]:
    if not updaters:
        _stderr("error: no updater scripts found under pkgs/by-name/*/*/update.py")
        raise SystemExit(1)

    if run_all or not package_names:
        target_names = sorted(updaters)
    else:
        target_names = sorted(set(package_names))

    unknown = [name for name in target_names if name not in updaters]
    if unknown:
        _stderr(f"error: unknown package(s): {', '.join(unknown)}")
        _stderr(f"available packages: {', '.join(sorted(updaters))}")
        raise SystemExit(2)

    return [updaters[name] for name in target_names]


def _run_updater(
    repo_root: Path,
    updater: _PackageUpdater,
    child_args: list[str],
) -> int:
    cmd = [sys.executable, str(updater.script), *child_args]
    _stdout(f"==> Updating {updater.name}")

    completed = subprocess.run(cmd, cwd=repo_root, check=False)
    return completed.returncode


def _print_summary(succeeded: list[str], failed: list[str]) -> None:
    _stdout("Update summary:")
    success_text = ", ".join(succeeded) if succeeded else "none"
    failed_text = ", ".join(failed) if failed else "none"
    _stdout(f"  succeeded ({len(succeeded)}): {success_text}")
    _stdout(f"  failed ({len(failed)}): {failed_text}")


def _working_tree_snapshot(repo_root: Path) -> bytes:
    return subprocess.run(
        ["git", "status", "--porcelain=v1", "--untracked-files=all"],
        cwd=repo_root,
        capture_output=True,
        check=True,
        timeout=30,
    ).stdout


def _main(argv: Sequence[str] | None = None) -> int:
    repo_root = Path(__file__).resolve().parent.parent
    args, child_args = _parse_args(argv if argv is not None else sys.argv[1:])

    updaters = _discover_updaters(repo_root)
    targets = _select_targets(
        updaters,
        run_all=args.all,
        package_names=args.package,
    )

    succeeded: list[str] = []
    failed: list[str] = []
    partial_unsafe = False
    initial_snapshot = _working_tree_snapshot(repo_root) if args.allow_partial else b""

    for updater in targets:
        before = _working_tree_snapshot(repo_root) if args.allow_partial else b""
        exit_code = _run_updater(repo_root, updater, child_args)
        if exit_code == 0:
            succeeded.append(updater.name)
            continue

        failed.append(f"{updater.name} (exit {exit_code})")
        if args.allow_partial and _working_tree_snapshot(repo_root) != before:
            _stderr(f"error: failed updater {updater.name} changed the working tree")
            partial_unsafe = True
            break
        if not args.keep_going:
            break

    _print_summary(succeeded, failed)
    if not failed:
        return 0
    if args.allow_partial and not partial_unsafe:
        if _working_tree_snapshot(repo_root) != initial_snapshot:
            _stdout("Submitting successful updates; failed packages need attention")
            return 0
        _stderr("error: no successful package changes to submit")
    return 1


if __name__ == "__main__":
    raise SystemExit(_main())
