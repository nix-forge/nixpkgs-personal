{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  python3,
  fetchurl,
  undmg,
}:
let
  pname = "libreoffice";
  source = import ./source.nix;
  appName = "LibreOffice.app";
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.sources.${stdenvNoCC.hostPlatform.system};
  nativeBuildInputs = [ undmg ];
  sourceRoot = appName;
  strictDeps = true;
  # Preserve the vendor signature on the prebuilt application bundle.
  dontFixup = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    source ${replaceVars ./scripts/install-phase.sh { inherit appName; }}
  '';

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/LibreOffice.app" --expected-version ${lib.escapeShellArg source.version} --allow-build-suffix
  '';
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];

  meta = {
    description = "Office suite with word processing, spreadsheets and presentations";
    homepage = "https://www.libreoffice.org/";
    downloadPage = "https://www.libreoffice.org/download/download-libreoffice/";
    # The official distribution uses MPL 2.0; the bundle retains third-party notices.
    license = lib.licenses.mpl20;
    mainProgram = "libreoffice";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "LibreOffice.app"; };
}
