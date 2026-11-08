# shellcheck shell=bash
# The upstream loader validates every cache ancestor. Secure only the private
# workspace owned by this Nix build; never alter a host-wide temporary directory.
swc_check_top=$(@coreutils@/bin/realpath -e -- "$NIX_BUILD_TOP")
if [ "$(@coreutils@/bin/stat -c %u -- "$swc_check_top")" != "$(@coreutils@/bin/id -u)" ]; then
  printf '%s\n' 'SWC tests require a build workspace owned by the current builder' >&2
  return 1
fi
@coreutils@/bin/chmod go-w -- "$swc_check_top"
TMPDIR=$(@coreutils@/bin/mktemp -d "$swc_check_top/swc-native-tests.XXXXXXXXXX")
# Darwin temporary ancestors can be symlinks; keep the complete test path canonical.
TMPDIR=$(@coreutils@/bin/realpath -e -- "$TMPDIR")
export TMPDIR
XDG_CACHE_HOME="$TMPDIR/cache"
export XDG_CACHE_HOME
unset swc_check_top
