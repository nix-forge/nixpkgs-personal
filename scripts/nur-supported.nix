{ nixpkgsPath, repositoryPath }:
let
  licenseMetadata = import ./license-metadata.nix;
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
  forSystem =
    system:
    let
      pkgs = import nixpkgsPath {
        inherit system;
        config = {
          allowUnfree = true;
          checkMeta = true;
        };
      };
      packages = import repositoryPath { inherit pkgs; };
      supported = pkgs.lib.filterAttrs (
        _: package:
        pkgs.lib.isDerivation package && pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform package
      ) packages;
    in
    pkgs.lib.mapAttrs (
      name: package:
      let
        licenses = pkgs.lib.toList (package.meta.license or null);
        unfree = pkgs.lib.any (license: !licenseMetadata.isFree license) licenses;
      in
      if !(package.meta ? license) then
        throw "${name}: missing package license"
      else if unfree && !(package.meta ? sourceProvenance) then
        throw "${name}: unfree packages must declare source provenance"
      else
        package.drvPath
    ) supported;
in
builtins.listToAttrs (
  map (system: {
    name = system;
    value = forSystem system;
  }) systems
)
