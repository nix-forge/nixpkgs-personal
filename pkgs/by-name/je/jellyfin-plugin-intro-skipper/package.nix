{
  replaceVars,
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
  fetchPnpmDeps,
  lib,
  nodejs_24,
  pnpm_11,
  pnpmConfigHook,
}:
let
  source = import ./source.nix;
in
buildDotnetModule (finalAttrs: {
  pname = "jellyfin-plugin-intro-skipper";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "intro-skipper";
    repo = "intro-skipper";
    inherit (source) rev;
    hash = source.sourceHash;
  };
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    sourceRoot = "${finalAttrs.src.name}/web";
    fetcherVersion = 4;
    hash = source.pnpmHash;
  };
  pnpmRoot = "web";
  projectFile = "IntroSkipper/IntroSkipper.csproj";
  nugetDeps = ./deps.json;
  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.runtime_10_0;
  dotnetFlags = [ "-p:SkipWebBuild=true" ];
  executables = [ ];
  strictDeps = true;
  nativeBuildInputs = [
    nodejs_24
    pnpm_11
    pnpmConfigHook
  ];

  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        inherit (finalAttrs) version;
        source_rev = source.rev;
      }
    }
  '';

  preBuild = builtins.readFile ./scripts/pre-build.sh;

  postInstall = ''
    source ${
      replaceVars ./scripts/post-install.sh {
        inherit (finalAttrs) pname;
      }
    }
  '';

  meta = {
    description = "Plugin for detecting introduction and credit segments in Jellyfin";
    homepage = "https://github.com/intro-skipper/intro-skipper";
    changelog = "https://github.com/intro-skipper/intro-skipper/releases/tag/12.0%2Fv${finalAttrs.version}";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = lib.platforms.linux;
  };
})
