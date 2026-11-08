"""Keep Feishin's themed macOS title bar and use native window controls."""

import sys
from pathlib import Path


def replace_once(source: str, old: str, new: str, name: str) -> str:
    count = source.count(old)
    if count != 1:
        raise ValueError(f"Expected one {name} anchor, found {count}")
    return source.replace(old, new, 1)


root = Path(sys.argv[1])
main_path = root / "out/main/index.js"
main = main_path.read_text()
main = replace_once(
    main,
    "    frame: false,\n    icon: isWindows()",
    "    frame: false,\n"
    '    ...isMacOS() && store.get("window_window_bar_style") === "macos" && '
    "{ trafficLightPosition: { x: 10, y: 5 } },\n"
    "    icon: isWindows()",
    "BrowserWindow options",
)
main = replace_once(
    main,
    "    ...windowBounds\n  });\n  electronLocalShortcut.register(mainWindow",
    "    ...windowBounds\n  });\n"
    '  if (isMacOS() && !nativeFrame && store.get("window_window_bar_style") === "macos") {\n'
    "    mainWindow.setWindowButtonVisibility(true);\n"
    "  }\n"
    "  electronLocalShortcut.register(mainWindow",
    "native window controls",
)
main_path.write_text(main)

css_matches = [
    path
    for path in (root / "out/renderer/assets").glob("*.css")
    if ".fs-window-bar-module-macos-button-group{" in path.read_text()
]
if len(css_matches) != 1:
    raise ValueError(
        f"Expected one macOS title bar stylesheet, found {len(css_matches)}"
    )
css_path = css_matches[0]
css = css_path.read_text()
css += "\n.fs-window-bar-module-macos-button-group{display:none!important}\n"
css_path.write_text(css)
