"""Verify the native bundle retains FigCraft document and collaboration handlers."""

import plistlib
import sys
from pathlib import Path

from check_craft_assets import check_bundle

package = Path(sys.argv[1])
check_bundle(package, sys.argv[2], sys.argv[3], pdf_models=False)
contents = package / "Applications/FigCraft.app/Contents"
info = plistlib.loads((contents / "Info.plist").read_bytes())
if info["CFBundleIdentifier"] != "ai.storyteller.figcraft":
    raise ValueError("Wrong native application identity")
if info["CFBundleExecutable"] != "FigCraft":
    raise ValueError("Wrong bundle executable")
if not (contents / "Resources/FigCraft.icns").read_bytes().startswith(b"icns"):
    raise ValueError("Native app icon is missing")
if not any(
    "figcraft" in entry["CFBundleURLSchemes"] for entry in info["CFBundleURLTypes"]
):
    raise ValueError("Collaboration invitation handler is missing")
if not any(
    entry["UTTypeIdentifier"] == "ai.storyteller.figcraft.document"
    for entry in info["UTExportedTypeDeclarations"]
):
    raise ValueError("Native document UTI is missing")
if len(info["CFBundleDocumentTypes"]) != 3:
    raise ValueError("Native/SVG/image document associations were lost")
if not info["NSSupportsAutomaticGraphicsSwitching"]:
    raise ValueError("Native graphics switching was lost")
