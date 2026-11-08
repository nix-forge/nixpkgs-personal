"""Construct PdfCraft's native font input without its prohibited Noto CJK face."""

import hashlib
import os
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

ALLOWED_FAMILIES = {
    "Shippori Mincho",
    "BIZ UDPGothic",
    "BIZ UDMincho",
    "Noto Sans Arabic",
}
RETAINED_FACE_COUNT = 5
DROID_HASH = "2392015530438bafc48edfc4aee6d9de2387f627a6134d8ab3dfcc99d21c8240"
DROID_NOTICE_HASH = "38751245389e1e23f73e6f5384b5cbe7fa972cc4410c5adc9c04b082a0b9561a"
DROID_SOURCE = "https://android.googlesource.com/platform/frameworks/base/+/57bb140be9e48cf08acba131f7463e461777bb8e/data/fonts/DroidSansFallbackFull.ttf"
DROID_ROW = f"Droid Sans Fallback | Regular | fonts/droid-sans-fallback/DroidSansFallbackFull.ttf | Hans,Hant | Apache-2.0 | fonts/droid-sans-fallback/NOTICE | {DROID_HASH} | {DROID_SOURCE}"

THAI_HASH = "5a1c559bb539583c8a1fd99d1c5b9491e5e14478c9cd2bd0970d5c3096cc9ef8"
THAI_NOTICE_HASH = "2e98fd23a52d253db8612cd5942c8f2ff4111b21d2367050fdca91d8ccc374a0"
THAI_SOURCE = "https://github.com/google/fonts/tree/9710da1eacb3be272583c3224dcb70f9da6eadbb/ofl/notosansthai"
THAI_ROW = f"Noto Sans Thai | Regular | fonts/noto-sans-thai/NotoSansThai.ttf | Thai | OFL-1.1 | fonts/noto-sans-thai/OFL.txt | {THAI_HASH} | {THAI_SOURCE}"


@dataclass(frozen=True)
class FontFiles:
    """An unmodified font and its complete upstream notice."""

    font: Path
    notice: Path


def verified_copy(source: Path, target: Path, checksum: str | None = None) -> None:
    """Copy a verified file, retaining its upstream bytes.

    Raises:
        ValueError: If the expected file hash differs.

    """
    if (
        checksum is not None
        and hashlib.sha256(source.read_bytes()).hexdigest() != checksum
    ):
        raise ValueError(f"Checksum mismatch: {source.name}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def excluded_upstream_face(
    family: str, style: str, licence: str, checksum: str
) -> bool:
    """Exclude prohibited CJK and the identical, separately pinned Thai face.

    Returns:
        Whether to omit this upstream manifest row.

    Raises:
        ValueError: If the upstream Thai face no longer matches the reviewed input.

    """
    if family == "Noto Sans CJK SC":
        return True
    if family != "Noto Sans Thai":
        return False
    if style != "Regular" or licence != "OFL-1.1" or checksum != THAI_HASH:
        raise ValueError(f"Unreviewed font: {family} {style}")
    return True


def select(
    source: Path, droid: FontFiles, thai: FontFiles, output: Path, revision: str
) -> None:
    """Select allowed manifest entries and preserve their complete licence files.

    Raises:
        ValueError: If the input contains unreviewed or escaping font entries.

    """
    source = source.resolve()
    rows = []
    for line in (source / "fonts/manifest.txt").read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        family, style, filename, scripts, licence, licence_file, checksum, url = (
            field.strip() for field in line.split(" | ")
        )
        if excluded_upstream_face(family, style, licence, checksum):
            continue
        if family not in ALLOWED_FAMILIES or licence != "OFL-1.1":
            raise ValueError(f"Unreviewed font: {family} {style}")
        for relative in (filename, licence_file):
            path = Path(relative)
            if (
                path.is_absolute()
                or ".." in path.parts
                or not (source / path).resolve().is_relative_to(source)
            ):
                raise ValueError(f"Font input path escapes source: {relative}")
        verified_copy(source / filename, output / filename, checksum)
        verified_copy(source / licence_file, output / licence_file)
        rows.append(
            f"{family} | {style} | {filename} | {scripts} | {licence} | {licence_file} | {checksum} | {url}"
        )
    if len(rows) != RETAINED_FACE_COUNT:
        raise ValueError("Expected five reviewed OFL faces")
    verified_copy(
        droid.font,
        output / "fonts/droid-sans-fallback/DroidSansFallbackFull.ttf",
        DROID_HASH,
    )
    verified_copy(
        droid.notice, output / "fonts/droid-sans-fallback/NOTICE", DROID_NOTICE_HASH
    )
    rows.append(DROID_ROW)
    verified_copy(
        thai.font, output / "fonts/noto-sans-thai/NotoSansThai.ttf", THAI_HASH
    )
    verified_copy(
        thai.notice, output / "fonts/noto-sans-thai/OFL.txt", THAI_NOTICE_HASH
    )
    rows.append(THAI_ROW)
    (output / "fonts/manifest.txt").write_text(
        "# PdfCraft policy-compliant native font selection.\n" + "\n".join(rows) + "\n"
    )
    for name in ("LICENSE-MIT", "LICENSE-APACHE"):
        verified_copy(source / name, output / name)
    (output / "ATTRIBUTION.md").write_text(
        "# PdfCraft font input\n\n"
        "The first five faces retain the upstream craft-fonts manifest metadata and full OFL notices.\n"
        "Droid Sans Fallback is Copyright 2005-2008 The Android Open Source Project, Apache-2.0.\n"
        "Its complete original NOTICE is fonts/droid-sans-fallback/NOTICE.\n\n"
        "Noto Sans Thai is Copyright The Noto Project Authors; its original OFL is fonts/noto-sans-thai/OFL.txt.\n\n"
        f"Upstream input: https://github.com/storytold/craft-fonts/tree/{revision}\n\n"
        "Each manifest row records the file, licence, full notice, SHA-256 and original source:\n\n```text\n"
        + "\n".join(rows)
        + "\n```\n"
    )


if __name__ == "__main__":
    source, droid, droid_notice, thai, thai_notice, output = map(Path, sys.argv[1:])
    select(
        source,
        FontFiles(droid, droid_notice),
        FontFiles(thai, thai_notice),
        output,
        os.environ["CRAFT_FONTS_REVISION"],
    )
