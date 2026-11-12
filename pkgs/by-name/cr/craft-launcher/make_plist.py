"""Write numerical bundle versions and the toolchain's actual deployment minimum."""

import pathlib
import plistlib
import sys

output, version, revision, toolchain_minimum = sys.argv[1:]
minimum = max(
    "11.0", toolchain_minimum, key=lambda value: tuple(map(int, value.split(".")))
)
info = {
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleIdentifier": "io.github.nix-forge.craft-launcher",
    "CFBundleName": "Craft Launcher",
    "CFBundleDisplayName": "Craft Launcher",
    "CFBundleExecutable": "craft-launcher",
    "CFBundleIconFile": "CraftLauncher.icns",
    "CFBundlePackageType": "APPL",
    "CFBundleVersion": version,
    "CFBundleShortVersionString": version,
    "CraftLauncherBuildSHA": revision,
    "LSMinimumSystemVersion": minimum,
    "NSHighResolutionCapable": True,
}
pathlib.Path(output).write_bytes(plistlib.dumps(info))
