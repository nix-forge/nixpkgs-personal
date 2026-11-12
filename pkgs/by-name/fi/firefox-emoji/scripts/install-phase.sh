# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -Dm444 "$src" "$out/share/fonts/truetype/FirefoxEmoji.ttf"
install -Dm444 @upstreamLicense@ "$out/share/doc/@pname@/LICENSE.md"
install -Dm444 @apacheLicense@ "$out/share/doc/@pname@/Apache-2.0.txt"
cat >"$out/share/doc/@pname@/README.txt" <<'EOF'
Firefox Emoji artwork by Mozilla Foundation. Font distributed unmodified.
Source: https://github.com/mozilla/fxemoji/tree/@source_revision@
See LICENSE.md for upstream attribution and license terms.
This historical font is for explicit family selection, not current Unicode coverage.
EOF
runHook postInstall
