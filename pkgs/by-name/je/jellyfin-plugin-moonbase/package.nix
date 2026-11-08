{
  replaceVars,
  callPackage,
  fetchFromGitHub,
  fetchurl,
  jq,
  lib,
  stdenvNoCC,
}:
let
  source = import ./source.nix;
  pluginSource = fetchFromGitHub {
    owner = "Moonfin-Client";
    repo = "Plugin";
    rev = source.pluginRev;
    hash = source.pluginHash;
  };
  manifestSource = fetchurl {
    url = "https://raw.githubusercontent.com/Moonfin-Client/Plugin/${source.manifestRev}/Jellyfin/manifest.json";
    hash = source.manifestHash;
  };
  server = callPackage ./server.nix { };
  web = callPackage ./web.nix { };
in
stdenvNoCC.mkDerivation {
  pname = "jellyfin-plugin-moonbase";
  inherit (source) version;
  dontUnpack = true;
  strictDeps = true;
  nativeBuildInputs = [ jq ];
  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit server;
        inherit web;
        inherit pluginSource;
        web_src = web.src;
        releaseTag = lib.escapeShellArg source.releaseTag;
        inherit manifestSource;
      }
    }
  '';
  doInstallCheck = true;
  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        targetAbi = lib.escapeShellArg source.targetAbi;
      }
    }
  '';
  meta = {
    description = "Moonbase server plugin for Moonfin clients and Seerr integration";
    homepage = "https://github.com/Moonfin-Client/Plugin";
    changelog = "https://github.com/Moonfin-Client/Plugin/releases/tag/${source.releaseTag}";
    license = [
      lib.licenses.gpl3Only
      lib.licenses.gpl2Plus
      lib.licenses.ofl
      lib.licenses.mit
      lib.licenses.bsd3
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    platforms = lib.platforms.linux;
  };
}
