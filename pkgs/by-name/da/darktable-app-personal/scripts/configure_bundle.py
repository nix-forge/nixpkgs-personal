"""Configure the upstream bundle template for its Nix-built executable."""

from __future__ import annotations

import argparse
import pathlib
import plistlib
import re


def configure(
    template: pathlib.Path, output: pathlib.Path, version: str, minimum: str
) -> None:
    """Preserve upstream identity and associations while setting build metadata.

    Raises:
        ValueError: The version or upstream template cannot describe this bundle.

    """
    release = re.match(r"([0-9]+\.[0-9]+\.[0-9]+)(?:$|[-+])", version)
    if release is None:
        raise ValueError(f"Unsupported Darktable release version: {version!r}")
    info = plistlib.loads(template.read_bytes())
    if (
        info.get("CFBundleExecutable") != "darktable"
        or info.get("CFBundlePackageType") != "APPL"
    ):
        raise ValueError("Review the changed upstream application template")
    # Apple's authored release/build version fields are numeric, not Nix snapshot names.
    info["CFBundleShortVersionString"] = release.group(1)
    info["CFBundleVersion"] = release.group(1)
    info["LSMinimumSystemVersion"] = minimum
    info["LSApplicationCategoryType"] = "public.app-category.photography"
    info["NSHighResolutionCapable"] = True
    output.write_bytes(plistlib.dumps(info))


def main() -> None:
    """Configure the template selected by the package's upstream dependency."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("version")
    parser.add_argument("minimum")
    args = parser.parse_args()
    configure(args.template, args.output, args.version, args.minimum)


if __name__ == "__main__":
    main()
