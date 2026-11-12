# shellcheck shell=bash
# Nix provides builder variables and the rendered Rust environment.
# shellcheck disable=SC2154
runHook preBuild
export CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
export HOME="$TMPDIR/home"
mkdir -p "$HOME"
@cargoEnvironment@ cargo test --offline --locked --no-run --lib --package @crate@ \
  --target @rustTarget@ --jobs "$NIX_BUILD_CORES" --message-format=json \
  >native-host-tests.json
runHook postBuild
