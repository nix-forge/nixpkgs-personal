"""Check package boundaries and run updater imports outside the checkout."""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# These helpers deliberately remain package-local so copied packages are usable.
# List intended copies explicitly; specialized Windows and emoji font inspectors
# have separate behavior and do not belong to the Apple font helper group.
HELPER_COPIES = {
    "catalog.py": ("anthropic-skills", "openai-skills"),
    "update_support.py": (
        "anthropic-skills",
        "apple-color-emoji",
        "apple-fonts",
        "bitwarden-desktop",
        "claude-desktop",
        "libreoffice",
        "linearmouse",
        "mattpocock-skills",
        "microsoft-teams",
        "openai-codex-desktop",
        "openai-skills",
        "pstack-skills",
        "remindctl",
        "spotify-spotx",
        "steam",
        "t3-code",
        "ttf-ms-win11-auto",
        "vorssaint",
        "wootility",
    ),
    "skills_updater.py": (
        "anthropic-skills",
        "mattpocock-skills",
        "openai-skills",
        "pstack-skills",
    ),
    "unpack.py": (
        "apple-fonts",
        "apple-new-york",
        "apple-sf-arabic",
        "apple-sf-armenian",
        "apple-sf-compact",
        "apple-sf-georgian",
        "apple-sf-hebrew",
        "apple-sf-mono",
        "apple-sf-pro",
    ),
    "font_support.py": (
        "apple-fonts",
        "apple-new-york",
        "apple-sf-arabic",
        "apple-sf-armenian",
        "apple-sf-compact",
        "apple-sf-georgian",
        "apple-sf-hebrew",
        "apple-sf-mono",
        "apple-sf-pro",
    ),
}


def check_helper_copies(root: Path) -> None:
    for filename, names in HELPER_COPIES.items():
        original = root / "pkgs/by-name" / names[0][:2] / names[0] / filename
        expected = original.read_bytes()
        for name in names[1:]:
            copy = root / "pkgs/by-name" / name[:2] / name / filename
            if copy.read_bytes() != expected:
                raise ValueError(
                    f"Divergent helper copy: {copy.relative_to(root)} differs from "
                    f"{original.relative_to(root)}; review every copy in this group"
                )


def check_packages(root: Path) -> None:
    check_helper_copies(root)
    packages = sorted((root / "pkgs/by-name").glob("*/*"))
    if not packages:
        raise ValueError("No package directories found")
    updates = 0
    for package in packages:
        if package.parent.name != package.name[:2].lower():
            raise ValueError(f"Wrong by-name prefix: {package}")
        for required in ("package.nix", "README.md"):
            if not (package / required).is_file():
                raise ValueError(f"Missing {required}: {package}")
        for path in package.rglob("*"):
            if path.is_symlink() and not path.resolve().is_relative_to(
                package.resolve()
            ):
                raise ValueError(f"Escaping package symlink: {path}")
        with tempfile.TemporaryDirectory(prefix="standalone-package-") as temporary:
            isolated = Path(temporary) / "package"
            shutil.copytree(
                package,
                isolated,
                ignore=shutil.ignore_patterns(
                    "__pycache__", ".build", ".swiftpm", ".ruff_cache"
                ),
            )
            updater = isolated / "update.py"
            if updater.exists():
                environment = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}
                subprocess.run(
                    [sys.executable, "-B", str(updater), "--help"],
                    cwd=temporary,
                    env=environment,
                    check=True,
                    stdout=subprocess.DEVNULL,
                    timeout=30,
                )
                updates += 1
    print(
        f"Checked {len(packages)} independent directories and {updates} isolated updater imports"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    check_packages(parser.parse_args().root.resolve())
