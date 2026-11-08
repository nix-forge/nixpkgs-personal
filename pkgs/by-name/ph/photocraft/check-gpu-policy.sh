# shellcheck shell=bash
# Nix supplies the target, compile mode and bounded build variables.
# shellcheck disable=SC2154
export CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
export HOME="$TMPDIR/gpu-policy-home"
mkdir -p "$HOME"
policy_args=()
if [[ $ARTCRAFT_GPU_POLICY_COMPILE_ONLY == 1 ]]; then
  policy_args+=(--no-run)
fi
cargo test --offline --target "$ARTCRAFT_RUST_TARGET" -j "$NIX_BUILD_CORES" \
  -p photocraft --bin photocraft "${policy_args[@]}" \
  gpu_startup::tests::intel_macs_skip_the_indirect_validation_shaders -- --exact
