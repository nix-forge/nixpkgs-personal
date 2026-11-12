"""Check installed craft application assets without Nix interpolation in Python."""

from __future__ import annotations

import argparse
import pathlib
import plistlib
import struct
import wave


def check_plist(path: pathlib.Path, upstream_version: str) -> None:
    """Check the executable and the upstream version in an installed plist."""
    with path.open("rb") as stream:
        info = plistlib.load(stream)
    assert (path.parent / "MacOS" / info["CFBundleExecutable"]).is_file()
    assert info["CFBundleShortVersionString"] == upstream_version
    assert "@" not in info["CFBundleVersion"]


def check_bundle(
    output: pathlib.Path,
    upstream_version: str,
    toolchain_minimum: str,
    *,
    pdf_models: bool,
) -> None:
    """Check the signed bundle, version floor, and optional bundled OCR models."""
    bundles = list((output / "Applications").glob("*.app"))
    assert len(bundles) == 1
    contents = bundles[0] / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    assert info["CFBundleVersion"] == upstream_version
    assert info["CFBundleShortVersionString"] == upstream_version
    minimum = tuple(map(int, info["LSMinimumSystemVersion"].split(".")))
    toolchain = tuple(map(int, toolchain_minimum.split(".")))
    assert minimum >= toolchain
    assert (contents / "_CodeSignature" / "CodeResources").is_file()
    if pdf_models:
        models = contents / "Resources" / "models"
        assert models.is_dir()
        assert not models.is_symlink()
        for name in (
            "text-detection.rten",
            "text-recognition.rten",
            "LICENSE-CC-BY-SA-4.0.txt",
        ):
            model = models / name
            assert model.is_file()
            assert not model.is_symlink()
            assert model.stat().st_size > 0


def check_png(path: pathlib.Path) -> None:
    """Check a PNG signature and nonempty dimensions."""
    image = path.read_bytes()
    assert image[:8] == b"\x89PNG\r\n\x1a\n"
    width, height = struct.unpack(">II", image[16:24])
    assert width > 0
    assert height > 0


def check_wav(path: pathlib.Path) -> None:
    """Check that an exported WAV contains audio frames at a positive rate."""
    with wave.open(str(path)) as audio:
        assert audio.getnframes() > 0
        assert audio.getframerate() > 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    plist = commands.add_parser("plist")
    plist.add_argument("path", type=pathlib.Path)
    plist.add_argument("upstream_version")
    bundle = commands.add_parser("bundle")
    bundle.add_argument("output", type=pathlib.Path)
    bundle.add_argument("upstream_version")
    bundle.add_argument("toolchain_minimum")
    bundle.add_argument("--pdf-models", action="store_true")
    for command in ("png", "wav"):
        commands.add_parser(command).add_argument("path", type=pathlib.Path)
    args = parser.parse_args()
    if args.command == "plist":
        check_plist(args.path, args.upstream_version)
    elif args.command == "bundle":
        check_bundle(
            args.output,
            args.upstream_version,
            args.toolchain_minimum,
            pdf_models=args.pdf_models,
        )
    elif args.command == "png":
        check_png(args.path)
    elif args.command == "wav":
        check_wav(args.path)


if __name__ == "__main__":
    main()
