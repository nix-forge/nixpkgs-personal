{ inputs, lib, ... }: {
  imports = [ inputs.git-hooks-nix.flakeModule ];

  perSystem =
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      checkPython = pkgs.python3.withPackages (
        ps: with ps; [
          fonttools
          lxml
          pillow
          pyyaml
          selenium
          uharfbuzz
          websocket-client
        ]
      );
      evaluationCheck = pkgs.writeShellApplication {
        name = "package-evaluation-check";
        text = ''
          # A fresh filtered source needs materialization before a read-only check.
          nix store add-path flake/dev >/dev/null
          nix eval --option allow-import-from-derivation false --json .#checks --apply 'builtins.mapAttrs (_: checks: builtins.mapAttrs (_: check: check.drvPath) checks)' >/dev/null
          nix flake check --all-systems --no-build --option allow-import-from-derivation false
        '';
      };
      pythonCompile = pkgs.writeShellApplication {
        name = "package-python-compile";
        text = ''
          cache="$(${lib.getExe' pkgs.coreutils "mktemp"} -d)"
          trap '${lib.getExe' pkgs.coreutils "rm"} -rf -- "$cache"' EXIT
          PYTHONPYCACHEPREFIX="$cache" ${lib.getExe pkgs.python3} -m compileall -q .github scripts pkgs tests
        '';
      };
      hookSettings = {
        package = pkgs.prek;
        hooks = {
          treefmt = {
            enable = true;
            name = "treefmt";
            # treefmt schedules its formatters; avoid many concurrent wrappers.
            require_serial = true;
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
          oxlint = {
            enable = true;
            name = "Oxlint";
            entry = "${lib.getExe pkgs.oxlint} --config .oxlintrc.json --deny-warnings .";
            language = "system";
            extraPackages = [ pkgs.oxlint ];
            files = "(^\\.oxlintrc\\.json$|\\.[cm]?[jt]sx?$)";
            pass_filenames = false;
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
            entry = "${lib.getExe pkgs.ty} check --python ${lib.getExe checkPython}";
            language = "system";
            always_run = true;
            pass_filenames = false;
            after = [ "ruff" ];
          };
          python-compile = {
            enable = true;
            # Compile every package updater, CI helper, and Python test.
            # compileall writes bytecode even with -B; use a temporary cache.
            entry = lib.getExe pythonCompile;
            language = "system";
            always_run = true;
            pass_filenames = false;
            after = [ "ty" ];
          };
          end-of-file-fixer.enable = true;
          trim-trailing-whitespace = {
            enable = true;
            # Patch context whitespace belongs to upstream source.
            excludes = [ "\\.patch$" ];
          };
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
          };
          typos = {
            enable = true;
            # The upstream hook's generated empty [default] table overrides configPath.
            entry = "${lib.getExe pkgs.typos} --config .typos.toml --force-exclude";
          };
          zizmor = {
            enable = true;
            args = [ "--persona=pedantic" ];
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
            # Use the Nix installation that supplies the daemon and its settings.
            # Injecting nixpkgs' CLI rejects Determinate's schemas/settings.
            entry = lib.getExe evaluationCheck;
            language = "system";
            always_run = true;
            pass_filenames = false;
            stages = [ "pre-push" ];
          };
        };
      };
    in
    {
      pre-commit = {
        # Export the sandbox-specific configuration below; retain every local hook.
        check.enable = false;
        settings = hookSettings;
      };
      checks.pre-commit = inputs.git-hooks-nix.lib.${system}.run (
        hookSettings // { src = inputs.self.outPath; }
      );
    };
}
