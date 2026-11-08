"""Check bundle updates preserve upstream capabilities and replace release tokens."""

import importlib.util
import pathlib
import plistlib
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "configure_bundle", pathlib.Path(__file__).parent / "scripts/configure_bundle.py"
)
assert SPEC is not None
assert SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BundleTests(unittest.TestCase):
    def test_new_release_preserves_upstream_associations_and_identity(self) -> None:
        info = {
            "CFBundleIdentifier": "org.example.updated",
            "CFBundleExecutable": "darktable",
            "CFBundlePackageType": "APPL",
            "CFBundleIconFile": "Icons.icns",
            "CFBundleShortVersionString": "{VERSION}",
            "CFBundleVersion": "{VERSION}.{COMMITS}",
            "CFBundleDocumentTypes": [
                {"CFBundleTypeRole": "Viewer", "LSItemContentTypes": ["public.image"]}
            ],
            "NSPrincipalClass": "NSApplication",
        }
        with tempfile.TemporaryDirectory() as directory:
            source = pathlib.Path(directory) / "upstream.plist"
            output = pathlib.Path(directory) / "Info.plist"
            source.write_bytes(plistlib.dumps(info))
            MODULE.configure(source, output, "9.8.7-unstable-2026-10-13", "14.0")
            actual = plistlib.loads(output.read_bytes())
        self.assertEqual(actual["CFBundleShortVersionString"], "9.8.7")
        self.assertEqual(actual["CFBundleVersion"], "9.8.7")
        self.assertEqual(actual["LSMinimumSystemVersion"], "14.0")
        for key in (
            "CFBundleIdentifier",
            "CFBundleIconFile",
            "CFBundleDocumentTypes",
            "NSPrincipalClass",
        ):
            self.assertEqual(actual[key], info[key])


if __name__ == "__main__":
    unittest.main()
