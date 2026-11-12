"""Validate FilmCraft's native-menu dependency boundary."""

import json
import sys
from pathlib import Path


def _reachable(nodes: dict, root: str) -> set:
    pending = [root]
    visited = set()
    while pending:
        current = pending.pop()
        if current not in visited:
            visited.add(current)
            pending.extend(nodes[current]["dependencies"])
    return visited


def check(metadata: dict, target: str) -> None:
    """Keep the AppKit menu backend without unused Rust GTK dependencies.

    Raises:
        ValueError: If the resolved graph violates the native-menu contract.

    """
    packages = {item["id"]: item for item in metadata["packages"]}
    nodes = {item["id"]: item for item in metadata["resolve"]["nodes"]}
    if any(item["name"] in {"glib", "gtk", "gtk4"} for item in packages.values()):
        raise ValueError("The unused Rust GTK dependency chain remains")
    apps = [item for item in packages.values() if item["name"] == "filmcraft"]
    if len(apps) != 1:
        raise ValueError("Expected the FilmCraft application root")
    active = _reachable(nodes, apps[0]["id"])
    menus = [item for item in active if packages[item]["name"] == "muda"]
    if "apple-darwin" not in target:
        if menus:
            raise ValueError("The macOS-only menu dependency entered another target")
        return
    if len(menus) != 1 or packages[menus[0]]["version"] != "0.21.0":
        raise ValueError("The original native menu provider must remain")
    menu = nodes[menus[0]]
    if {"gtk3", "gtk4"}.intersection(menu["features"]):
        raise ValueError("Unused GTK menu features were re-enabled")
    dependencies = {packages[item]["name"] for item in menu["dependencies"]}
    if not {"objc2", "objc2-app-kit", "objc2-foundation"}.issubset(dependencies):
        raise ValueError("The native AppKit menu dependencies changed")


if __name__ == "__main__":
    check(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")), sys.argv[2])
