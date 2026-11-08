{
  replaceVars,
  actual-server,
  lib,
  nodejs_22,
  testers,
}:
actual-server.overrideAttrs (
  final: old: {
    pname = "actual-cli";
    strictDeps = true;
    buildPhase = builtins.readFile ./scripts/build-phase.sh;
    installPhase = ''
      source ${
        replaceVars ./scripts/install-phase.sh {
          node = lib.getExe nodejs_22;
        }
      }
    '';
    passthru = {
      tests.version = testers.testVersion {
        package = final.finalPackage;
        command = "actual-cli --version";
      };
    };
    meta = old.meta // {
      description = "Official Actual Budget command line client";
      mainProgram = "actual-cli";
      maintainers = [ ];
      sourceProvenance = [ lib.sourceTypes.fromSource ];
    };
  }
)
