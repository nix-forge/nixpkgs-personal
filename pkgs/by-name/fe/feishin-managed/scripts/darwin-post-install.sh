# shellcheck shell=bash
# Feishin's themed macOS bar has HTML traffic lights. Use AppKit's
# controls in that bar, keeping its color and track title.
@python@ @nativeTitlebar@ managed-feishin
# Feishin's macOS song event is unused upstream. Supply its artwork to
# mpv for native Now Playing.
cp @scripts@/mpv-now-playing.cjs managed-feishin/out/main/
sed -i '1i require("./mpv-now-playing.cjs").install();' managed-feishin/out/main/index.js
