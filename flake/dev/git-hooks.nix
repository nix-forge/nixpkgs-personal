{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem =
    { config, pkgs, ... }:
    let
      wireguardRoamingQuality = pkgs.writeShellApplication {
        name = "wireguard-roaming-quality";
        runtimeInputs = with pkgs; [
          cargo
          cargo-deny
          cargo-machete
          clippy
          rustc
        ];
        text = ''
          manifest="pkgs/by-name/wi/wireguard-roaming-controller/Cargo.toml"
          cargo clippy --manifest-path "$manifest" --all-targets --all-features --locked -- -D warnings
          cargo test --manifest-path "$manifest" --all-targets --all-features --locked --no-fail-fast
          cargo machete pkgs/by-name/wi/wireguard-roaming-controller
          cargo deny --manifest-path "$manifest" --locked check bans licenses sources
        '';
      };
    in
    {
      pre-commit = {
        check.enable = pkgs.stdenv.hostPlatform.isDarwin;
        settings = {
          package = pkgs.prek;
          hooks = {
            treefmt = {
              enable = true;
              name = "treefmt";
              entry = "${lib.getExe config.treefmt.build.wrapper} --no-cache";
              pass_filenames = true;
            };
            pinact = {
              enable = true;
              name = "pinact";
              entry = "${lib.getExe pkgs.pinact} run --fix=false --no-api";
              language = "system";
              files = "^\\.github/workflows/.*\\.ya?ml$";
              after = [ "treefmt" ];
            };
            ruff-format = {
              enable = true;
              entry = "${lib.getExe pkgs.ruff} format --check .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            ruff = {
              enable = true;
              entry = "${lib.getExe pkgs.ruff} check .";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff-format" ];
            };
            ty = {
              enable = true;
              entry = "${lib.getExe pkgs.ty} check";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ruff" ];
            };
            python-compile = {
              enable = true;
              # Compile every package updater as well as the top-level scripts.
              # -B verifies syntax without leaving __pycache__ files in a working tree.
              entry = "${lib.getExe pkgs.python3} -B -m compileall -q scripts pkgs";
              language = "system";
              always_run = true;
              pass_filenames = false;
              after = [ "ty" ];
            };
            wireguard-roaming-check = {
              enable = true;
              name = "wireguard roaming cargo check";
              entry = "cargo check --manifest-path pkgs/by-name/wi/wireguard-roaming-controller/Cargo.toml --all-targets --all-features --locked";
              language = "system";
              extraPackages = [
                pkgs.cargo
                pkgs.rustc
              ];
              files = "^pkgs/by-name/wi/wireguard-roaming-controller/.*\\.(rs|toml)$";
              pass_filenames = false;
              after = [ "treefmt" ];
            };
            wireguard-roaming-quality = {
              enable = true;
              name = "wireguard roaming Rust quality";
              entry = lib.getExe wireguardRoamingQuality;
              language = "system";
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
              after = [ "wireguard-roaming-check" ];
            };

            end-of-file-fixer.enable = true;
            trim-trailing-whitespace.enable = true;
            mixed-line-endings = {
              enable = true;
              args = [ "--fix=lf" ];
            };
            check-merge-conflicts.enable = true;
            check-symlinks.enable = true;
            detect-private-keys.enable = true;
            check-case-conflicts.enable = true;
            check-added-large-files.enable = true;
            check-executables-have-shebangs.enable = true;
            check-shebang-scripts-are-executable.enable = true;
            fix-byte-order-marker.enable = true;
            check-json.enable = true;
            check-toml.enable = true;
            check-yaml.enable = true;
            editorconfig-checker = {
              enable = true;
              excludes = [ "^\\.gitmodules$" ];
            };
            typos = {
              enable = true;
              settings.configPath = ".typos.toml";
            };
            zizmor = {
              enable = true;
              args = [
                "--persona=pedantic"
                "--min-severity=medium"
              ];
            };
            gitleaks = {
              enable = true;
              name = "Gitleaks";
              entry = "${lib.getExe pkgs.gitleaks} git --pre-commit --staged --redact --no-banner --config=.gitleaks.toml";
              language = "system";
              always_run = true;
              pass_filenames = false;
            };
            flake-checker.enable = true;

            nix-flake-check = {
              enable = true;
              entry = "${lib.getExe pkgs.nix} flake check --no-build";
              language = "system";
              always_run = true;
              pass_filenames = false;
              stages = [ "pre-push" ];
            };
          };
        };
      };
    };
}
