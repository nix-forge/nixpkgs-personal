{
  lib,
  stdenv,
  fetchurl,
  callPackage,
  extraPackages ? [ ],
}:

let
  pname = "openai-codex-desktop";
  source = import ./source.nix;
  inherit (stdenv.hostPlatform) system;
  sourceForSystem =
    source.sources.${system} or (throw "${pname} does not provide an upstream artifact for ${system}");
  src = fetchurl {
    inherit (sourceForSystem) url hash;
    name = "${pname}-${sourceForSystem.version}-${system}.${
      if stdenv.hostPlatform.isDarwin then "zip" else "deb"
    }";
  };
  meta = {
    description = "OpenAI desktop app with ChatGPT, Work, and Codex";
    longDescription = ''
      OpenAI's unified desktop application. It includes ChatGPT, Work, and the
      Codex interface for local and cloud software-development tasks.
    '';
    homepage = "https://chatgpt.com/download/";
    downloadPage = "https://chatgpt.com/download/";
    changelog = "https://help.openai.com/en/articles/6825453-chatgpt-release-notes";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = builtins.attrNames source.sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
  passthru = {
    inherit (source) appName;
    inherit sourceForSystem;
    updateScript = [
      "python3"
      "pkgs/by-name/op/openai-codex-desktop/update.py"
    ];
  };
  commonAttrs = {
    inherit
      pname
      src
      meta
      passthru
      ;
    inherit (sourceForSystem) version;
  };
in
if stdenv.hostPlatform.isDarwin then
  callPackage ./darwin.nix {
    inherit pname commonAttrs;
    inherit (source) appName;
  }
else
  callPackage ./linux.nix { inherit pname commonAttrs extraPackages; }
