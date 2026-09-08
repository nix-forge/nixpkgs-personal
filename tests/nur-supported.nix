{ nixpkgsPath, repositoryPath }:
let
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
        config.allowUnfree = true;
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
        unfree = pkgs.lib.any (license: builtins.isAttrs license && !(license.free or true)) licenses;
      in
      assert pkgs.lib.assertMsg (package.meta ? license) "${name}: missing package license";
      assert pkgs.lib.assertMsg (
        !unfree || package.meta ? sourceProvenance
      ) "${name}: unfree packages must declare source provenance";
      package.drvPath
    ) supported;
in
builtins.listToAttrs (
  map (system: {
    name = system;
    value = forSystem system;
  }) systems
)
