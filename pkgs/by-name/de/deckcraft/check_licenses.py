"""Verify that installed font notices retain the complete pinned licence texts."""

import hashlib
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

    # The local epaint source retains the notices omitted from the registry archive.
    for notice, digest in {
        "LICENSE-MIT": "95ca92f5f8ea5231f1580b3a2a799e8260af3114b900e1def5355a7f44bcf60c",
        "LICENSE-APACHE": "8173d5c29b4f956d532781d2b86e4e30f83e6b7878dce18c919451d6ba707c90",
    }.items():
        installed_notice = (
            package / "share/doc" / name / "licenses/vendor/epaint" / notice
        )
        if hashlib.sha256(installed_notice.read_bytes()).hexdigest() != digest:
            raise ValueError(f"Incomplete epaint notice: {notice}")


if __name__ == "__main__":
    check(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
