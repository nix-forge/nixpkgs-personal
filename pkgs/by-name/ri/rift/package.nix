{
  lib,
  stdenvNoCC,
  rustPlatform,
  fetchFromGitHub,
  apple-sdk,
  replaceVars,
  rcodesign,
  python3,
  writeText,
}:
let
  source = import ./source.nix;
  # Keep compilation and upstream unit tests independent of bundle metadata and
  # install checks so changing the wrapper does not rebuild the Rust workspace.
  unwrapped = rustPlatform.buildRustPackage {
    pname = "rift-unwrapped";
    inherit (source) version cargoHash;
    cargoDepsName = "rift-${source.version}";
    src = fetchFromGitHub source.src;
    strictDeps = true;
    nativeBuildInputs = [ apple-sdk ];
    cargoBuildFlags = [
      "--package"
      "rift-wm"
      "--bin"
      "rift"
      "--bin"
      "rift-cli"
    ];
    # The reactor/space fixtures fall through to live SkyLight queries and abort
    # without a graphical session on macOS 26. Run the independent headless suites
    # in the sandbox; verify real windows through the installed app separately.
    doCheck = true;
    cargoTestFlags = [ "--lib" ];
    checkFlags = [
      # libtest filters are substrings: actor::gesture:: also matches
      # reactor::gesture::. Explicitly fence the session-dependent module.
      "--skip=actor::reactor::"
      "common::"
      "layout_engine::"
      "model::"
      "actor::config::"
      "actor::input::"
      "actor::drag::"
      "actor::gesture::"
      "actor::raise_manager::"
    ];
    dontFixup = true;
    installPhase = builtins.readFile ./scripts/install-unwrapped-phase.sh;
    meta = {
      description = "Rift window manager and IPC client without the application bundle";
      homepage = "https://github.com/acsandmann/rift";
      license = lib.licenses.asl20;
      platforms = lib.platforms.darwin;
      mainProgram = "rift";
      sourceProvenance = [ lib.sourceTypes.fromSource ];
    };
  };
  validationSource = lib.fileset.toSource {
    root = ./scripts;
    fileset = lib.fileset.unions [
      ./scripts/check_app_bundle.py
      ./scripts/check_rift_bundle.py
    ];
  };
  infoPlist = writeText "Rift-Info.plist" (
    lib.generators.toPlist { escape = true; } {
      CFBundleDevelopmentRegion = "en";
      CFBundleExecutable = "rift";
      CFBundleIdentifier = "git.acsandmann.rift";
      CFBundleInfoDictionaryVersion = "6.0";
      CFBundleName = "Rift";
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = source.version;
      CFBundleVersion = source.version;
      LSMinimumSystemVersion = stdenvNoCC.hostPlatform.darwinMinVersion;
      LSUIElement = true;
      NSHighResolutionCapable = true;
      NSScreenCaptureUsageDescription = "Rift optionally captures window previews while Overview is open.";
    }
  );
in
stdenvNoCC.mkDerivation {
  pname = "rift";
  inherit (source) version;
  strictDeps = true;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;
  nativeBuildInputs = [ rcodesign ];
  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit unwrapped infoPlist; }}
  '';
  nativeInstallCheckInputs = [ python3 ];
  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        checkRiftBundle = "${validationSource}/check_rift_bundle.py";
      }
    }
  '';
  passthru = { inherit unwrapped; };

  meta = {
    description = "Tiling window manager for macOS with native workspace and layout controls";
    homepage = "https://github.com/acsandmann/rift";
    changelog = "https://github.com/acsandmann/rift/releases/tag/v${source.version}";
    license = lib.licenses.asl20;
    platforms = lib.platforms.darwin;
    mainProgram = "rift";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Rift.app"; };
}
