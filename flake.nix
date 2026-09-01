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
      personalOverlay = _final: prev: import ./pkgs { pkgs = prev; };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = supportedSystems;

      imports = [ ./flake/partitions.nix ];

      flake = {
        overlays.default = personalOverlay;
        legacyPackages = builtins.listToAttrs (
          map (system: {
            name = system;
            value = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ personalOverlay ];
            };
          }) supportedSystems
        );
      };

      perSystem =
        { pkgs, system, ... }:
        let
          packagePkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          packages = import ./pkgs { pkgs = packagePkgs; };
          update = pkgs.replaceVarsWith {
            name = "update-packages";
            src = ./scripts/update-packages.sh;
            dir = "bin";
            isExecutable = true;
            replacements = {
              bash = "${pkgs.bash}/bin/bash";
              git = "${pkgs.git}/bin/git";
              python = "${pkgs.python3}/bin/python3";
            };
          };
        in
        {
          inherit packages;
          apps.update = {
            type = "app";
            program = "${update}/bin/update-packages";
          };
        };
    };
}
