# shellcheck shell=bash
# shellcheck disable=SC2154
runHook preInstallCheck
app="$out/Applications/Rift.app"
python3 @checkRiftBundle@ "$app" "$version"
# rcodesign's verify command rejects valid ad-hoc signatures as missing CMS.
# Inspect declared signature data here; Apple's full verification is a native
# post-build check on the copied bundle, outside Nix's host-tool restrictions.
signatureInfo="$(rcodesign print-signature-info "$app/Contents/MacOS/rift")"
printf '%s\n' "$signatureInfo" | grep -Fq 'flags: CodeSignatureFlags(ADHOC'
printf '%s\n' "$signatureInfo" | grep -Fq 'identifier: git.acsandmann.rift'
signatureInfo="$(rcodesign print-signature-info "$out/bin/rift-cli")"
printf '%s\n' "$signatureInfo" | grep -Fq 'flags: CodeSignatureFlags(ADHOC'
printf '%s\n' "$signatureInfo" | grep -Fq 'identifier: rift-cli'
test "$("$out/bin/rift" --version)" = "rift $version"
test "$("$out/bin/rift-cli" --version)" = "rift-cli $version"
"$out/bin/rift-cli" execute workspace --help | grep -F move-window
test -s "$out/share/doc/rift/LICENSE"
runHook postInstallCheck
