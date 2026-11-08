{
  lib,
  packageNixpkgs,
  packageOverlay,
  ...
}:
let
  unitSource = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../.github/workflows/update-packages.yml
      ../../.github/workflows/dco.yml
      ../../tests/run_package_tests.py
      ../../tests/test_update_packages.py
      ../../tests/test_updater_support.py
      ../../tests/test_update_transaction.py
      ../../tests/update_transaction.py
      ../../tests/update_nix.py
      ../../tests/run_update.py
      ../../tests/test_package_catalog.py
      ../../scripts/update_packages.py
      ../../scripts/package_catalog.py
      ../../pkgs/by-name
    ];
  };
  javascriptSource = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../.editorconfig
      ../../package.json
      ../../package-lock.json
      ../../tsconfig.json
      ../../tests/javascript
      ../../tests/check_node_modules.mts
      (lib.fileset.fileFilter (
        file:
        builtins.any file.hasExt [
          "ts"
          "mts"
          "cts"
          "tsx"
          "js"
          "mjs"
          "cjs"
          "jsx"
        ]
        || builtins.elem file.name [
          "tsconfig.json"
          "application-types.json"
          ".oxlintrc.json"
        ]
      ) ../../pkgs/by-name)
    ];
  };
in
{
  perSystem = { pkgs, system, ... }: {
    checks = {
      source-pins = import ../../tests/source-pins.nix { inherit pkgs; };
      package-updaters = import ../../tests/package-updaters.nix {
        inherit pkgs;
        nixpkgs = packageNixpkgs;
      };
      updater-unit-tests =
        pkgs.runCommand "updater-unit-tests"
          {
            nativeBuildInputs = [
              pkgs.git
              pkgs.jq
              (pkgs.python3.withPackages (_: [
                (pkgs.callPackage ../../pkgs/by-name/no/notification-process/package.nix { })
              ]))
            ];
          }
          ''
            python3 -B ${unitSource}/tests/test_update_transaction.py
            python3 -B ${unitSource}/tests/test_updater_support.py
            python3 -B ${unitSource}/tests/test_update_packages.py
            touch "$out"
          '';

      package-app-metadata =
        let
          source = lib.fileset.toSource {
            root = ../..;
            fileset = lib.fileset.unions [
              ../../tests/check_desktop_entry.py
              ../../tests/check_desktop_items.py
              ../../tests/check_app_bundle.py
              ../../tests/test_app_bundle_metadata.py
              ../../pkgs/by-name/da/darktable-app-personal/test_bundle.py
              ../../pkgs/by-name/da/darktable-app-personal/scripts/configure_bundle.py
            ];
          };
          desktopContracts =
            let
              upstream = import packageNixpkgs { inherit system; };
              moonfin = upstream.callPackage ../../pkgs/by-name/mo/moonfin/package.nix { };
            in
            lib.optionals (system == "x86_64-linux") [
              {
                package = moonfin;
                displayName = "Moonfin";
                icon = "org.moonfin.linux";
              }
            ];
        in
        pkgs.runCommand "package-app-metadata"
          {
            nativeBuildInputs = [
              pkgs.python3
            ]
            ++ lib.optionals (desktopContracts != [ ]) [ pkgs.desktop-file-utils ];
          }
          (
            ''
              python3 -B ${source}/tests/test_app_bundle_metadata.py
              python3 -B ${source}/pkgs/by-name/da/darktable-app-personal/test_bundle.py
            ''
            + lib.concatMapStrings (
              contract:
              lib.concatMapStrings (item: ''
                for entry in ${item}/share/applications/*.desktop; do
                  desktop-file-validate "$entry"
                  python3 -B ${source}/tests/check_desktop_items.py "$entry" \
                    ${lib.escapeShellArgs [
                      contract.package.meta.mainProgram
                      contract.displayName
                      contract.icon
                    ]}
                done
              '') contract.package.desktopItems
            ) desktopContracts
            + ''
              touch "$out"
            ''
          );

      license-metadata =
        pkgs.runCommand "license-metadata"
          { results = builtins.toJSON (import ../../tests/license-metadata.nix); }
          ''
            printf '%s\n' "$results" > "$out"
          '';

      javascript-quality = pkgs.buildNpmPackage {
        pname = "package-javascript-quality";
        version = "1";
        src = javascriptSource;
        nodejs = pkgs.nodejs_24;
        inherit (import ./javascript-tools.nix { inherit pkgs; }) npmDeps;
        dontNpmBuild = true;
        dontNpmInstall = true;
        doCheck = true;
        checkPhase = builtins.readFile ./scripts/check-javascript.sh;
        installPhase = builtins.readFile ./scripts/install-check-output.sh;
      };
      # The application compiler uses ReactFlux's real locked dependencies.
      reactflux-typescript = pkgs.callPackage ../../pkgs/by-name/re/reactflux/package.nix { };
      package-policy =
        let
          report = import ../../tests/package-policy.nix {
            nixpkgs = packageNixpkgs;
            overlay = packageOverlay;
            inherit system;
          };
        in
        builtins.deepSeq report (pkgs.writeText "package-policy.json" (builtins.toJSON report));
      package-templates = import ../../tests/package-templates.nix {
        inherit pkgs system;
        nixpkgs = packageNixpkgs;
      };
      package-helpers = import ../../tests/package-helpers.nix {
        pkgs = import packageNixpkgs { inherit system; };
      };
      package-independence =
        let
          report = import ../../tests/package-contract.nix {
            nixpkgs = packageNixpkgs;
            overlay = packageOverlay;
            inherit system;
          };
        in
        # Force all metadata and derivation paths during evaluation on every system.
        builtins.deepSeq report (
          pkgs.runCommand "package-independence"
            {
              nativeBuildInputs = [
                (pkgs.python3.withPackages (_: [
                  (pkgs.callPackage ../../pkgs/by-name/no/notification-process/package.nix { })
                ]))
              ];
              # Record paths without making every package a build dependency of this check.
              report = builtins.unsafeDiscardStringContext (builtins.toJSON report);
              passAsFile = [ "report" ];
            }
            (
              (import ../../lib/render-text.nix) ./scripts/package-independence.sh {
                tests_check_package_layout_py = ../../tests/check_package_layout.py;
                value = ../..;
              }
            )
        );
    }
    // lib.optionalAttrs (system == "x86_64-linux") {
      source-notification-contract =
        let
          source = lib.fileset.toSource {
            root = ../..;
            fileset = lib.fileset.unions [
              ../../.github/workflows
              ../../tests/test_source_notifications.py
            ];
          };
          sharedRelease = pkgs.fetchurl {
            url = "https://github.com/nix-forge/ci/releases/download/v2.13.0/nix-forge-ci-v2.13.0.tar.gz";
            hash = "sha256-DktBzMZugRZKOIjQyZorgkfpSoUdtmTiapqddP5B75Y=";
          };
        in
        pkgs.runCommand "package-source-notification-contract"
          {
            nativeBuildInputs = [
              pkgs.bash
              (pkgs.python3.withPackages (p: [ p.pyyaml ]))
            ];
          }
          ''
            export SHARED_CI_ARCHIVE=${sharedRelease}
            python3 -B ${source}/tests/test_source_notifications.py -v
            touch "$out"
          '';
      # Build the complete Python dependency environment without the large
      # model derivation. This keeps every automated Python pin update
      # observable in normal CI while the multi-gigabyte model audit remains
      # an explicit workflow input.
      audiomuse-ai-python =
        let
          audiomuse = pkgs.callPackage ../../pkgs/by-name/au/audiomuse-ai/package.nix { };
          source = import ../../pkgs/by-name/au/audiomuse-ai/source.nix;
        in
        pkgs.runCommand "audiomuse-ai-python-contract"
          { nativeBuildInputs = [ audiomuse.pythonEnvironment ]; }
          (
            (import ../../lib/render-text.nix) ./scripts/audiomuse-ai-python-contract.sh {
              audiomuse_applicationSource = audiomuse.applicationSource;
              pkgs_replaceVars_scripts_packages_check_py_source_python_goo =
                pkgs.replaceVars ./scripts/check_audiomuse_python_contract.py
                  {
                    source_python_googleGenai_version = source.python.googleGenai.version;
                    source_python_huggingfaceHub_version = source.python.huggingfaceHub.version;
                    source_python_mistralai_version = source.python.mistralai.version;
                    source_python_transformers_version = source.python.transformers.version;
                    source_python_transformers_tokenizersRequirement = source.python.transformers.tokenizersRequirement;
                  };
            }
          );
      package-unit-tests =
        pkgs.runCommand "package-unit-tests"
          {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (p: [
                p.defusedxml
                p.fonttools
                p.packaging
                p.pytest
                p.pyyaml
                p.sigstore
                (pkgs.callPackage ../../pkgs/by-name/no/notification-process/package.nix { })
              ]))
              pkgs.fontconfig
              pkgs.git
              pkgs.jq
              pkgs.nodejs_24
              pkgs.pnpm_11
            ];
          }
          (
            (import ../../lib/render-text.nix) ./scripts/package-unit-tests.sh {
              pkgs_dejavu_fonts = pkgs.dejavu_fonts;
              pkgs_by_name_ap_apple_fonts_fonts_conf = ../../pkgs/by-name/ap/apple-fonts/fonts.conf;
              inherit unitSource;
            }
          );
    }
    // lib.optionalAttrs (system == "x86_64-linux") {
      # The upstream Navidrome builder now targets WASI through pkgsCross.
      # Building this package also checks the packed loopback permission.
      navidrome-plugin-wasi =
        (import packageNixpkgs {
          inherit system;
          config.allowUnfree = true;
        }).callPackage
          ../../pkgs/by-name/na/navidrome-plugin-audiomuseai-personal/package.nix
          { };
    };
  };
}
