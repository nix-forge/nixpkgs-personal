# shellcheck shell=bash
exec @coreutils@/bin/env -u CARGO_BUILD_TARGET @cargo@/bin/cargo "$@"
