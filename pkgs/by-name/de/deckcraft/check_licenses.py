"""Verify that installed font notices retain the complete pinned licence texts."""

import sys
from pathlib import Path

NOTICES = ("OFL.txt", "UFL.txt", "Hack-Regular.txt", "emoji-icon-font-mit-license.txt")


def check(package: Path, vendor: Path, name: str) -> None:
    """Compare complete notices, including Hack's cumulative MIT and Vera terms.

    Raises:
        ValueError: If the pinned bundle is ambiguous or an installed notice differs.

    """
    bundles = list(vendor.glob("epaint_default_fonts-*/fonts"))
    if len(bundles) != 1:
        raise ValueError("Expected exactly one pinned epaint font bundle")
    bundle = bundles[0]
    installed = (
        package
        / "share/doc"
        / name
        / "licenses/dependencies"
        / bundle.parent.name
        / "fonts"
    )
    for notice in NOTICES:
        original = (bundle / notice).read_bytes()
        if not original or (installed / notice).read_bytes() != original:
            raise ValueError(f"Incomplete font notice: {notice}")


if __name__ == "__main__":
    check(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
