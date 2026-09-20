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
      ../../tests/run-package-tests.py
      ../../pkgs/by-name
    ];
  };
in
{
  perSystem = { pkgs, system, ... }: {
    checks = {
      package-policy =
        let
          report = import ../../tests/package-policy.nix {
            nixpkgs = packageNixpkgs;
            overlay = packageOverlay;
            inherit system;
          };
        in
        builtins.deepSeq report (pkgs.writeText "package-policy.json" (builtins.toJSON report));
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
              nativeBuildInputs = [ pkgs.python3 ];
              # Record paths without making every package a build dependency of this check.
              report = builtins.unsafeDiscardStringContext (builtins.toJSON report);
              passAsFile = [ "report" ];
            }
            ''
              python3 ${../../tests/check-package-layout.py} ${../..}
              python3 -B ${../..}/tests/test_package_layout.py
              python3 -B ${../..}/tests/test_nur_check.py
              cp "$reportPath" "$out"
            ''
        );
    }
    // lib.optionalAttrs (system == "x86_64-linux") {
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
          ''
            mkdir -p "$TMPDIR/audiomuse-ai"
            cp -R ${audiomuse.applicationSource}/. "$TMPDIR/audiomuse-ai/"
            export AUDIOMUSE_SOURCE="$TMPDIR/audiomuse-ai"
            export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
            export DATABASE_URL=
            mkdir -p "$PYTHONPYCACHEPREFIX"
            python -m compileall -q "$AUDIOMUSE_SOURCE"
            python - <<'PY'
            import os
            import sys

            source = os.environ["AUDIOMUSE_SOURCE"]
            sys.path.insert(0, f"{source}/native-build")
            sys.path.insert(1, source)

            import importlib.metadata

            from packaging.requirements import Requirement
            from packaging.version import Version

            import google.genai
            import huggingface_hub
            import mistralai
            import onnxruntime
            import safetensors
            import tokenizers
            import transformers
            import app_auth
            import numeric_bootstrap
            import service_roles
            from transformers.dependency_versions_table import deps
            from linux import launcher

            package_version = importlib.metadata.version
            assert package_version("google-genai") == "${source.python.googleGenai.version}"
            assert package_version("huggingface-hub") == "${source.python.huggingfaceHub.version}"
            assert package_version("mistralai") == "${source.python.mistralai.version}"
            assert package_version("transformers") == "${source.python.transformers.version}"
            assert deps["tokenizers"] == "${source.python.transformers.tokenizersRequirement}"
            tokenizers_requirement = Requirement(deps["tokenizers"])
            assert tokenizers_requirement.specifier.contains(
                package_version("tokenizers"), prereleases=True
            )
            assert Version(package_version("tokenizers")) >= Version("0.22.0")
            assert package_version("onnxruntime")
            assert service_roles.ROLE_FLASK == "flask"
            assert launcher.WEB_URL == "http://127.0.0.1:8000"
            PY
            touch "$out"
          '';
      # These tests exercise architecture-neutral package tooling. Running them
      # once avoids rebuilding Python, Node.js, and font tooling on every host.
      package-unit-tests =
        pkgs.runCommand "package-unit-tests"
          {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (p: [
                p.fonttools
                p.pyyaml
              ]))
              pkgs.fontconfig
              pkgs.nodejs_24
              pkgs.pnpm_11
            ];
          }
          ''
            export FONT_FIXTURE=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf
            export FONTCONFIG_FILE=${../../pkgs/by-name/ap/apple-fonts/fonts.conf}
            export XDG_CACHE_HOME="$TMPDIR/cache"
            python3 ${unitSource}/tests/run-package-tests.py ${unitSource}
            touch "$out"
          '';
    };
  };
}
