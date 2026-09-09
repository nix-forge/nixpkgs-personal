{
  lib,
  stdenvNoCC,
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
    runHook preInstall

    install -d "$out/Applications/${appName}" "$out/bin"
    cp -R . "$out/Applications/${appName}"
    ln -s "$out/Applications/${appName}/Contents/MacOS/soffice" "$out/bin/soffice"
    ln -s "$out/bin/soffice" "$out/bin/libreoffice"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -s "$out/Applications/LibreOffice.app/Contents/Info.plist"
    test -x "$out/Applications/LibreOffice.app/Contents/MacOS/soffice"
    test -x "$out/bin/libreoffice"
    runHook postInstallCheck
  '';

  passthru.updateScript = [
    "python3"
    "pkgs/by-name/li/libreoffice/update.py"
  ];

  meta = {
    description = "Comprehensive, professional-quality productivity suite";
    homepage = "https://www.libreoffice.org/";
    downloadPage = "https://www.libreoffice.org/download/download-libreoffice/";
    # The official distribution uses MPL 2.0; the bundle retains third-party notices.
    license = lib.licenses.mpl20;
    mainProgram = "libreoffice";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
