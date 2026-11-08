{
  lib,
  buildNpmPackage,
  nodejs_24,
}:
buildNpmPackage {
  pname = "feishin-managed-scripts";
  version = "1";
  strictDeps = true;
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./.oxlintrc.json
      ./package.json
      ./package-lock.json
      ./tsconfig.json
      ./managed-login-renderer.cts
      ./mpv-message.cts
      ./managed-login.cts
      ./mpv-now-playing.cts
      ./mpv-readiness.cts
      ./mpv-readiness.test.cts
      ./managed-login.test.cts
    ];
  };
  nodejs = nodejs_24;
  npmDepsHash = "sha256-I9opL5lAMaGhhj0MCVXgL6sXyTFPuRIRDp5T9oA6J7w=";
  dontNpmBuild = true;
  buildPhase = builtins.readFile ./scripts/build-helpers.sh;
  doCheck = true;
  checkPhase = builtins.readFile ./scripts/check-helpers.sh;
  installPhase = builtins.readFile ./scripts/install-helpers.sh;
}
