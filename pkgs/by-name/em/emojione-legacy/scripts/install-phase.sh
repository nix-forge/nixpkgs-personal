# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -Dm444 "$src" "$out/share/fonts/opentype/emojione-svg.otf"
install -Dm444 @upstreamLicense@ "$out/share/doc/@pname@/LICENSE.md"
install -Dm444 @adobeLicense@ "$out/share/doc/@pname@/LICENSE-ADOBE-MIT"
cat >"$out/share/doc/@pname@/README.txt" <<'EOF'
Copyright 2016 Adobe Systems Incorporated.
Emoji art supplied by EmojiOne. Original attribution: http://emojione.com
Font distributed unmodified.
Adobe's matching font: adobe-fonts/emojione-color commit
835b4ef8384f55ecf9abf7ecc943a3980884690b. All font tables match except
its added DSIG signature and the corresponding head checksum adjustment.
Source: https://github.com/joypixels/emojione/tree/@source_revision@
See LICENSE.md for upstream attribution and license terms.
This historical font is for explicit family selection, not current Unicode coverage.
EOF
runHook postInstall
