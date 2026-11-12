"""Validate an installed macOS application's metadata without launching it."""

from __future__ import annotations

import argparse
import os
import pathlib
import plistlib
import re


def check_bundle(
    app: pathlib.Path,
    *,
    expected_version: str | None = None,
    version_key: str = "CFBundleShortVersionString",
    allow_build_suffix: bool = False,
    authored: bool = False,
) -> None:
    """Check plist identity and declared executable and icon against the bundle.

    Raises:
        TypeError: The plist does not contain a dictionary.
        ValueError: Metadata is invalid or a declared bundle artifact is missing.

    """
    contents = app / "Contents"
    with (contents / "Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if not isinstance(info, dict):
        raise TypeError("Application Info.plist must contain a dictionary")
    for key in (
        "CFBundleIdentifier",
        "CFBundleExecutable",
        "CFBundleName",
        "CFBundleVersion",
    ):
        if not isinstance(info.get(key), str) or not info[key]:
            raise ValueError(f"Missing nonempty string: {key}")
    if not re.fullmatch(
        r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", info["CFBundleIdentifier"]
    ):
        raise ValueError("Bundle identifier must be a reverse-DNS identifier")
    if info.get("CFBundlePackageType") != "APPL":
        raise ValueError("Application bundle must declare CFBundlePackageType=APPL")
    executable = info["CFBundleExecutable"]
    if executable in {".", ".."} or "/" in executable:
        raise ValueError("CFBundleExecutable must name a file in Contents/MacOS")
    program = contents / "MacOS" / executable
    if not program.is_file() or not os.access(program, os.X_OK):
        raise ValueError(f"Bundle executable is missing or not executable: {program}")
    _check_versions(info, expected_version, version_key, allow_build_suffix, authored)
    _check_declared_settings(info)
    _check_icon(contents, info.get("CFBundleIconFile"))


def _check_versions(
    info: dict[str, object],
    expected_version: str | None,
    version_key: str,
    allow_build_suffix: bool,
    authored: bool,
) -> None:
    """Check explicit release agreement and the separate authored-version contract.

    Raises:
        ValueError: A version field is absent, malformed or stale.

    """
    # Vendor build numbers can have more components than Apple's authored-plist
    # recommendation. Preserve their signed bytes and require a nonempty value.
    if "CFBundleShortVersionString" in info and (
        not isinstance(info["CFBundleShortVersionString"], str)
        or not info["CFBundleShortVersionString"]
    ):
        raise ValueError("CFBundleShortVersionString must be a nonempty string")
    if expected_version is not None:
        actual = info.get(version_key)
        matches = actual == expected_version
        if allow_build_suffix and isinstance(actual, str):
            matches = (
                matches
                or re.fullmatch(re.escape(expected_version) + r"\.[0-9]+", actual)
                is not None
            )
        if not matches:
            raise ValueError(
                f"{version_key} does not match the package version: "
                f"{actual!r}, expected {expected_version!r}"
            )
    if authored:
        for key, pattern in (
            ("CFBundleShortVersionString", r"[0-9]+\.[0-9]+\.[0-9]+"),
            ("CFBundleVersion", r"[0-9]+(?:\.[0-9]+){0,2}"),
        ):
            value = info.get(key)
            if not isinstance(value, str) or re.fullmatch(pattern, value) is None:
                raise ValueError(f"Invalid authored {key}: {value!r}")


def _check_declared_settings(info: dict[str, object]) -> None:
    """Validate declared settings without adding unsupported capabilities.

    Raises:
        TypeError: A declared setting has the wrong property-list type.
        ValueError: A deployment version is malformed.

    """
    string_keys = {
        "CFBundleDisplayName",
        "CFBundleDevelopmentRegion",
        "CFBundleInfoDictionaryVersion",
        "LSApplicationCategoryType",
        "NSPrincipalClass",
        "NSHumanReadableCopyright",
    }
    string_keys |= {
        key for key in info if key.startswith("NS") and key.endswith("UsageDescription")
    }
    for key in string_keys & info.keys():
        if not isinstance(info[key], str):
            raise TypeError(f"{key} must be a string")
    boolean_keys = {
        "LSUIElement",
        "LSBackgroundOnly",
        "LSMultipleInstancesProhibited",
        "NSHighResolutionCapable",
    }
    for key in boolean_keys & info.keys():
        if not isinstance(info[key], bool):
            raise TypeError(f"{key} must be a boolean")
    for key in {"CFBundleSupportedPlatforms", "CFBundleLocalizations"} & info.keys():
        _string_array(key, info[key])
    if "LSMinimumSystemVersion" in info:
        value = info["LSMinimumSystemVersion"]
        if (
            not isinstance(value, str)
            or re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value) is None
        ):
            raise ValueError("LSMinimumSystemVersion must be a numeric version string")
    for key in {"CFBundleDocumentTypes", "CFBundleURLTypes"} & info.keys():
        _check_associations(key, info[key])


def _check_associations(key: str, value: object) -> None:
    """Validate the types of declared document and URL associations.

    Raises:
        TypeError: An association has the wrong property-list type.
        ValueError: An association declares an invalid role.

    """
    if not isinstance(value, list) or any(not isinstance(item, dict) for item in value):
        raise TypeError(f"{key} must be an array of dictionaries")
    array_keys = {
        "CFBundleTypeExtensions",
        "CFBundleTypeMIMETypes",
        "LSItemContentTypes",
        "CFBundleURLSchemes",
    }
    for item in value:
        if "CFBundleTypeRole" in item and item["CFBundleTypeRole"] not in {
            "Editor",
            "Viewer",
            "Shell",
            "None",
        }:
            raise ValueError("Invalid CFBundleTypeRole")
        for array_key in array_keys & item.keys():
            _string_array(array_key, item[array_key])


def _string_array(key: str, value: object) -> None:
    """Check the property-list representation of a string array.

    Raises:
        TypeError: The value is not an array of strings.

    """
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        raise TypeError(f"{key} must be an array of strings")


def _check_icon(contents: pathlib.Path, icon: object) -> None:
    """Check an icon declared by the bundle.

    Raises:
        ValueError: The declared filename is invalid or absent from Resources.

    """
    if icon:
        if not isinstance(icon, str) or icon in {".", ".."} or "/" in icon:
            raise ValueError("CFBundleIconFile must name a file in Contents/Resources")
        resources = contents / "Resources"
        if not any((resources / name).is_file() for name in (icon, f"{icon}.icns")):
            raise ValueError(f"Declared bundle icon is missing: {icon}")


def main() -> None:
    """Validate the bundle supplied by the package's install check."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--expected-version")
    parser.add_argument(
        "--version-key",
        choices=["CFBundleShortVersionString", "CFBundleVersion"],
        default="CFBundleShortVersionString",
    )
    parser.add_argument("--allow-build-suffix", action="store_true")
    parser.add_argument("--authored", action="store_true")
    args = parser.parse_args()
    check_bundle(
        args.app,
        expected_version=args.expected_version,
        version_key=args.version_key,
        allow_build_suffix=args.allow_build_suffix,
        authored=args.authored,
    )


if __name__ == "__main__":
    main()
