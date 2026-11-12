{ pkgs }:
let
  inherit (pkgs) lib;
  renderTemplate = import ./package-template-renderer.nix { inherit lib; };
  markerSource = builtins.toFile "marker-regression.sh" "a=@a@ b=@b@ deferred=@deferred@\n";
  markerReplacements = {
    a = "@b@";
    b = "literal $HOME";
    deferred = null;
  };
  rejects = replacements: !(builtins.tryEval (renderTemplate markerSource replacements)).success;
  markerExpected = pkgs.replaceVars markerSource markerReplacements;
  markerRendered = renderTemplate markerSource markerReplacements;
  expected = "literal $HOME \"quoted\" 'single' \\ backslash\nsecond line";
  phase = pkgs.replaceVars ./fixtures/native-phase.sh {
    directory = lib.escapeShellArg "directory with spaces";
    value = lib.escapeShellArg expected;
    deferred = null;
  };
  renderedPhase = renderTemplate ./fixtures/native-phase.sh {
    directory = lib.escapeShellArg "directory with spaces";
    value = lib.escapeShellArg expected;
    deferred = null;
  };
  application = pkgs.writeShellApplication {
    name = "package-shell-probe";
    runtimeInputs = [ pkgs.coreutils ];
    inheritPath = false;
    text = builtins.readFile ./fixtures/native-shell.sh;
  };
  python = pkgs.writers.writePython3Bin "package-python-probe" {
    libraries = [ pkgs.python3Packages.packaging ];
  } ./fixtures/native_probe.py;
  fakeNode = pkgs.writeShellScriptBin "node" (builtins.readFile ./fixtures/native-forward.sh);
  steamClient = pkgs.writeShellScriptBin "steam-client" (
    builtins.readFile ./fixtures/native-forward.sh
  );
  steamBootstrap = pkgs.writeShellApplication {
    name = "steam-bootstrap";
    runtimeInputs = [ pkgs.coreutils ];
    text = lib.replaceStrings [ "@client@" ] [ (lib.getExe steamClient) ] (
      builtins.readFile ./fixtures/steam-bootstrap.sh
    );
  };
  steamInstall = pkgs.replaceVars ../pkgs/by-name/st/steam/scripts/install-phase.sh {
    pname = "steam";
    launcherSource = pkgs.replaceVars ../pkgs/by-name/st/steam/scripts/steam-launcher.sh.in {
      runtimeOutput = null;
    };
  };
  scryptedInstall = pkgs.replaceVars ../pkgs/by-name/sc/scrypted-server/scripts/install-phase.sh {
    nodejs_24 = fakeNode;
    launcherSource = pkgs.replaceVars ../pkgs/by-name/sc/scrypted-server/scripts/scrypted-serve.sh.in {
      nodejs_24 = fakeNode;
      runtimeOutput = null;
    };
  };
in
assert rejects (markerReplacements // { unused = "x"; });
assert rejects (removeAttrs markerReplacements [ "b" ]);
pkgs.runCommand "package-helpers" {
  nativeBuildInputs = [
    pkgs.bash
    pkgs.gnutar
    pkgs.zip
    pkgs.unzip
  ];
  inherit
    phase
    renderedPhase
    markerExpected
    markerRendered
    expected
    steamInstall
    scryptedInstall
    ;
  shellProbe = lib.getExe application;
  pythonProbe = lib.getExe python;
  steamBootstrapProgram = lib.getExe steamBootstrap;
} (builtins.readFile ./scripts/check-package-helpers.sh)
