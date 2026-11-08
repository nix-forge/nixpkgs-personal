# shellcheck shell=bash
# shellcheck disable=SC2154
runHook preInstall
app="$out/libexec/aurral"
mkdir -p "$app" "$out/bin" "$out/share/doc/aurral"
# Keep pnpm's root virtual store and workspace links in the same relative layout.
cp -R node_modules backend lib "$app/"
mkdir -p "$app/frontend"
cp -R frontend/dist frontend/node_modules "$app/frontend/"
cp package.json "$app/"
cp frontend/package.json "$app/frontend/"
install -Dm644 LICENSE "$out/share/doc/aurral/LICENSE"
# Musl prebuilds cannot load in this glibc package. Sharp uses the source addon.
find "$app/node_modules/.pnpm" -mindepth 1 -maxdepth 1 -type d -name '@img+sharp-*' -exec rm -r -- {} +
# Remove references to those excluded prebuilds, retaining every runtime link.
find "$app/node_modules/.pnpm" -type l -path '*/node_modules/@img/sharp-*' -delete
# The documentation workspace is not part of the installed application.
test -L "$app/node_modules/.pnpm/node_modules/aurral-docs"
rm -- "$app/node_modules/.pnpm/node_modules/aurral-docs"
find "$app/node_modules/.pnpm" -type f -name '*.musl.node' -delete
find "$app/node_modules/.pnpm" -type f -path '*/better-sqlite3/prebuilds/*musl*' -delete
makeWrapper @nodejs@/bin/node "$out/bin/aurral" \
  --add-flags "$app/backend/server.ts" \
  --prefix PATH : @mediaToolsPath@ \
  --set-default APP_VERSION @version@
runHook postInstall
