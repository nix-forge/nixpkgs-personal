"""Validate launcher output and the platform artifacts selected by Nix."""

import argparse
import pathlib
import plistlib

from defusedxml import ElementTree


def main() -> None:
    """Check the CLI output and the selected platform's installed metadata."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("package", type=pathlib.Path)
    parser.add_argument("upstream_version")
    parser.add_argument("package_version")
    parser.add_argument("app_id")
    parser.add_argument("revision")
    parser.add_argument("platform", choices=("darwin", "linux"))
    parser.add_argument("minimum_version")
    args = parser.parse_args()
    assert args.output.read_text().strip() == f"craft-launcher {args.upstream_version}"
    if args.platform == "darwin":
        contents = args.package / "Applications/Craft Launcher.app/Contents"
        info = plistlib.loads((contents / "Info.plist").read_bytes())
        assert info["CFBundleIdentifier"] == args.app_id
        assert info["CFBundleVersion"] == args.upstream_version
        assert info["CFBundleShortVersionString"] == args.upstream_version
        assert info["CraftLauncherBuildSHA"] == args.revision
        assert (contents / "MacOS" / info["CFBundleExecutable"]).is_file()
        minimum = tuple(map(int, info["LSMinimumSystemVersion"].split(".")))
        expected = tuple(map(int, args.minimum_version.split(".")))
        assert minimum >= expected
        assert (contents / "Resources/CraftLauncher.icns").read_bytes()[:4] == b"icns"
        assert (contents / "_CodeSignature/CodeResources").is_file()
    else:
        metadata = ElementTree.parse(
            args.package / "share/metainfo" / f"{args.app_id}.metainfo.xml",
        ).getroot()
        assert metadata.findtext("id") == args.app_id
        assert metadata.findtext("launchable") == f"{args.app_id}.desktop"
        icon_root = args.package / "share/icons/hicolor"
        for location, suffix in (
            ("scalable", "svg"),
            ("64x64", "png"),
            ("256x256", "png"),
        ):
            canonical = icon_root / location / "apps" / f"{args.app_id}.{suffix}"
            legacy = canonical.with_name(f"io.github.nix-forge.craft-launcher.{suffix}")
            assert canonical.is_file()
            assert legacy.is_symlink()
            assert legacy.resolve() == canonical.resolve()
        release = metadata.find("releases/release")
        assert release is not None
        assert release.attrib["version"] == args.package_version


if __name__ == "__main__":
    main()
