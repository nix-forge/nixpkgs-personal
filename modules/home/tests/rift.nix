{ pkgs, homeManager }:
let
  inherit (pkgs) lib;
  evaluate =
    extra:
    homeManager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        ../rift.nix
        {
          home.username = "example";
          home.homeDirectory = "/Users/example";
          home.stateVersion = "26.05";
          programs.rift.enable = true;
          programs.rift.settings.keys."Alt + C".switch_to_workspace = 0;
          xdg.configHome = "/Users/example/Config";
        }
        extra
      ];
    };
  active = (evaluate { }).config;
  manual = (evaluate { programs.rift.startAtLogin = false; }).config;
  conflict =
    builtins.tryEval
      (evaluate { programs.aerospace.enable = true; }).activationPackage.drvPath;
  disabled = (evaluate { programs.rift.enable = lib.mkForce false; }).config;
  alternate =
    (evaluate {
      programs.rift.package = active.programs.rift.package.overrideAttrs (old: {
        name = "${old.pname}-${old.version}-alternate";
      });
    }).config;
  args = active.launchd.agents.rift.config.ProgramArguments;
in
assert
  args == [
    "/Users/example/Applications/Home Manager Apps/Rift.app/Contents/MacOS/rift"
    "--config"
    "/Users/example/Config/rift/config.toml"
  ];
assert
  active.launchd.agents.rift.config.EnvironmentVariables.RIFT_PACKAGE_PATH
  != alternate.launchd.agents.rift.config.EnvironmentVariables.RIFT_PACKAGE_PATH;
assert !(manual.launchd.agents.rift.enable or false);
assert !(disabled.launchd.agents.rift.enable or false);
assert (evaluate { }).activationPackage.drvPath != "";
assert !conflict.success;
assert active.programs.rift.settings.settings.ui.mission_control.window_previews == false;
pkgs.runCommand "rift-home-manager-contract"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    generated = active.programs.rift.configurationFile;
  }
  ''
    python3 ${./check_config.py} "$generated"
    touch "$out"
  ''
