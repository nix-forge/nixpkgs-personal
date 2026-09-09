"""Apply the PersonalMonitor identity to the pinned upstream source tree."""

from __future__ import annotations

import argparse
import plistlib
import re
from pathlib import Path

APP_ID = "io.github.ianhollow.personalmonitor"
APP_NAME = "PersonalMonitor"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if text.count(old) != 1:
        raise ValueError(f"Review upstream change in {path.name}: {old}")
    path.write_text(text.replace(old, new))


def rebrand(root: Path) -> None:
    originals = {}
    for directory in (root / "Sources", root / "Resources"):
        for path in directory.rglob("*"):
            if path.suffix not in {
                ".swift",
                ".plist",
                ".strings",
                ".stringsdict",
                ".pl",
            }:
                continue
            old = path.read_text()
            originals[path] = old
            lines = []
            for line in old.splitlines(keepends=True):
                # Copyright credits continue identifying the original author.
                if "copyright" not in line.lower() and "©" not in line:
                    line = line.replace("com.vorssaint.utils", APP_ID)
                    line = line.replace("com.vorssaint", APP_ID).replace(
                        "org.vorssaint", APP_ID
                    )
                    line = line.replace("Vorssaint", APP_NAME)
                    line = (
                        line.replace("vorssaint-", "personalmonitor-")
                        if "http" not in line
                        and "vorssaint/vorssaint-utils" not in line
                        else line
                    )
                lines.append(line)
            new = "".join(lines)
            if new != old:
                path.write_text(new)

    sources = root / "Sources/Vorssaint"
    app_info = sources / "Core/AppInfo.swift"
    replace_once(
        app_info,
        "enum AppInfo {",
        "enum AppInfo {\n    static let isPackageManaged = true",
    )
    for old in (
        "https://vorssaint.com",
        "https://github.com/vorssaint/vorssaint-utils",
    ):
        replace_once(app_info, old, "https://github.com/IanHollow/nixpkgs-personal")

    updater = sources / "Services/Update/UpdateService.swift"
    replace_once(
        updater,
        'private let repository = "vorssaint/vorssaint-utils"',
        'private let repository = "IanHollow/nixpkgs-personal"',
    )
    for signature in (
        "func startAutomaticChecks() {",
        "private func configureAutomaticChecks() {",
        "func checkIfStale(maxAge: TimeInterval = 15 * 60) {",
        "func downloadAndInstall() {",
    ):
        replace_once(
            updater,
            signature,
            signature + "\n        if AppInfo.isPackageManaged { return }",
        )
    replace_once(
        updater,
        "func check(manual: Bool) {",
        """func check(manual: Bool) {
        if AppInfo.isPackageManaged {
            state = .failed("Update PersonalMonitor through your package manager.")
            return
        }""",
    )
    replace_once(
        sources / "Services/Update/UpdateShowcaseMedia.swift",
        "func load() {",
        "func load() {\n        if AppInfo.isPackageManaged { state = .failed; return }",
    )

    # Ad-hoc signatures cannot satisfy a Developer ID team requirement. Do not
    # claim the upstream team or weaken privileged IPC to identifier-only trust.
    ipc = sources / "Services/FanControl/FanControlXPC.swift"
    text = ipc.read_text().replace(
        'static let teamID = "3D485NHW29"', 'static let teamID = ""'
    )
    text, count = re.subn(
        r'"anchor apple generic and certificate leaf\[subject.OU\].*$',
        '"anchor apple and not anchor apple"',
        text,
        flags=re.MULTILINE,
    )
    if count != 2 or "3D485NHW29" in text:
        raise ValueError("Review upstream fan-control signing requirements")
    ipc.write_text(text)
    replace_once(
        sources / "Services/FanControl/FanControlService.swift",
        "private func refreshAccessState() {",
        """private func refreshAccessState() {
        if AppInfo.isPackageManaged {
            accessState = .unavailable
            error = .helperUnavailable
            return
        }""",
    )
    strings = sources / "Core/FanControlStrings.swift"
    text, count = re.subn(
        r'helperUnavailable: "[^"\n]*"',
        'helperUnavailable: "Privileged fan control is unavailable in this ad-hoc signed build."',
        strings.read_text(),
    )
    if count == 0:
        raise ValueError("Missing fan-control status messages")
    strings.write_text(text)

    info = root / "Resources/Info.plist"
    data = plistlib.loads(info.read_bytes())
    if data["CFBundleIdentifier"] != APP_ID or data["CFBundleExecutable"] != APP_NAME:
        raise ValueError("Inconsistent application identity")
    data["CFBundleDisplayName"] = APP_NAME
    info.write_bytes(plistlib.dumps(data))

    for path, original in originals.items():
        text = path.read_text()
        if text == original:
            continue
        notice = "Modified by nixpkgs-personal on 2026-09-08 for the unofficial PersonalMonitor build."
        if path.suffix in {".plist", ".stringsdict"}:
            text += f"\n<!-- {notice} -->\n"
        elif path.suffix == ".pl":
            # Preserve a Perl shebang at the beginning of the file.
            text += f"\n# {notice}\n"
        else:
            text = f"// {notice}\n" + text
        path.write_text(text)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    rebrand(args.source)


if __name__ == "__main__":
    main()
