# shellcheck shell=bash
# Cargo's normal Nix setup and declared vendor tree remain active in postCheck.
@cargoEnvironment@ cargo test --offline --locked --package lightcraft-codecs --test heif \
  --features heif --target @rustTarget@ --jobs "${NIX_BUILD_CORES:-1}"
