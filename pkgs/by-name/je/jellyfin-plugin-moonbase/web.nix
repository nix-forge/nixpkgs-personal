{
  replaceVars,
  fetchFromGitHub,
  flutter347,
  lib,
}:
let
  source = import ./source.nix;
  webBaseHref = "/Moonfin/Web/";
in
flutter347.buildFlutterApplication {
  pname = "moonfin-web";
  version = source.webVersion;
  src = fetchFromGitHub {
    owner = "Moonfin-Client";
    repo = "Moonfin-Core";
    rev = source.webRev;
    hash = source.webHash;
  };
  pubspecLock = lib.importJSON ./pubspec.lock.json;
  gitHashes = lib.importJSON ./git-hashes.json;
  # The pinned 0.6.0+eol package contains no Linux CMake directory. Nixpkgs'
  # global sqlite3_flutter_libs source builder patches that directory for
  # native apps; the web target only needs the unmodified package source.
  customSourceBuilders.sqlite3_flutter_libs = { src, ... }: src;
  targetFlutterPlatform = "web";
  strictDeps = true;
  # Flutter's WASM build also emits a JavaScript fallback. Compile it first so
  # the two large compilers do not run concurrently under bounded builders.
  preBuild = ''
    source ${
      replaceVars ./scripts/web-pre-build.sh {
        webBaseHref = lib.escapeShellArg webBaseHref;
      }
    }
  '';
  flutterBuildFlags = [
    "--wasm"
    "--base-href"
    webBaseHref
  ];
  postInstall = builtins.readFile ./scripts/web-post-install.sh;
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/web-install-check-phase.sh;
}
