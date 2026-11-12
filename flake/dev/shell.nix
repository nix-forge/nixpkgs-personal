{ lib, ... }: {
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.pre-commit.settings) enabledPackages package shellHook;
      checkPython = import ./quality-python.nix { pkgs = pkgs.buildPackages; };
    in
    {
      devShells = {
        default = pkgs.buildPackages.mkShellNoCC {
          inherit shellHook;
          LIBRARY_PATH = lib.optionalString pkgs.buildPackages.stdenv.hostPlatform.isDarwin "${pkgs.buildPackages.libiconv}/lib";
          NIX_LDFLAGS = lib.optionalString pkgs.buildPackages.stdenv.hostPlatform.isDarwin "-L${pkgs.buildPackages.libiconv}/lib";
          RUST_SRC_PATH = "${pkgs.buildPackages.rustPlatform.rustLibSrc}";
          packages =
            enabledPackages
            ++ [
              package
              (import ./javascript-tools.nix { pkgs = pkgs.buildPackages; })
            ]
            ++ (with pkgs.buildPackages; [
              actionlint
              _7zz
              fontconfig
              checkPython
              cargo
              cargo-deny
              cargo-machete
              cargo-nextest
              clippy
              deadnix
              direnv
              editorconfig-checker
              gitleaks
              jq
              keep-sorted
              just
              nixd
              nixf-diagnose
              nixfmt
              nodejs_24
              prek
              pinact
              prefetch-npm-deps
              rumdl
              rust-analyzer
              rustc
              rustfmt
              shellcheck
              shfmt
              statix
              taplo
              treefmt
              typos
              yamlfmt
              yamllint
              zizmor
            ])
            ++ lib.optionals pkgs.buildPackages.stdenv.hostPlatform.isDarwin [ pkgs.buildPackages.libiconv ];
        };
      };
    };
}
