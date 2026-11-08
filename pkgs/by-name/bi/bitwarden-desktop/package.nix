{
  callPackage,
  lib,
  stdenvNoCC,
  python3,
  fetchurl,
  undmg,
}:

let
  pname = "bitwarden-desktop";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  strictDeps = true;

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;
  # Generic fixup would mutate Bitwarden's notarized application and replace
  # the stable Developer ID used by Keychain, Touch ID, and native messaging.
  dontFixup = true;

  installPhase = builtins.readFile ./scripts/install-phase.sh;

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/Bitwarden.app" --expected-version ${lib.escapeShellArg source.version}
  '';
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];

  meta = {
    description = "Password manager with encrypted vaults and cross-device synchronization";
    homepage = "https://bitwarden.com";
    downloadPage = "https://github.com/bitwarden/clients/releases";
    changelog = "https://github.com/bitwarden/clients/releases/tag/desktop-v${source.version}";
    license = lib.licenses.gpl3Only;
    mainProgram = "bitwarden";
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Bitwarden.app"; };
}
