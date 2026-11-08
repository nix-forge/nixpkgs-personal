{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  python3,
  fetchurl,
  unzip,
}:

let
  pname = "claude-desktop";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  strictDeps = true;
  # Preserve the vendor signature on the prebuilt application bundle.
  dontFixup = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit pname; }}
  '';

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/Claude.app" --expected-version ${lib.escapeShellArg source.version}
  '';
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];

  meta = {
    description = "Anthropic's official Claude AI desktop app";
    homepage = "https://claude.com/download";
    license = lib.licenses.unfree;
    mainProgram = "claude-desktop";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Claude.app"; };
}
