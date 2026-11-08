# shellcheck shell=bash
# Allocate a fresh canonical cache inside the owned test filesystem.
# shellcheck source=/dev/null
source @environment@ || exit $?
exec cargo test --offline --locked -p swc_native_addon --test format --test integrity
