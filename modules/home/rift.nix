{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.rift;
  format = pkgs.formats.toml { };
  configurationFile = format.generate "rift-config.toml" cfg.settings;
  applicationPath = "${config.home.homeDirectory}/${config.targets.darwin.copyApps.directory}/Rift.app";
in
{
  options.programs.rift = {
    enable = lib.mkEnableOption "Rift window management";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rift or (pkgs.callPackage ../../pkgs/by-name/ri/rift/package.nix { });
      defaultText = lib.literalExpression "pkgs.rift";
      description = "Rift package with Rift.app and its matching IPC CLI. Falls back to this collection's recipe without an overlay.";
    };
    startAtLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Manage one Rift instance through Home Manager's LaunchAgent. Do not also install Rift's native or Homebrew service.";
    };
    settings = lib.mkOption {
      inherit (format) type;
      default = { };
      description = "Declarative Rift TOML configuration, including its built-in key bindings. The native Settings UI must not write this store-backed file.";
    };
    applicationPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = applicationPath;
      description = "Stable copied bundle used by launchd and macOS Accessibility.";
    };
    configurationFile = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = configurationFile;
      description = "Generated configuration used by the managed service.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "programs.rift" pkgs lib.platforms.darwin)
      {
        assertion = !(config.programs.aerospace.enable or false);
        message = "Rift and AeroSpace must not manage windows and shortcuts at the same time.";
      }
      {
        assertion = config.targets.darwin.copyApps.enable;
        message = "Rift requires targets.darwin.copyApps.enable for its stable application identity.";
      }
    ];
    home.packages = [ cfg.package ];
    targets.darwin.copyApps.enable = lib.mkDefault true;
    targets.darwin.linkApps.enable = lib.mkDefault false;
    xdg.configFile."rift/config.toml".source = configurationFile;
    programs.rift.settings = {
      settings = {
        default_disable = lib.mkDefault false;
        hot_reload = lib.mkDefault true;
        ui.mission_control = {
          enabled = lib.mkDefault false;
          window_previews = lib.mkDefault false;
        };
      };
      keys = lib.mkDefault { };
    };
    home.activation.waitForCopiedRift = lib.mkIf cfg.startAtLogin (
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "copyApps" ] ''
        run mkdir -p ${lib.escapeShellArg "${config.home.homeDirectory}/Library/Logs"}
        run /bin/wait4path ${lib.escapeShellArg applicationPath}
      ''
    );
    launchd.agents.rift = lib.mkIf cfg.startAtLogin {
      enable = true;
      config = {
        ProgramArguments = [
          "${applicationPath}/Contents/MacOS/rift"
          "--config"
          "${config.xdg.configHome}/rift/config.toml"
        ];
        # The executable's stable copied path does not change on upgrades.
        # Bind the agent identity to the package so HM restarts it on replacement.
        EnvironmentVariables.RIFT_PACKAGE_PATH = toString cfg.package;
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        ThrottleInterval = 5;
        ProcessType = "Interactive";
        LimitLoadToSessionType = "Aqua";
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/rift.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/rift.err.log";
      };
    };
  };
}
