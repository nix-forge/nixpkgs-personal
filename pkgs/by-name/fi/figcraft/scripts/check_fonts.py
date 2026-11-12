"""Validate all release-pinned embedded fonts and their complete installed notices."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def entries(fonts: Path) -> list[tuple[str, str, str]]:
    """Return font, notice and digest records from both required manifests.

    Returns:
        Validated font, notice and digest tuples.

    Raises:
        ValueError: The release manifest, font bytes or notices differ from policy.

    """
    records = []
    for manifest in ("latin-manifest.txt", "manifest.txt"):
        for line in (fonts / "fonts" / manifest).read_text().splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            fields = [field.strip() for field in line.split(" | ")]
            if len(fields) != 8 or fields[4] != "OFL-1.1":
                raise ValueError(f"Unexpected font metadata: {line}")
            file, notice, digest = fields[2], fields[5], fields[6]
            for name in (file, notice):
                path = Path(name)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError(f"Unsafe manifest path: {name}")
            if hashlib.sha256((fonts / file).read_bytes()).hexdigest() != digest:
                raise ValueError(f"Font bytes differ from manifest: {file}")
            if not (fonts / notice).read_bytes():
                raise ValueError(f"Empty font notice: {notice}")
            records.append((file, notice, digest))
    if len(records) != 57 or len({record[0] for record in records}) != 57:
        raise ValueError(
            "Expected the complete release collection of 57 distinct fonts"
        )
    return records


def check(fonts: Path, package: Path | None) -> None:
    """Check manifest digests and optional output notice bytes.

    Raises:
        ValueError: An installed notice differs from the pinned input.

    """
    records = entries(fonts)
    if package is None:
        return
    installed = package / "share/doc/figcraft/licenses/craft-fonts"
    for _, notice, _ in records:
        if (installed / notice).read_bytes() != (fonts / notice).read_bytes():
            raise ValueError(f"Incomplete installed font notice: {notice}")
    for name in ("fonts/latin-manifest.txt", "fonts/manifest.txt", "ATTRIBUTION.md"):
        if (installed / name).read_bytes() != (fonts / name).read_bytes():
            raise ValueError(f"Incomplete font attribution: {name}")


def main() -> None:
    """Validate input or installed font assets."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("input", "installed"))
    parser.add_argument("fonts", type=Path)
    parser.add_argument("package", type=Path, nargs="?")
    args = parser.parse_args()
    if args.mode == "installed" and args.package is None:
        parser.error("installed requires a package directory")
    check(args.fonts, args.package)


if __name__ == "__main__":
    main()
