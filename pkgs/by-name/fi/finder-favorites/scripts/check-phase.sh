# shellcheck shell=bash
runHook preCheck

# This release-built harness exercises the in-memory backend without
# touching the live sidebar.
"$(swiftpmBinPath)/finder-favorites-selftest" |
  grep -Fxq 'finder-favorites self-test passed'

runHook postCheck
