# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -x "$out/bin/@pname@"
test -x "$out/bin/@pname@-cli"
"$out/bin/@pname@-cli" --version
test -s "$out/share/doc/@pname@/licenses/LICENSE-MIT"
