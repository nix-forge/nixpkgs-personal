# shellcheck shell=bash
[[ -o errexit && -o nounset && -o pipefail ]]
basename -- "$1"
printf '%s' "$2"
