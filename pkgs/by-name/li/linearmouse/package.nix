{
  callPackage,
  lib,
  stdenvNoCC,
  python3,
  fetchurl,
  _7zz,
}:

let
  pname = "linearmouse";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ _7zz ];
  strictDeps = true;

  # LinearMouse's DMG contains APFS rather than HFS, so undmg cannot unpack it.
  # Suppress NTFS/APFS alternate streams as 7-Zip would otherwise materialize a
  # quarantine stream as an Info.plist:com.apple.quarantine file and invalidate
  # the embedded LaunchAtLogin helper's signature.
  unpackPhase = builtins.readFile ./scripts/unpack-phase.sh;

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # Any generic mutation of this bundle would invalidate its notarized
  # Developer ID signature and make its TCC identity less stable.
  dontFixup = true;

  installPhase = builtins.readFile ./scripts/install-phase.sh;

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/LinearMouse.app" --expected-version ${lib.escapeShellArg source.version}
  '';
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;

  passthru = {
    configurationSchema = fetchurl source.configurationSchema;
    configurationSchemaVersion = source.version;
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
  };

  meta = {
    description = "Customizable mouse and trackpad utility for macOS";
    homepage = "https://linearmouse.app/";
    downloadPage = "https://github.com/linearmouse/linearmouse/releases";
    changelog = "https://github.com/linearmouse/linearmouse/releases/tag/v${source.version}";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "LinearMouse.app"; };
}
