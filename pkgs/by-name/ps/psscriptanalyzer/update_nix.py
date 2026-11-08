"""Build updater expressions against the caller's selected Nixpkgs scope."""

from __future__ import annotations

import json
import os
from pathlib import Path


def nix_string(value: str) -> str:
    """Quote a literal string without introducing Nix interpolation.

    Returns:
        A Nix double-quoted string literal.

    """
    return json.dumps(value, ensure_ascii=False).replace("${", r"\${")


def package_scope(*, system: str | None = None) -> str:
    """Use the native updater's Nixpkgs pin, with NIX_PATH for direct Python calls.

    Returns:
        An expression importing the selected Nixpkgs source.

    Raises:
        ValueError: An explicitly selected source is not an absolute Nixpkgs directory.

    """
    selected = os.environ.get("NIXPKGS_UPDATE_SOURCE")
    if selected:
        source = Path(selected)
        if not source.is_absolute() or not (source / "default.nix").is_file():
            raise ValueError(
                "NIXPKGS_UPDATE_SOURCE must name an absolute Nixpkgs source directory"
            )
        expression = f"(builtins.toPath {nix_string(str(source))})"
    else:
        expression = "<nixpkgs>"
    arguments = "{}" if system is None else f"{{ system = {nix_string(system)}; }}"
    return f"import {expression} {arguments}"


def candidate_expression(package: Path, recipe: str, attribute: str) -> str:
    """Evaluate a staged standalone recipe in the selected Nixpkgs scope.

    Returns:
        A Nix expression selecting the candidate's requested passthru derivation.

    """
    return (
        f"let pkgs = {package_scope()}; in "
        f"(pkgs.callPackage (builtins.toPath {nix_string(str(package / recipe))}) {{}})"
        f".{nix_string(attribute)}"
    )
