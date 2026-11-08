# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
archive=$(find "$out" -name app.asar -print -quit)
test -n "$archive"
asar extract "$archive" managed-feishin
cp @scripts@/managed-login.cjs @scripts@/managed-login-renderer.cjs \
  @scripts@/mpv-readiness.cjs @scripts@/mpv-message.cjs managed-feishin/out/main/
# Install before the application's windows are created, including on macOS.
sed -i '1i require("./managed-login.cjs").install(require("electron"));' managed-feishin/out/main/index.js
# Apply the declarative player path after electron-store migrations and
# before Feishin captures it for the lifetime of the process.
substituteInPlace managed-feishin/out/main/index.js --replace-fail \
  'const MPV_BINARY_PATH = store.get("mpv_path");' \
  'require("./managed-login.cjs").configurePlayer(store, require("node:path").join(require("electron").app.getPath("userData"), "managed.json")); const MPV_BINARY_PATH = store.get("mpv_path");'
# Device discovery shares the playback socket on Linux and macOS. Serialize
# both lifecycles before adding platform-specific integration.
@python@ @lifecycleSources@/mpv_lifecycle.py managed-feishin
FEISHIN_MAIN=managed-feishin/out/main/index.js \
  node --test @lifecycleTest@
@darwinIntegration@
asar pack managed-feishin "$archive" --unpack-dir node_modules
