# shellcheck shell=bash
# Nix builds cannot reuse this workspace's incremental test artifacts.
# Keep debug assertions, without large disposable symbol/incremental files.
export CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
export HOME="$TMPDIR/home"
mkdir -p "$HOME"
