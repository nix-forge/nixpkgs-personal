{ inputs, lib, ... }: {
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    let
      templateFormatter = pkgs.buildPackages.writeShellApplication {
        name = "format-nix-template";
        runtimeInputs = [
          pkgs.buildPackages.nixfmt
          pkgs.buildPackages.coreutils
          pkgs.buildPackages.diffutils
        ];
        text = builtins.readFile ./scripts/format-nix-template.sh;
      };
      python = pkgs.buildPackages.python3.withPackages (_: [
        (pkgs.buildPackages.callPackage ../../pkgs/by-name/no/notification-process/package.nix { })
      ]);
    in
    {
      checks.nix-template-formatter =
        pkgs.buildPackages.runCommand "nix-template-formatter" { nativeBuildInputs = [ python ]; }
          ''
            python3 ${../../tests/check_nix_template_formatter.py} ${lib.getExe templateFormatter}
            touch "$out"
          '';
      treefmt.programs = {
        actionlint.enable = true;
        yamlfmt = {
          enable = true;
          settings.formatter.max_line_length = 100;
        };
        yamllint = {
          enable = true;
          settings = {
            extends = "default";
            rules = {
              # Repository YAML uses one document per file.
              document-start = "disable";
              # yamlfmt emits one space before inline comments.
              comments.min-spaces-from-content = 1;
              # GitHub Actions uses the YAML 1.2 key `on`.
              truthy.check-keys = false;
              line-length = {
                max = 160;
                level = "error";
              };
            };
          };
        };

        deadnix = {
          enable = true;
          priority = 100;
        };
        statix = {
          enable = true;
          priority = 200;
        };
        nixfmt = {
          enable = true;
          width = 100;
          strict = true;
          priority = 300;
        };
        nixf-diagnose = {
          enable = true;
          autoFix = false;
          priority = 400;
        };

        ruff-check.enable = true;
        ruff-format.enable = true;
        rustfmt.enable = true;
        clang-format.enable = true;
        shfmt.enable = true;
        shellcheck.enable = true;
        taplo.enable = true;
        rumdl-check.enable = true;
        typos = {
          enable = true;
          configFile = ".typos.toml";
        };
        prettier = {
          enable = true;
          excludes = [
            "*.md"
            "*.yaml"
            "*.yml"
          ];
          settings.proseWrap = "always";
        };
        keep-sorted.enable = true;
        just.enable = true;
      };
      treefmt.settings.formatter = {
        prettier = {
          command = lib.mkForce "${
            import ./javascript-tools.nix { pkgs = pkgs.buildPackages; }
          }/bin/prettier";
          includes = [
            "*.mts"
            "*.cts"
          ];
        };
        nix-template = {
          command = lib.getExe templateFormatter;
          includes = [ "*.nix.in" ];
        };
        shfmt.includes = [ "*.sh.in" ];
        shellcheck.includes = [ "*.sh.in" ];
        # Spelling suggestions must not rewrite protocol names or translations.
        typos.options = lib.mkForce [
          "--force-exclude"
          "--config"
          ".typos.toml"
        ];
      };
    };
}
