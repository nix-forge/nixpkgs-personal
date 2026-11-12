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
        "ruzstd 0.9.1: bounded decompression (RUSTSEC-2026-0344)",
        "Nix fontconfig discovery and native desktop application identity",
        "Compact credits columns and native-platform rename regression fixture",
    ],
}
(output / "SOURCE-PROVENANCE.json").write_text(json.dumps(provenance, indent=2) + "\n")
