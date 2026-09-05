#!/usr/bin/env bash
set -euo pipefail

package_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$package_root"

xcrun swift-format lint --configuration .swift-format --parallel --strict --recursive Sources Tests
swiftlint lint --no-cache --strict --config .swiftlint.yml
swift test --parallel
swift test -Xswiftc -strict-memory-safety
swift test -Xswiftc -D -Xswiftc OCR_CAPTURE_NIX_BUILD
periphery scan --clean-build

if [[ ${OCR_CAPTURE_RUN_SANITIZERS:-1} == 1 ]]; then
  swift test --sanitize address
  swift test --sanitize thread
fi
