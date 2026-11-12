{
  replaceVars,
  coreutils,
  file,
  findutils,
  gnugrep,
  lib,
  fetchFromGitHub,
  rcodesign,
  stdenv,
  swift,
  swiftpm,
}:

let
  version = "0.1.0";
  minimumMacOS = "14.0";
in
assert lib.assertMsg (lib.versionAtLeast swift.version "5.10")
  "finder-favorites requires Swift 5.10 or newer";
stdenv.mkDerivation {
  pname = "finder-favorites";
  inherit version;

  src = fetchFromGitHub {
    owner = "IanHollow";
    repo = "finder-favorites";
    rev = "d35623e32ee6597d2018dd0d9c80ecb09db360cf";
    hash = "sha256-oTWZoFPBg2jpBQai1RUpapuGme+yRRmpvOgNdAwjyzE=";
  };
  nativeBuildInputs = [
    coreutils
    file
    findutils
    gnugrep
    rcodesign
    swift
    swiftpm
  ];
  strictDeps = true;
  MACOSX_DEPLOYMENT_TARGET = minimumMacOS;
  # SwiftPM must compile with the caller-selected Swift, including overrides.
  SWIFT_EXEC = "${swift}/bin/swiftc";
  NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = 1;

  dontConfigure = true;
  # Nix exports list attributes as scalar strings; the hook splits this string
  # into flags, while swiftpmFlagsArray requires a shell array.
  swiftpmFlags = lib.concatStringsSep " " [
    "--explicit-target-dependency-import-check"
    "error"
    "-Xcc"
    "-Wall"
    "-Xcc"
    "-Wextra"
    "-Xcc"
    "-Wpedantic"
    "-Xcc"
    "-Wconversion"
    "-Xcc"
    "-Wsign-conversion"
    "-Xcc"
    "-Wcast-qual"
    "-Xcc"
    "-Wformat=2"
    "-Xcc"
    "-Wnull-dereference"
    "-Xcc"
    "-Wshadow"
    "-Xcc"
    "-Wstrict-prototypes"
    "-Xcc"
    "-Wmissing-prototypes"
    "-Xcc"
    "-Wnullability-completeness"
    "-Xcc"
    "-Werror"
    "-Xcc"
    "-Wno-newline-eof"
    "-Xcc"
    "-Wno-nullability-extension"
    "-Xswiftc"
    "-swift-version"
    "-Xswiftc"
    "5"
    "-Xswiftc"
    "-strict-concurrency=complete"
    "-Xswiftc"
    "-warnings-as-errors"
  ];

  doCheck = true;
  checkPhase = builtins.readFile ./scripts/check-phase.sh;

  installPhase = builtins.readFile ./scripts/install-phase.sh;

  postFixup = ''
    source ${
      replaceVars ./scripts/post-fixup.sh {
        rcodesign = lib.getExe rcodesign;
      }
    }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit minimumMacOS;
        inherit version;
        rcodesign = lib.getExe rcodesign;
      }
    }
  '';

  meta = {
    description = "Transactional declarative manager for macOS Finder Favorites";
    homepage = "https://github.com/IanHollow/finder-favorites";
    license = lib.licenses.mit;
    mainProgram = "finder-favorites";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
