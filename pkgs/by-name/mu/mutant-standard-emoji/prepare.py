"""Prepare upstream codepoint artwork for nanoemoji without redrawing it."""

import re
import sys
from pathlib import Path

from lxml import etree


def prepare(artwork: Path) -> None:
    # SVG pixels and unitless user coordinates are equivalent here. Picosvg
    # expects unitless lengths, including lengths in inline style properties.
    pixels = re.compile(r"(-?(?:\d*\.)?\d+)px\b")
    parser = etree.XMLParser(resolve_entities=False, no_network=True)
    for path in sorted(artwork.glob("*.svg")):
        tree = etree.parse(str(path), parser)
        for element in tree.getroot().iter():
            for key, value in list(element.attrib.items()):
                element.set(key, pixels.sub(r"\1", value))
        tree.write(str(path), encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    prepare(Path(sys.argv[1]))
