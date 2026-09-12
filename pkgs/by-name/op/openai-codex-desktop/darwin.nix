{
  unzip,
  stdenvNoCC,
  commonAttrs,
  pname,
  appName,
}:
stdenvNoCC.mkDerivation (
  commonAttrs
  // {
    nativeBuildInputs = [ unzip ];
    sourceRoot = ".";
    strictDeps = true;
    __structuredAttrs = true;

    dontPatch = true;
    dontConfigure = true;
    dontBuild = true;
    # Generic fixup would invalidate OpenAI's notarized app bundle signature.
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      install -d "$out/Applications" "$out/bin"
      cp -a "${appName}.app" "$out/Applications/"
      ln -s "$out/Applications/${appName}.app/Contents/MacOS/${appName}" \
        "$out/bin/chatgpt"
      ln -s chatgpt "$out/bin/${pname}"

      runHook postInstall
    '';
  }
)
