# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
app="$out/lib/node_modules/@scrypted/server"
mkdir -p "$app" "$out/bin"
cp -R dist bin python volume node_modules package.json \
  "$app/"
rm -rf \
  "$app/node_modules/@img" \
  "$app/node_modules/classic-level/prebuilds" \
  "$app/node_modules/sharp/src/build/Release/obj.target" \
  "$app/node_modules/sharp/src/build/Release/.deps" \
  "$app/node_modules/classic-level/build/Release/obj.target" \
  "$app/node_modules/classic-level/build/Release/.deps" \
  "$app/node_modules/@scrypted/node-pty/build/Release/obj.target"
rm -f "$app/node_modules/classic-level/build/Release/"*.a
rm -f "$app/node_modules/sharp/src/build/Release/node-addon-api/"*.o
ln -s @nodejs_24@/bin/node "$out/bin/scrypted-node"
# Split the literal token so replaceVars leaves it for this output-path substitution.
runtime_output_marker='@runtimeOutput'
runtime_output_marker+='@'
substitute @launcherSource@ "$out/bin/scrypted-serve" --replace-fail "$runtime_output_marker" "$out"
chmod +x "$out/bin/scrypted-serve"
runHook postInstall
