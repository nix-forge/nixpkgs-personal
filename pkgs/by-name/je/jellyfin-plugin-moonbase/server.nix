{
  buildDotnetModule,
  dotnetCorePackages,
  fetchFromGitHub,
}:
let
  source = import ./source.nix;
in
buildDotnetModule {
  pname = "moonbase-server";
  inherit (source) version;
  src = fetchFromGitHub {
    owner = "Moonfin-Client";
    repo = "Plugin";
    rev = source.pluginRev;
    hash = source.pluginHash;
  };
  projectFile = "Jellyfin/backend/Moonfin.Server.csproj";
  nugetDeps = ./deps.json;
  dotnet-sdk = dotnetCorePackages.sdk_8_0;
  dotnet-runtime = dotnetCorePackages.runtime_8_0;
  dotnetBuildFlags = [
    "-p:AssemblyVersion=${source.version}"
    "-p:FileVersion=${source.version}"
    "-p:Version=${source.version}"
  ];
  executables = [ ];
  strictDeps = true;
  installPhase = builtins.readFile ./scripts/server-install-phase.sh;
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/server-install-check-phase.sh;
}
