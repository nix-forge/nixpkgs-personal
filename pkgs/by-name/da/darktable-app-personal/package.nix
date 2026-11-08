{
  replaceVars,
  darktable,
  lib,
  stdenvNoCC,
  python3,
}:
let
  matchedVersion = builtins.match "([0-9]+[.][0-9]+[.][0-9]+)([-+].*)?" darktable.version;
  bundleVersion =
    assert lib.assertMsg (matchedVersion != null) "Darktable requires a numeric bundle release version";
    builtins.head matchedVersion;
in
stdenvNoCC.mkDerivation {
  pname = "darktable-app-personal";
  inherit (darktable) version;
  # Upstream may provide a release archive or an unpacked Git source.
  inherit (darktable) src;
  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;
  nativeBuildInputs = [ python3 ];

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/darktable.app" --expected-version ${lib.escapeShellArg bundleVersion} --authored
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    runHook postInstallCheck
  '';

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit darktable;
        configureBundle = ./scripts/configure_bundle.py;
        version = lib.escapeShellArg bundleVersion;
        minimumMacOS = lib.escapeShellArg stdenvNoCC.hostPlatform.darwinMinVersion;
      }
    }
  '';

  meta = {
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "macOS application bundle for Darktable";
    homepage = "https://www.darktable.org/";
    inherit (darktable.meta) license;
    platforms = lib.platforms.darwin;
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "darktable.app"; };
}
