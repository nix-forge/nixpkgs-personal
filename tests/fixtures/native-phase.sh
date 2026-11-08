# shellcheck shell=bash
# shellcheck disable=SC2154
runHook preBuild
shared_values+=(second)
mkdir -p @directory@
cd @directory@ || exit
printf '%s' @value@ >value.txt
export deferred_token='@deferred@'
runHook postBuild
