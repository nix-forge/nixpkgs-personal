"""Verify or refresh the files needed by standalone package updaters."""

from __future__ import annotations

import argparse
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def imported_modules(source: Path) -> set[str]:
    """Read absolute import names without executing the updater."""
    modules = set()
    for node in ast.walk(ast.parse(source.read_bytes(), filename=str(source))):
        match node:
            case ast.Import(names=aliases):
                modules.update(alias.name.split(".")[0] for alias in aliases)
            case ast.ImportFrom(module=str(module), level=0):
                modules.add(module.split(".")[0])
    return modules


def expected_mirrors() -> dict[Path, Path]:
    """Map adjacent launcher and helper paths to their canonical sources."""
    recipes = ROOT / "pkgs/by-name"
    canonical = {path.stem: path for path in (ROOT / "scripts/updaters").glob("*.py")}
    canonical["notification_process"] = (
        recipes / "no/notification-process/src/notification_process.py"
    )
    launcher = ROOT / "scripts/run_package_update.py"
    mirrors = {}
    for wrapper in recipes.glob("*/*/update.nix"):
        if "./run_update.py" in wrapper.read_text(encoding="utf-8"):
            mirrors[wrapper.with_name("run_update.py")] = launcher

    dependencies = {
        module: imported_modules(source) & canonical.keys()
        for module, source in canonical.items()
    }
    for updater in recipes.glob("*/*/update.py"):
        pending = imported_modules(updater) & canonical.keys()
        seen = set()
        while pending:
            module = pending.pop()
            seen.add(module)
            source = canonical[module]
            mirrors[updater.with_name(source.name)] = source
            pending.update(dependencies[module] - seen)
    return mirrors


def main() -> int:
    """Check for missing or stale copies, optionally regenerating them."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    status = 0
    for mirror, source in sorted(expected_mirrors().items()):
        data = source.read_bytes()
        if not mirror.is_symlink():
            if mirror.is_file() and mirror.read_bytes() == data:
                continue
            if args.write:
                mirror.write_bytes(data)
                continue
        sys.stderr.write(
            f"Updater mirror differs from its canonical source: {mirror.relative_to(ROOT)}\n",
        )
        status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
