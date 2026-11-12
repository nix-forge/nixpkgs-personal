# shellcheck shell=bash
# shellcheck disable=SC2154
# Compare validation-only text with the real production substitution helper.
cmp "$phase" "$renderedPhase"
cmp "$markerExpected" "$markerRendered"
preBuild() { printf 'pre\n' >>"$TMPDIR/hooks"; }
postBuild() { printf 'post\n' >>"$TMPDIR/hooks"; }
shared_values=(first)
# shellcheck source=/dev/null
source "$phase"
[[ ${shared_values[*]} == 'first second' ]]
[[ $PWD == */'directory with spaces' ]]
[[ $deferred_token == '@deferred@' ]]
printf 'pre\npost\n' >"$TMPDIR/expected-hooks"
cmp "$TMPDIR/expected-hooks" "$TMPDIR/hooks"
printf '%s' "$expected" >"$TMPDIR/expected-value"
cmp "$TMPDIR/expected-value" value.txt
printf 'file name\n%s' "$expected" >"$TMPDIR/expected-shell"
PATH=/nonexistent "$shellProbe" '/directory/file name' "$expected" >"$TMPDIR/actual-shell"
cmp "$TMPDIR/expected-shell" "$TMPDIR/actual-shell"
[[ $(PATH=/nonexistent "$pythonProbe" v1.2.0) == 1.2.0 ]]

check_scrypted() {
  local out="$TMPDIR/scrypted output"
  mkdir -p "$TMPDIR/scrypted-source"
  cd "$TMPDIR/scrypted-source" || exit
  mkdir -p dist bin python volume node_modules/classic-level/prebuilds
  printf '{}\n' >package.json
  touch node_modules/classic-level/prebuilds/vendor-binary
  # shellcheck source=/dev/null
  source "$scryptedInstall"
  test -L "$out/bin/scrypted-node"
  test ! -e "$out/lib/node_modules/@scrypted/server/node_modules/classic-level/prebuilds"
  printf '%s\n' --expose-gc "$out/lib/node_modules/@scrypted/server/dist/scrypted-main.js" "$expected" >"$TMPDIR/expected-scrypted"
  bash "$out/bin/scrypted-serve" "$expected" >"$TMPDIR/actual-scrypted"
  cmp "$TMPDIR/expected-scrypted" "$TMPDIR/actual-scrypted"
}

check_steam() {
  local out="$TMPDIR/steam output"
  local src="$TMPDIR/bootstrap.zip"
  local steam_test_home="$TMPDIR/steam-home"
  mkdir -p "$TMPDIR/steam-source"
  cd "$TMPDIR/steam-source" || exit
  mkdir -p Steam.app/Contents/MacOS
  cp "$steamBootstrapProgram" Steam.app/Contents/MacOS/steam_osx
  printf 'fixture\n' >Steam.app/Contents/Info.plist
  touch Steam.app/Contents/._discard
  tar -czf SteamMacBootstrapper.tar.gz Steam.app
  zip -q "$src" SteamMacBootstrapper.tar.gz
  # shellcheck source=/dev/null
  source "$steamInstall"
  test ! -e "$out/Applications/Steam.app/Contents/._discard"
  printf '%s\n' "$expected" >"$TMPDIR/expected-steam"
  env HOME="$steam_test_home" bash "$out/bin/steam" "$expected" >"$TMPDIR/actual-steam"
  cmp "$TMPDIR/expected-steam" "$TMPDIR/actual-steam"
}

check_scrypted
check_steam
touch "$out"
