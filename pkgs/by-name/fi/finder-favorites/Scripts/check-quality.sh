#!/usr/bin/env bash
set -euo pipefail

package_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$package_root"

required_commands=(
  bash clang clang-format clang-tidy deadnix jq nix-instantiate nixf-diagnose
  nixfmt periphery prettier rumdl shellcheck shfmt statix swift swift-format
  swiftlint typos yamlfmt yamllint xcrun
)
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'error: required quality tool is unavailable: %s\n' "$command_name" >&2
    exit 127
  fi
done

swift_sources=(Sources Tests Package.swift)
c_sources=(
  Sources/FinderFavoritesBridge/FinderFavoritesBridge.c
  Sources/FinderFavoritesBridge/include/FinderFavoritesBridge.h
)
yaml_sources=(.periphery.yml .swiftlint.yml)
clang_yaml_sources=(.clang-format .clang-tidy)

swift-format lint \
  --configuration .swift-format \
  --parallel \
  --recursive \
  --strict \
  "${swift_sources[@]}"
swiftlint lint --no-cache --strict --config .swiftlint.yml

clang-format --dry-run --Werror --style=file "${c_sources[@]}"
sdk_path=$(xcrun --sdk macosx --show-sdk-path)
c_flags=(
  -x c
  -std=c17
  -fblocks
  -isysroot "$sdk_path"
  -mmacosx-version-min=14.0
  -I Sources/FinderFavoritesBridge/include
  -Weverything
  -Werror
  -Wno-covered-switch-default
  -Wno-poison-system-directories
  -Wno-declaration-after-statement
  -Wno-implicit-void-ptr-cast
  -Wno-nullability-extension
  -Wno-padded
  -Wno-unsafe-buffer-usage
  -Wno-unused-command-line-argument
)
clang -fsyntax-only "${c_flags[@]}" Sources/FinderFavoritesBridge/FinderFavoritesBridge.c
clang --analyze -Xanalyzer -analyzer-output=text -o /dev/null \
  "${c_flags[@]}" Sources/FinderFavoritesBridge/FinderFavoritesBridge.c
clang-tidy \
  --quiet \
  Sources/FinderFavoritesBridge/FinderFavoritesBridge.c \
  --config-file=.clang-tidy \
  -- \
  "${c_flags[@]}"

bash -n Scripts/check-quality.sh
shellcheck --shell=bash --severity=style Scripts/check-quality.sh
shfmt -d -i 2 Scripts/check-quality.sh

nixfmt --check package.nix
statix check package.nix
deadnix --fail package.nix
nixf-diagnose package.nix
nix-instantiate --parse package.nix >/dev/null

yamlfmt -lint "${yaml_sources[@]}"
prettier --check --parser yaml "${clang_yaml_sources[@]}"
yamllint --strict \
  -d '{extends: default, rules: {document-start: disable, line-length: {max: 160}}}' \
  "${yaml_sources[@]}" \
  "${clang_yaml_sources[@]}"
prettier --check --parser json .swift-format
jq -e . .swift-format >/dev/null
rumdl fmt --check README.md
rumdl check README.md
typos --format brief \
  Package.swift README.md Scripts Sources Tests package.nix \
  .clang-format .clang-tidy .periphery.yml .swift-format .swiftlint.yml

swift package dump-package >/dev/null
scratch_root=$(mktemp -d "${TMPDIR:-/tmp}/finder-favorites-quality.XXXXXX")
trap 'rm -rf -- "$scratch_root"' EXIT

swift_build_flags=(
  --disable-sandbox
  --explicit-target-dependency-import-check error
  -Xswiftc -strict-concurrency=complete
  -Xswiftc -warnings-as-errors
  -Xcc -Wall
  -Xcc -Wextra
  -Xcc -Wpedantic
  -Xcc -Wconversion
  -Xcc -Wsign-conversion
  -Xcc -Wcast-qual
  -Xcc -Wformat=2
  -Xcc -Wnull-dereference
  -Xcc -Wshadow
  -Xcc -Wstrict-prototypes
  -Xcc -Wmissing-prototypes
  -Xcc -Wnullability-completeness
  -Xcc -Werror
  -Xcc -Wno-newline-eof
  -Xcc -Wno-nullability-extension
)
swift build \
  --scratch-path "$scratch_root/swift-5" \
  "${swift_build_flags[@]}" \
  -Xswiftc -swift-version \
  -Xswiftc 5
swift test \
  --parallel \
  --scratch-path "$scratch_root/swift-5-tests" \
  "${swift_build_flags[@]}" \
  -Xswiftc -swift-version \
  -Xswiftc 5
swift build \
  --scratch-path "$scratch_root/swift-6" \
  "${swift_build_flags[@]}" \
  -Xswiftc -swift-version \
  -Xswiftc 6

periphery scan --clean-build --config .periphery.yml

if [[ ${FINDER_FAVORITES_RUN_SANITIZERS:-1} == 1 ]]; then
  swift test \
    --parallel \
    --scratch-path "$scratch_root/address-sanitizer" \
    --sanitize address
  swift test \
    --parallel \
    --scratch-path "$scratch_root/thread-sanitizer" \
    --sanitize thread
fi
