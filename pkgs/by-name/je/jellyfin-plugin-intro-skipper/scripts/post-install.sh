# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
install -Dm444 "$out/lib/@pname@/IntroSkipper.dll" \
  "$out/IntroSkipper.dll"
# Jellyfin provides its own assemblies. Match the upstream release's
# single-DLL payload when copying this package into the plugin directory.
rm -r "${out:?}/lib"
install -Dm444 LICENSE "$out/share/doc/@pname@/LICENSE"
