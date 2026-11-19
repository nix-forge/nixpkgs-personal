"""Retain source and font provenance alongside the complete upstream notices."""

import json
import shutil
import sys
from pathlib import Path

from check_fonts import entries

fonts, recipe, output = map(Path, sys.argv[1:4])
rev, source_hash, font_rev, font_hash = sys.argv[4:8]
output.mkdir(parents=True, exist_ok=True)
shutil.copyfile(recipe, output / "source.nix")
provenance = {
    "source": {
        "url": "https://github.com/storytold/figcraft",
        "rev": rev,
        "hash": source_hash,
    },
    "fonts": {
        "url": "https://github.com/storytold/craft-fonts",
        "rev": font_rev,
        "hash": font_hash,
        "embedded": [
            {"path": file, "notice": notice, "sha256": digest}
            for file, notice, digest in entries(fonts)
        ],
    },
    "patches": [
        "Validate ZIP header consistency across the supported import formats",
        "Register embedded regional fonts for text fallback",
        "Report contextual errors when reopening recent files",
    ],
}
(output / "SOURCE-PROVENANCE.json").write_text(json.dumps(provenance, indent=2) + "\n")
