# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

workdir="$PWD/work"
install -d "$workdir" "$out/Applications" "$out/bin"

unzip -qq "$src" 'SteamMacBootstrapper.tar.gz' -d "$workdir"
tar -xzf "$workdir/SteamMacBootstrapper.tar.gz" -C "$workdir"

find "$workdir/Steam.app" -name '._*' -delete
cp -a "$workdir/Steam.app" "$out/Applications/"

# Split the literal token so replaceVars leaves it for this output-path substitution.
runtime_output_marker='@runtimeOutput'
runtime_output_marker+='@'
substitute @launcherSource@ "$out/bin/@pname@" --replace-fail "$runtime_output_marker" "$out"
chmod 0555 "$out/bin/@pname@"

runHook postInstall
