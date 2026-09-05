{ lib, ... }: {
  perSystem =
    { config, pkgs, ... }:
    let
      inherit (config.pre-commit.settings) enabledPackages package shellHook;
    in
    {
      devShells.default = pkgs.mkShellNoCC {
        inherit shellHook;
        LIBRARY_PATH = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "${pkgs.libiconv}/lib";
        NIX_LDFLAGS = lib.optionalString pkgs.stdenv.hostPlatform.isDarwin "-L${pkgs.libiconv}/lib";
        RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
        packages =
          enabledPackages
          ++ [ package ]
          ++ (with pkgs; [
            actionlint
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
            prek
            pinact
            prettier
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
          ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
            pkgs.clang-tools
            pkgs.libiconv
            pkgs.periphery
            pkgs.swift-format
            pkgs.swiftlint
          ];
      };
    };
}
