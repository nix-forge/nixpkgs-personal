{
  description = "Ian Holloway's personal Nix packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      packagesFor =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        pkgs.lib.filterAttrs (_: package: pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform package) (
          import ./pkgs { inherit pkgs; }
        );
      # Discover supported names outside the overlay fixed point. Filtering the
      # prev-based package values would force dependencies before the set exists.
      # Unsupported overrides must leave upstream packages (e.g. Linux Steam) intact.
      personalOverlay =
        _final: prev:
        builtins.intersectAttrs (packagesFor prev.stdenv.hostPlatform.system) (
          import ./pkgs { pkgs = prev; }
        );
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = supportedSystems;
      # Development partitions may replace inputs.nixpkgs for tooling. Package
      # contracts must use the same pin as the public package outputs.
      _module.args.packageNixpkgs = nixpkgs;
      _module.args.packageOverlay = personalOverlay;

      imports = [
        ./flake/partitions.nix
        ./flake/ci.nix
      ];

      flake = {
        overlays.default = personalOverlay;
        legacyPackages = nixpkgs.lib.genAttrs supportedSystems (
          system:
          import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ personalOverlay ];
          }
        );
      };

      perSystem =
        { pkgs, system, ... }:
        let
          packages = packagesFor system;
          update = pkgs.writeShellApplication {
            name = "update-packages";
            runtimeInputs = [
              pkgs.git
              pkgs.python3
            ];
            text = builtins.readFile ./scripts/update-packages.sh;
          };
        in
        {
          inherit packages;
          apps.update = {
            type = "app";
            program = pkgs.lib.getExe update;
          };
        };
    };
}
