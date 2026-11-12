# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
if [ "$version" != 1.7.0 ]; then
  echo "Review the authentication UX patch for noctalia-greeter $version" >&2
  exit 1
fi
