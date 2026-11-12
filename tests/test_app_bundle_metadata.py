"""Check metadata validation against complete and malformed application bundles."""

from __future__ import annotations

import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("check_app_bundle.py")
SPEC = importlib.util.spec_from_file_location("app_bundle_checker", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


DESKTOP_SPEC = importlib.util.spec_from_file_location(
    "desktop_checker", pathlib.Path(__file__).with_name("check_desktop_entry.py")
)
assert DESKTOP_SPEC is not None
assert DESKTOP_SPEC.loader is not None
DESKTOP_CHECKER = importlib.util.module_from_spec(DESKTOP_SPEC)
DESKTOP_SPEC.loader.exec_module(DESKTOP_CHECKER)


class BundleMetadataTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="bundle-metadata-test-")
        self.addCleanup(temporary.cleanup)
        self.app = pathlib.Path(temporary.name) / "Example App.app"
        self.contents = self.app / "Contents"
        (self.contents / "MacOS").mkdir(parents=True)
        (self.contents / "Resources").mkdir()
        self.program = self.contents / "MacOS" / "example"
        self.program.write_text("#!/bin/sh\nexit 0\n")
        self.program.chmod(0o755)
        (self.contents / "Resources" / "Example.icns").write_bytes(b"icns")
        self.info: dict[str, object] = {
            "CFBundleIdentifier": "org.example.app",
            "CFBundleName": "Example App",
            "CFBundleExecutable": "example",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "26.1.2.3",
            "CFBundleShortVersionString": "26.1.2",
            "CFBundleIconFile": "Example",
        }

    def check(self, **options: object) -> None:
        (self.contents / "Info.plist").write_bytes(plistlib.dumps(self.info))
        CHECKER.check_bundle(self.app, **options)

    def test_complete_bundle_and_vendor_build_number(self) -> None:
        self.check()

    def test_expected_release_detects_stale_metadata(self) -> None:
        self.check(expected_version="26.1.2")
        with self.assertRaisesRegex(ValueError, "package version"):
            self.check(expected_version="26.2.0")

    def test_vendor_release_build_suffix_is_explicit(self) -> None:
        self.info["CFBundleShortVersionString"] = "26.1.2.3"
        self.check(expected_version="26.1.2", allow_build_suffix=True)
        with self.assertRaisesRegex(ValueError, "package version"):
            self.check(expected_version="26.1.2")
        self.info["CFBundleShortVersionString"] = "26.1.2.3.4"
        with self.assertRaisesRegex(ValueError, "package version"):
            self.check(expected_version="26.1.2", allow_build_suffix=True)

    def test_bootstrap_bundle_without_short_version(self) -> None:
        del self.info["CFBundleShortVersionString"]
        self.check(expected_version="26.1.2.3", version_key="CFBundleVersion")

    def test_authored_versions_are_strict_without_rewriting_vendors(self) -> None:
        self.info["CFBundleVersion"] = "26.1.2"
        self.check(authored=True)
        self.info["CFBundleShortVersionString"] = "26.1.2-preview"
        self.check()
        with self.assertRaisesRegex(ValueError, "authored"):
            self.check(authored=True)

    def test_declared_settings_use_native_plist_types(self) -> None:
        self.info.update({
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": True,
            "CFBundleSupportedPlatforms": ["MacOSX"],
            "CFBundleDocumentTypes": [
                {
                    "CFBundleTypeRole": "Viewer",
                    "LSItemContentTypes": ["public.image"],
                    "CFBundleTypeExtensions": ["*"],
                }
            ],
            "CFBundleURLTypes": [{"CFBundleURLSchemes": ["example"]}],
            "NSScreenCaptureUsageDescription": "Recognize selected screen text.",
        })
        self.check()
        for key, value in (
            ("LSMinimumSystemVersion", 14),
            ("LSUIElement", "true"),
            ("CFBundleSupportedPlatforms", "MacOSX"),
            ("CFBundleDocumentTypes", [{"CFBundleTypeRole": "invalid"}]),
            ("CFBundleURLTypes", [{"CFBundleURLSchemes": [1]}]),
            ("NSScreenCaptureUsageDescription", True),
        ):
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = value
                with self.assertRaises((TypeError, ValueError)):
                    self.check()
                self.info[key] = original

    def test_store_executable_symlink_is_allowed(self) -> None:
        target = self.app.parent / "installed-command"
        self.program.rename(target)
        self.program.symlink_to(target)
        self.check()

    def test_invalid_identity_or_executable_path_is_rejected(self) -> None:
        for key, value in (
            ("CFBundleIdentifier", "invalid identifier"),
            ("CFBundleExecutable", "../outside"),
            ("CFBundleName", ""),
            ("CFBundlePackageType", "BNDL"),
            ("CFBundleShortVersionString", ""),
        ):
            with self.subTest(key=key):
                original = self.info[key]
                self.info[key] = value
                with self.assertRaises((TypeError, ValueError)):
                    self.check()
                self.info[key] = original

    def test_missing_icon_is_rejected(self) -> None:
        (self.contents / "Resources" / "Example.icns").unlink()
        with self.assertRaisesRegex(ValueError, "icon is missing"):
            self.check()

    def test_non_executable_program_is_rejected(self) -> None:
        self.program.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "not executable"):
            self.check()


class DesktopMetadataTest(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="desktop-metadata-test-")
        self.addCleanup(temporary.cleanup)
        self.output = pathlib.Path(temporary.name)
        (self.output / "bin").mkdir()
        command = self.output / "bin/example"
        command.write_text("#!/bin/sh\nexit 0\n")
        command.chmod(0o755)
        applications = self.output / "share/applications"
        applications.mkdir(parents=True)
        self.desktop = applications / "org.example.app.desktop"
        self.desktop.write_text(
            "[Desktop Entry]\nType=Application\nName=Example\nExec=example %U\n"
            "TryExec=example\nIcon=org.example.app\n"
        )
        icons = self.output / "share/icons/hicolor/scalable/apps"
        icons.mkdir(parents=True)
        self.icon = icons / "org.example.app.svg"
        self.icon.write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')

    def check(self) -> None:
        DESKTOP_CHECKER.check_desktop(self.output, self.desktop.name, "example")

    def test_installed_program_and_theme_icon(self) -> None:
        self.check()
        self.desktop.write_text(
            self.desktop.read_text().replace(
                "\nExec=example", f'\nExec="{self.output}/bin/example"'
            )
        )
        self.check()

    def test_wrong_program_is_rejected(self) -> None:
        self.desktop.write_text(
            self.desktop.read_text().replace("Exec=example", "Exec=other")
        )
        with self.assertRaisesRegex(ValueError, "installed command"):
            self.check()

    def test_missing_theme_icon_is_rejected(self) -> None:
        self.icon.unlink()
        with self.assertRaisesRegex(ValueError, "icon is missing"):
            self.check()


if __name__ == "__main__":
    unittest.main()
