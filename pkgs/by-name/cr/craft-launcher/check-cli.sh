# shellcheck shell=bash
# Builder-provided output path.
# shellcheck disable=SC2154
export HOME="$TMPDIR"
@launcher@ --version >"$out"
@check@ "$out" @arguments@
