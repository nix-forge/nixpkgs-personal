{
  callPackage,
  replaceVars,
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
  jq,
  lib,
  yq-go,
}:
let
  source = import ./source.nix;
in
buildDotnetModule (finalAttrs: {
  pname = "jellyfin-plugin-subtitle-extract";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "jellyfin";
    repo = "jellyfin-plugin-subtitleextract";
    rev = source.sourceRev;
    hash = source.sourceHash;
  };
  projectFile = "Jellyfin.Plugin.SubtitleExtract/Jellyfin.Plugin.SubtitleExtract.csproj";
  nugetDeps = ./deps.json;
  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.runtime_10_0;
  executables = [ ];
  strictDeps = true;
  nativeBuildInputs = [
    jq
    yq-go
  ];

  postInstall = ''
    source ${
      replaceVars ./scripts/post-install.sh {
        inherit (finalAttrs) pname;
        releaseTimestamp = lib.escapeShellArg source.releaseTimestamp;
      }
    }
  '';

  doInstallCheck = true;
  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];
  nativeInstallCheckInputs = [ jq ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        targetAbi = lib.escapeShellArg source.targetAbi;
      }
    }
  '';

  meta = {
    description = "Plugin for extracting embedded subtitles in Jellyfin";
    homepage = "https://github.com/jellyfin/jellyfin-plugin-subtitleextract";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = lib.platforms.linux;
  };
})
