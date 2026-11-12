"""Check package boundaries and run updater imports outside the checkout."""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from notification_process import run as run_command

# These helpers deliberately remain package-local so copied packages are usable.
# List intended copies explicitly; specialized Windows and emoji font inspectors
# have separate behavior and do not belong to the Apple font helper group.
HELPER_COPIES = {
    "run_update.py": (
        "anthropic-skills",
        "apple-color-emoji",
        "apple-fonts",
        "audiomuse-ai",
        "bitwarden-desktop",
        "jellyfin-plugin-moonbase",
        "jellyfin-plugin-subtitle-extract",
        "libreoffice",
        "linearmouse",
        "mattpocock-skills",
        "microsoft-teams",
        "moonfin",
        "openai-skills",
        "psscriptanalyzer",
        "pstack-skills",
        "rea",
        "remindctl",
        "spotify-spotx",
        "steam",
        "ttf-ms-win11-auto",
        "vorssaint",
        "wardrowbe-backend",
        "wardrowbe-frontend",
        "wootility",
    ),
    "update_transaction.py": (
        "anthropic-skills",
        "apple-color-emoji",
        "apple-fonts",
        "audiomuse-ai",
        "bitwarden-desktop",
        "jellyfin-plugin-moonbase",
        "jellyfin-plugin-subtitle-extract",
        "libreoffice",
        "linearmouse",
        "mattpocock-skills",
        "microsoft-teams",
        "moonfin",
        "openai-skills",
        "psscriptanalyzer",
        "pstack-skills",
        "rea",
        "remindctl",
        "spotify-spotx",
        "steam",
        "ttf-ms-win11-auto",
        "vorssaint",
        "wardrowbe-backend",
        "wardrowbe-frontend",
        "wootility",
    ),
    "update_nix.py": (
        "audiomuse-ai",
        "jellyfin-plugin-moonbase",
        "jellyfin-plugin-subtitle-extract",
        "psscriptanalyzer",
    ),
    "notification_process.py": (
        "notification-process",
        "jellyfin-plugin-moonbase",
        "jellyfin-plugin-subtitle-extract",
        "moonfin",
        "psscriptanalyzer",
        "rea",
        "wardrowbe-backend",
        "wardrowbe-frontend",
    ),
    "catalog.py": ("anthropic-skills", "openai-skills"),
    "update_support.py": (
        "anthropic-skills",
        "apple-color-emoji",
        "apple-fonts",
        "bitwarden-desktop",
        "libreoffice",
        "linearmouse",
        "mattpocock-skills",
        "microsoft-teams",
        "openai-skills",
        "pstack-skills",
        "remindctl",
        "spotify-spotx",
        "steam",
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
    "unpack_font_distribution.py": ("apple-fonts",),
    "font_support.py": ("apple-fonts",),
}


def check_helper_copies(root: Path) -> None:
    for filename, names in HELPER_COPIES.items():
        original = root / "pkgs/by-name" / names[0][:2] / names[0] / filename
        if filename == "notification_process.py":
            original = original.parent / "src" / filename
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
                run_command(
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
