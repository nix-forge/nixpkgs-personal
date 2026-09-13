{
  stdenvNoCC,
  fetchurl,
  unzip,
  commonAttrs,
  source,
}:
stdenvNoCC.mkDerivation (
  commonAttrs
  // {
    src = fetchurl source.darwin;

    nativeBuildInputs = [ unzip ];
    sourceRoot = ".";
    strictDeps = true;
    dontBuild = true;
    dontConfigure = true;
    # The official bundle is signed and notarized. Generic fixup would mutate
    # its contents and invalidate that identity without improving Darwin runtime
    # compatibility.
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      install -d "$out/Applications" "$out/bin"
      cp -a "${source.appName}.app" "$out/Applications/"
      ln -s "$out/Applications/${source.appName}.app/Contents/MacOS/${source.appName}" "$out/bin/${commonAttrs.pname}"

      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test -s "$out/Applications/${source.appName}.app/Contents/Info.plist"
      test -x "$out/Applications/${source.appName}.app/Contents/MacOS/${source.appName}"
      test -x "$out/bin/${commonAttrs.pname}"
      runHook postInstallCheck
    '';
  }
)
