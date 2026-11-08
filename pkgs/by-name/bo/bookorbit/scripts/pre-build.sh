# shellcheck shell=bash
set -euo pipefail
python3 @scripts_materialize_swc_py@ \
  @nodejs@/bin/node \
  @swc_native_verifier@/bin/swc-native-addon-verify \
  @scripts_select_swc_cjs@ @nativePackage@ @nativeTarget@
