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
      checkPython = import ./quality-python.nix { pkgs = pkgs.buildPackages; };
      javascriptTools = import ./javascript-tools.nix { pkgs = pkgs.buildPackages; };
      javascriptLint = pkgs.buildPackages.writeShellApplication {
        name = "package-typescript-lint";
        runtimeInputs = [
          pkgs.buildPackages.coreutils
          pkgs.buildPackages.findutils
          pkgs.buildPackages.nodejs_24
        ];
        text = (import ../../lib/render-text.nix) ./scripts/javascript-lint.sh.in {
          javascript_tools = javascriptTools;
          npm = lib.getExe' pkgs.buildPackages.nodejs_24 "npm";
          oxlint = lib.getExe javascriptTools;
        };
      };
      evaluationCheck = pkgs.buildPackages.writeShellApplication {
        name = "package-evaluation-check";
        runtimeInputs = [
          pkgs.buildPackages.jq
          pkgs.buildPackages.bash
        ];
        text = builtins.readFile ./scripts/package-evaluation-check.sh;
      };
      pythonCompile = pkgs.buildPackages.writeShellApplication {
        name = "package-python-compile";
        text = (import ../../lib/render-text.nix) ./scripts/package-python-compile.sh {
          lib_getExe_pkgs_coreutils_mktemp = lib.getExe' pkgs.buildPackages.coreutils "mktemp";
          lib_getExe_pkgs_coreutils_rm = lib.getExe' pkgs.buildPackages.coreutils "rm";
          lib_getExe_pkgs_python3 = lib.getExe pkgs.buildPackages.python3;
        };
      };
      hookSettings = {
        package = pkgs.buildPackages.prek;
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
            entry = "${lib.getExe pkgs.buildPackages.pinact} run --fix=false --no-api";
            language = "system";
            files = "^\\.github/workflows/.*\\.ya?ml$";
            after = [ "treefmt" ];
          };
          oxlint = {
            enable = true;
            name = "TypeScript and Oxlint";
            entry = lib.getExe javascriptLint;
            language = "system";
            extraPackages = [ javascriptTools ];
            files = "(\\.[cm]?[jt]sx?$|(^|/)(tsconfig|application-types|projects|\\.oxlintrc|package(-lock)?)\\.json$)";
            pass_filenames = false;
            after = [ "treefmt" ];
          };
          ruff-format = {
            enable = true;
            entry = "${lib.getExe pkgs.buildPackages.ruff} format --check .";
            language = "system";
            always_run = true;
            pass_filenames = false;
            after = [ "treefmt" ];
          };
          ruff = {
            enable = true;
            entry = "${lib.getExe pkgs.buildPackages.ruff} check .";
            language = "system";
            always_run = true;
            pass_filenames = false;
            after = [ "ruff-format" ];
          };
          ty = {
            enable = true;
            entry = "${lib.getExe pkgs.buildPackages.ty} check --python ${lib.getExe checkPython}";
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
          check-shebang-scripts-are-executable = {
            enable = true;
            # Rendered launcher templates are not directly executable source files.
            # Rust crate attributes also begin with #! without a script shebang.
            excludes = [
              ".*\\.sh\\.in$"
              ".*\\.rs$"
            ];
          };
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
            entry = "${lib.getExe pkgs.buildPackages.typos} --config .typos.toml --force-exclude";
          };
          zizmor = {
            enable = true;
            package = import ./zizmor.nix { pkgs = pkgs.buildPackages; };
            args = [ "--persona=pedantic" ];
          };
          gitleaks = {
            enable = true;
            name = "Gitleaks";
            entry = "${lib.getExe pkgs.buildPackages.gitleaks} git --pre-commit --staged --redact --no-banner --config=.gitleaks.toml";
            # The complete entry owns its arguments; do not append hook defaults.
            args = [ ];
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
      checks.pre-commit =
        (inputs.git-hooks-nix.lib.${system}.run (hookSettings // { src = inputs.self.outPath; }))
        .overrideAttrs
          {
            # Sandbox checks use pipes; interactive hooks keep their default colors.
            PREK_COLOR = "never";
          };
    };
}
