# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck

executable="$out/bin/finder-favorites"
test -x "$executable"
file "$executable" | grep -Fq 'Mach-O 64-bit arm64 executable'
otool -l "$executable" |
  grep -A4 -F 'cmd LC_BUILD_VERSION' |
  grep -Fq 'minos @minimumMacOS@'
"$executable" version | grep -Fxq 'finder-favorites @version@'
"$executable" help | grep -Fq 'finder-favorites apply --config FILE'
"$executable" doctor --json | grep -Fq '"backend" : "LSSharedFileList"'

while read -r dependency _; do
  case "$dependency" in
  /System/* | /usr/lib/*) ;;
  *)
    printf 'error: unexpected dynamic dependency: %s\n' "$dependency" >&2
    exit 1
    ;;
  esac
done < <(otool -L "$executable" | tail -n +2)

signatureInfo="$(@rcodesign@ print-signature-info "$executable")"
printf '%s\n' "$signatureInfo" |
  grep -Fq 'flags: CodeSignatureFlags(ADHOC | RUNTIME)'

runHook postInstallCheck
