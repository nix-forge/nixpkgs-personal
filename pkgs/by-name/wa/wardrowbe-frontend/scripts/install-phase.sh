# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
app="$out/libexec/wardrowbe-frontend"
mkdir -p "$app/.next" "$out/bin"
cp -R .next/standalone/. "$app/"
cp -R .next/static "$app/.next/static"
cp -R public messages "$app/"
mkdir -p "$out/share/doc/wardrowbe"
cp ../LICENSE "$out/share/doc/wardrowbe/LICENSE"
cp @inter_src@/LICENSE.txt "$out/share/doc/wardrowbe/Inter-LICENSE.txt"
makeWrapper @nodejs_24@/bin/node "$out/bin/wardrowbe-frontend" \
  --add-flags "$app/server.js" \
  --set-default NODE_ENV production \
  --set-default NEXT_TELEMETRY_DISABLED 1
runHook postInstall
