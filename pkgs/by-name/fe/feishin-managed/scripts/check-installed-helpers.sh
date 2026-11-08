# shellcheck shell=bash
# Nix supplies the installed output and platform-specific helper list.
# shellcheck disable=SC2154
archive=$(find "$out" -name app.asar -print -quit)
test -n "$archive"
mkdir feishin-installed-helpers
(
  cd feishin-installed-helpers || exit 1
  darwin_helpers=(@darwinHelpers@)
  for helper in managed-login managed-login-renderer mpv-readiness mpv-message "${darwin_helpers[@]}"; do
    asar extract-file "$archive" "out/main/$helper.cjs"
  done
  # Load the installed entrypoints, resolving their adjacent dependencies.
  # Compiling and testing the original helper directory cannot detect omissions
  # from the application's final archive.
  node -e 'require("./managed-login.cjs"); require("./mpv-readiness.cjs")'
  for helper in "${darwin_helpers[@]}"; do
    node --check "./$helper.cjs"
    # Now Playing imports Electron's live host API at module scope. The other
    # helpers can be loaded in Node and verify its packaged dependencies.
    if [[ $helper != mpv-now-playing ]]; then
      node -e 'require(process.argv[1])' "./$helper.cjs"
    fi
  done
)
