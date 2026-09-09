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
          PYTHONPYCACHEPREFIX="$cache" ${lib.getExe pkgs.python3} -m compileall -q scripts pkgs
        '';
      };
      # Xcode and SourceKit are supplied by the host and cannot run in a Nix sandbox.
      # Keep these hooks in local Git workflows and the required native Swift jobs.
      xcodeHooks = {
        ocr-capture-swift-format = {
          enable = pkgs.stdenv.hostPlatform.isDarwin;
          name = "OCR Capture swift-format";
          entry = "xcrun swift-format lint --configuration pkgs/by-name/oc/ocr-capture/.swift-format --parallel --strict --recursive pkgs/by-name/oc/ocr-capture/Sources pkgs/by-name/oc/ocr-capture/Tests";
          language = "system";
          files = "^pkgs/by-name/oc/ocr-capture/(\\.swift-format|.*\\.swift)$";
          pass_filenames = false;
          after = [ "treefmt" ];
        };
        ocr-capture-swiftlint = {
          enable = pkgs.stdenv.hostPlatform.isDarwin;
          name = "OCR Capture SwiftLint";
          entry = "${lib.getExe pkgs.swiftlint} lint --no-cache --strict --config pkgs/by-name/oc/ocr-capture/.swiftlint.yml";
          language = "system";
          extraPackages = [ pkgs.swiftlint ];
          files = "^pkgs/by-name/oc/ocr-capture/(\\.swiftlint\\.yml|.*\\.swift)$";
          pass_filenames = false;
          after = [ "ocr-capture-swift-format" ];
        };
        ocr-capture-quality = {
          enable = pkgs.stdenv.hostPlatform.isDarwin;
          name = "OCR Capture Swift quality suite";
          entry = "pkgs/by-name/oc/ocr-capture/Scripts/check-quality.sh";
          language = "system";
          extraPackages = [
            pkgs.periphery
            pkgs.swiftlint
          ];
          files = "^pkgs/by-name/oc/ocr-capture/";
          pass_filenames = false;
          stages = [ "pre-push" ];
          after = [ "ocr-capture-swiftlint" ];
        };
        finder-favorites-swiftlint = {
          enable = pkgs.stdenv.hostPlatform.isDarwin;
          name = "Finder Favorites SwiftLint";
          entry = "${lib.getExe pkgs.swiftlint} lint --no-cache --strict --config pkgs/by-name/fi/finder-favorites/.swiftlint.yml";
          language = "system";
          extraPackages = [ pkgs.swiftlint ];
          files = "^pkgs/by-name/fi/finder-favorites/(\\.swiftlint\\.yml|.*\\.swift)$";
          pass_filenames = false;
          after = [ "finder-favorites-swift-format" ];
        };
        finder-favorites-quality = {
          enable = pkgs.stdenv.hostPlatform.isDarwin;
          name = "Finder Favorites all-language quality suite";
          entry = "pkgs/by-name/fi/finder-favorites/Scripts/check-quality.sh";
          language = "system";
          extraPackages = with pkgs; [
            clang-tools
            deadnix
            jq
            nixf-diagnose
            nixfmt
            periphery
            prettier
            rumdl
            shellcheck
            shfmt
            statix
            swift-format
            swiftlint
            typos
            yamlfmt
            yamllint
          ];
          files = "^pkgs/by-name/fi/finder-favorites/";
          pass_filenames = false;
          stages = [ "pre-push" ];
          after = [
            "finder-favorites-c-format"
            "finder-favorites-swiftlint"
          ];
        };
      };
      hookSettings = withXcode: {
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
            # Compile every package updater as well as the top-level scripts.
            # compileall writes bytecode even with -B; use a temporary cache.
            entry = lib.getExe pythonCompile;
            language = "system";
            always_run = true;
            pass_filenames = false;
            after = [ "ty" ];
          };
          finder-favorites-swift-format = {
            enable = true;
            name = "Finder Favorites swift-format";
            entry = "${lib.getExe pkgs.swift-format} lint --configuration pkgs/by-name/fi/finder-favorites/.swift-format --parallel --strict --recursive pkgs/by-name/fi/finder-favorites/Sources pkgs/by-name/fi/finder-favorites/Tests pkgs/by-name/fi/finder-favorites/Package.swift";
            language = "system";
            extraPackages = [ pkgs.swift-format ];
            files = "^pkgs/by-name/fi/finder-favorites/(Package\\.swift|\\.swift-format|.*\\.swift)$";
            pass_filenames = false;
            after = [ "treefmt" ];
          };
          finder-favorites-c-format = {
            enable = true;
            name = "Finder Favorites clang-format";
            entry = "${lib.getExe' pkgs.clang-tools "clang-format"} --dry-run --Werror --style=file";
            language = "system";
            extraPackages = [ pkgs.clang-tools ];
            files = "^pkgs/by-name/fi/finder-favorites/.*\\.(c|h)$";
            after = [ "treefmt" ];
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
        }
        // lib.optionalAttrs withXcode xcodeHooks;
      };
    in
    {
      pre-commit = {
        # Export the sandbox-specific configuration below; retain every local hook.
        check.enable = false;
        settings = hookSettings true;
      };
      checks.pre-commit = inputs.git-hooks-nix.lib.${system}.run (
        (hookSettings false) // { src = inputs.self.outPath; }
      );
    };
}
