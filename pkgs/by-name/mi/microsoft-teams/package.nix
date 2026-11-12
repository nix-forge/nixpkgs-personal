{
  callPackage,
  lib,
  stdenvNoCC,
  python3,
  fetchurl,
  xar,
  pbzx,
  cpio,
}:

let
  pname = "microsoft-teams";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [
    xar
    pbzx
    cpio
  ];

  strictDeps = true;
  # Preserve the vendor signature on the prebuilt application bundle.
  dontFixup = true;

  unpackPhase = builtins.readFile ./scripts/unpack-phase.sh;

  dontPatch = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = builtins.readFile ./scripts/install-phase.sh;

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/Microsoft Teams.app" --expected-version ${lib.escapeShellArg source.version}
  '';
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];

  meta = {
    description = "Messaging, meetings and collaboration client";
    homepage = "https://teams.microsoft.com";
    downloadPage = "https://teams.microsoft.com/downloads";
    license = lib.licenses.unfree;
    mainProgram = "teams";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Microsoft Teams.app"; };
}
