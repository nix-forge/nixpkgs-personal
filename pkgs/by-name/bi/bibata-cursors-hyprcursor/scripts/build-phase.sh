# shellcheck shell=bash
runHook preBuild

export HOME="$TMPDIR/home"
mkdir -p "$HOME" build

build_theme() {
  @python3_interpreter@ src/cursor_utils.py \
    --hypr \
    --x11 \
    --theme "$1" \
    --out-dir "build/$1"
}

# `NIX_BUILD_CORES` is calculated by the client.  It can therefore reflect
# a macOS host rather than the CPU allocation of an external Linux builder.
# Use the actual build environment as the upper bound, then respect a
# lower Nix-provided limit. This avoids overcommitting Determinate Nix's
# default one-vCPU Linux VM while retaining parallel generation on native
# multi-core Linux builders.
max_jobs="$(@coreutils@/bin/nproc)"
if [ -n "${NIX_BUILD_CORES:-}" ] && [ "$NIX_BUILD_CORES" -gt 0 ] && [ "$NIX_BUILD_CORES" -lt "$max_jobs" ]; then
  max_jobs="$NIX_BUILD_CORES"
fi
pids=()
@buildThemes@
# Waiting without a PID can hide a failed worker's exit status.
for pid in "${pids[@]}"; do
  wait "$pid"
done

runHook postBuild
