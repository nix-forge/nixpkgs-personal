#!/usr/bin/env python3
"""Run local package update scripts in ``pkgs/by-name/*/*/update.py``."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING
from urllib.parse import quote

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
        "--list-json",
        action="store_true",
        help="print discovered package names as a JSON array without running updates",
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


def _nix_quote(value: Path | str) -> str:
    return json.dumps(str(value), ensure_ascii=False).replace("${", r"\${")


def _flake_reference(repo_root: Path) -> str:
    root = repo_root.resolve()
    if (root / ".git").exists():
        # A path flake can copy Git's sockets and other private metadata.
        # Git sources include tracked working files and omit the .git directory.
        return "git+file://" + quote(str(root), safe="/")
    return str(root)


def _run_updater(
    repo_root: Path,
    updater: _PackageUpdater,
    child_args: list[str],
) -> int:
    wrapper = updater.script.with_name("update.nix")
    forwarded = list(child_args)
    if (
        updater.name in {"wardrowbe-backend", "wardrowbe-frontend"}
        and "--paired" not in forwarded
    ):
        forwarded.insert(0, "--paired")
    if wrapper.is_file():
        expression = (
            f"let source = (builtins.getFlake {_nix_quote(_flake_reference(repo_root))}).inputs.nixpkgs; "
            f"pkgs = import source {{}}; in "
            f"{{ updater = pkgs.callPackage (builtins.toPath {_nix_quote(wrapper.resolve())}) {{}}; }}"
        )
        cmd = [
            "nix",
            "run",
            "--impure",
            "--no-update-lock-file",
            "--option",
            "allow-import-from-derivation",
            "false",
            "--expr",
            expression,
            "updater",
            "--",
            "--package-dir",
            str(updater.script.parent),
            *forwarded,
        ]
    else:
        cmd = [sys.executable, str(updater.script), *forwarded]
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
    # Discovery runs before the workflow installs native updater dependencies.
    from notification_process import run as run_command  # ruff: ignore[import-outside-top-level] - Discovery uses only the standard library.

    status = run_command(
        ["git", "status", "--porcelain=v1", "-z", "--untracked-files=all"],
        cwd=repo_root,
        capture_output=True,
        check=True,
        timeout=30,
    ).stdout
    names = run_command(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=repo_root,
        capture_output=True,
        check=True,
        timeout=30,
    ).stdout
    digest = hashlib.sha256(status)
    for name in sorted(set(names.split(b"\0")) - {b""}):
        path = repo_root / os.fsdecode(name)
        digest.update(name + b"\0")
        try:
            metadata = path.lstat()
        except FileNotFoundError:
            digest.update(b"deleted\0")
            continue
        digest.update(str(metadata.st_mode).encode() + b"\0")
        if stat.S_ISLNK(metadata.st_mode):
            digest.update(os.fsencode(path.readlink()) + b"\0")
        elif stat.S_ISREG(metadata.st_mode):
            with path.open("rb") as stream:
                digest.update(hashlib.file_digest(stream, "sha256").digest())
    return digest.digest()


def _list_updaters(
    updaters: dict[str, _PackageUpdater],
    args: argparse.Namespace,
    child_args: list[str],
) -> int:
    if args.all or child_args or args.keep_going or args.allow_partial:
        raise SystemExit("error: --list-json cannot be combined with update options")
    targets = _select_targets(updaters, run_all=False, package_names=args.package)
    _stdout(json.dumps([updater.name for updater in targets]))
    return 0


def _main(argv: Sequence[str] | None = None) -> int:
    repo_root = Path(__file__).resolve().parent.parent
    args, child_args = _parse_args(argv if argv is not None else sys.argv[1:])

    updaters = _discover_updaters(repo_root)
    if args.list_json:
        return _list_updaters(updaters, args, child_args)
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
