# Evaluate real target recipes without building or executing ARM programs.
{
  nixpkgs,
  system,
  sourceRoot ? ../.,
}:
if system != "x86_64-linux" then
  true
else
  let
    pkgs = import nixpkgs {
      localSystem = system;
      crossSystem.config = "aarch64-unknown-linux-gnu";
      config.allowUnfree = true;
    };
    inherit (pkgs) lib;
    isolated = builtins.path {
      path = sourceRoot + "/pkgs/by-name/no/noctalia-personal";
      name = "standalone-cross-noctalia-personal";
    };
    standalone = pkgs.callPackage (isolated + "/package.nix") { };
    registered = import (sourceRoot + "/pkgs") { inherit pkgs; };
    # Overlay callers supply an incoming scope rather than the final package set.
    overlaid = pkgs.extend (
      _final: prev: { inherit ((import (sourceRoot + "/pkgs") { pkgs = prev; })) noctalia-personal; }
    );
    derivations = [
      standalone.drvPath
      registered.noctalia-personal.drvPath
      overlaid.noctalia-personal.drvPath
    ];
  in
  assert pkgs.stdenv.buildPlatform.system == system;
  assert pkgs.stdenv.hostPlatform.system == "aarch64-linux";
  lib.all (path: lib.hasPrefix "/nix/store/" path && lib.hasSuffix ".drv" path) derivations
