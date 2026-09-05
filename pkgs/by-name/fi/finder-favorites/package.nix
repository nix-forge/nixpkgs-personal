{
  coreutils,
  file,
  findutils,
  gnugrep,
  lib,
  rcodesign,
  swiftPackages,
}:

let
  inherit (swiftPackages) stdenv swift;
  version = "0.1.0";
  minimumMacOS = "14.0";
in
assert lib.assertMsg (lib.versionAtLeast swift.version "5.10")
  "finder-favorites requires Swift 5.10 or newer";
stdenv.mkDerivation {
  pname = "finder-favorites";
  inherit version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Package.swift
      ./.clang-format
      ./.clang-tidy
      ./.periphery.yml
      ./.swift-format
      ./.swiftlint.yml
      ./LICENSE
      ./README.md
      ./Scripts
      ./Sources
      ./Tests
    ];
  };

  nativeBuildInputs = [
    coreutils
    file
    findutils
    gnugrep
    rcodesign
    swift
    swiftPackages.swiftpm
  ];
  strictDeps = true;
  MACOSX_DEPLOYMENT_TARGET = minimumMacOS;
  NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = 1;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # Nix's SwiftPM 5.10 evaluates manifests with its macOS 12 host triple,
    # while the packaged Swift runtime targets macOS 14. Quiet mode hides that
    # toolchain-only linker noise. All project diagnostics remain errors below.
    swift package --quiet \
      --cache-path "$TMPDIR/swift-cache" \
      --config-path "$TMPDIR/swift-config" \
      --security-path "$TMPDIR/swift-security" \
      dump-package >/dev/null

    swift build \
      --quiet \
      --disable-sandbox \
      --cache-path "$TMPDIR/swift-cache" \
      --config-path "$TMPDIR/swift-config" \
      --security-path "$TMPDIR/swift-security" \
      --scratch-path "$TMPDIR/swift-build" \
      -c release \
      --explicit-target-dependency-import-check error \
      -Xcc -Wall \
      -Xcc -Wextra \
      -Xcc -Wpedantic \
      -Xcc -Wconversion \
      -Xcc -Wsign-conversion \
      -Xcc -Wcast-qual \
      -Xcc -Wformat=2 \
      -Xcc -Wnull-dereference \
      -Xcc -Wshadow \
      -Xcc -Wstrict-prototypes \
      -Xcc -Wmissing-prototypes \
      -Xcc -Wnullability-completeness \
      -Xcc -Werror \
      -Xcc -Wno-newline-eof \
      -Xcc -Wno-nullability-extension \
      -Xswiftc -swift-version \
      -Xswiftc 5 \
      -Xswiftc -strict-concurrency=complete \
      -Xswiftc -warnings-as-errors

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    # Nix's Darwin Swift distribution omits XCTest. This release-built harness
    # exercises the same in-memory backend without touching the live sidebar.
    "$TMPDIR/swift-build/release/finder-favorites-selftest" \
      | grep -Fxq 'finder-favorites self-test passed'

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 "$TMPDIR/swift-build/release/finder-favorites" \
      "$out/bin/finder-favorites"
    install -Dm644 README.md "$out/share/doc/finder-favorites/README.md"
    install -Dm644 LICENSE "$out/share/doc/finder-favorites/LICENSE"

    runHook postInstall
  '';

  postFixup = ''
    ${lib.getExe rcodesign} sign \
      --code-signature-flags runtime \
      "$out/bin/finder-favorites"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    executable="$out/bin/finder-favorites"
    test -x "$executable"
    file "$executable" | grep -Fq 'Mach-O 64-bit arm64 executable'
    otool -l "$executable" \
      | grep -A4 -F 'cmd LC_BUILD_VERSION' \
      | grep -Fq 'minos ${minimumMacOS}'
    "$executable" version | grep -Fxq 'finder-favorites ${version}'
    "$executable" help | grep -Fq 'finder-favorites apply --config FILE'
    "$executable" doctor --json | grep -Fq '"backend" : "LSSharedFileList"'

    while read -r dependency _; do
      case "$dependency" in
        /System/* | /usr/lib/*) ;;
        *)
          printf 'error: unexpected dynamic dependency: %s\n' "$dependency" >&2
          exit 1
          ;;
      esac
    done < <(otool -L "$executable" | tail -n +2)

    signatureInfo="$(${lib.getExe rcodesign} print-signature-info "$executable")"
    printf '%s\n' "$signatureInfo" \
      | grep -Fq 'flags: CodeSignatureFlags(ADHOC | RUNTIME)'

    runHook postInstallCheck
  '';

  meta = {
    description = "Transactional declarative manager for macOS Finder Favorites";
    homepage = "https://github.com/ianmh/nixpkgs-personal";
    license = lib.licenses.mit;
    mainProgram = "finder-favorites";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
