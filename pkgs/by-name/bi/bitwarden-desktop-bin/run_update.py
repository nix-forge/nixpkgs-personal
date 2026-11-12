"""Locate editable package sources for a Nix-packaged updater."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _editable(directory: Path) -> bool:
    return (
        not directory.resolve().is_relative_to(Path("/nix/store"))
        and (directory / "package.nix").is_file()
        and (directory / "update.py").is_file()
    )


def find_package(name: str, source: Path | None, explicit: Path | None) -> Path:
    """Find the editable package without attempting to update a store copy.

    Returns:
        The package directory in an editable checkout.

    Raises:
        ValueError: An explicit directory is invalid or no editable package is found.

    """
    if explicit is not None:
        if not _editable(explicit):
            raise ValueError(f"Not an editable package directory: {explicit}")
        return explicit.resolve()
    if source is not None and _editable(source):
        return source.resolve()
    # Flakes evaluate source paths in the store. Resolve their by-name recipe in
    # the caller's checkout, including calls from a package or checkout subfolder.
    current = Path.cwd().resolve()
    for root in (current, *current.parents):
        candidates = [root / "pkgs/by-name" / name[:2] / name]
        if root.name == name:
            candidates.insert(0, root)
        for candidate in candidates:
            if _editable(candidate):
                return candidate.resolve()
    raise ValueError(
        "Set UPDATE_NIX_PACKAGE_DIR or pass --package-dir to the editable package"
    )


def main() -> None:
    """Forward updater arguments to its writable source and local helper modules."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--updater-name", required=True)
    parser.add_argument("--source-directory", type=Path)
    parser.add_argument("--package-dir", type=Path)
    args, child_args = parser.parse_known_args()
    explicit = args.package_dir
    if explicit is None and os.environ.get("UPDATE_NIX_PACKAGE_DIR"):
        explicit = Path(os.environ["UPDATE_NIX_PACKAGE_DIR"])
    directory = find_package(args.updater_name, args.source_directory, explicit)
    # Execute the editable Python file so __file__ and sibling imports refer to
    # the candidate checkout, while retaining the declared Python environment.
    os.execv(  # ruff: ignore[start-process-with-no-shell]
        sys.executable, [sys.executable, str(directory / "update.py"), *child_args]
    )


if __name__ == "__main__":
    main()
