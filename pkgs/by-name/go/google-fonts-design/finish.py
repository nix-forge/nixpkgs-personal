"""Remove duplicate role providers and retain the catalog's license notices."""

import json
import shutil
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

output, source = map(Path, sys.argv[1:])
# The UI roles use dedicated Inter/Literata, and emoji uses current Noto.
authorities = {"Inter", "Literata", "Noto Color Emoji", "Noto Color Emoji Compat Test"}
removed = []
for path in sorted((output / "share/fonts").rglob("*.ttf")):
    with TTFont(path, lazy=True) as font:
        family = font["name"].getBestFamilyName()
    if family in authorities:
        removed.append({"file": path.name, "family": family})
        path.unlink()
if not {"Inter", "Literata", "Noto Color Emoji"}.issubset({
    x["family"] for x in removed
}):
    raise ValueError("Upstream role families changed; review duplicate-provider policy")
doc = output / "share/doc/google-fonts-design"
doc.mkdir(parents=True)
(doc / "excluded-providers.json").write_text(json.dumps(removed, indent=2) + "\n")
for path in sorted(source.rglob("*")):
    if path.is_file() and path.name.lower() in {
        "ofl.txt",
        "license.txt",
        "license",
        "ufl.txt",
    }:
        target = doc / "licenses" / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
