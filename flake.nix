{
  description = "Personal Nix packages maintained by IanHollow";

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
          hostSystem = if builtins.isAttrs system then system.hostSystem else system;
          native = import nixpkgs {
            system = hostSystem;
            config.allowUnfree = true;
          };
          pkgs = import nixpkgs ((import ./flake/platform-args.nix system) // { config.allowUnfree = true; });
          supported = native.lib.filterAttrs (
            _: package: native.lib.meta.availableOn native.stdenv.hostPlatform package
          ) (import ./pkgs { pkgs = native; });
        in
        builtins.intersectAttrs supported (import ./pkgs { inherit pkgs; });
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
        ./flake/build-platform.nix
        ./flake/partitions.nix
        ./flake/ci.nix
      ];

      flake = {
        homeManagerModules.rift = import ./modules/home/rift.nix;
        lib.packagesFor = packagesFor;
        overlays.default = personalOverlay;
        legacyPackages = nixpkgs.lib.genAttrs supportedSystems (
          system:
          import nixpkgs (
            (import ./flake/platform-args.nix system)
            // {
              config.allowUnfree = true;
              overlays = [ personalOverlay ];
            }
          )
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
              pkgs.nix
              pkgs.prefetch-npm-deps
              (pkgs.python3.withPackages (pythonPackages: [
                pythonPackages.pyyaml
                pythonPackages.packaging
              ]))
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
