{ pkgs }:
let
  inherit (pkgs) callPackage;
  darwinPackages = {
    linearmouse = callPackage ./by-name/li/linearmouse/package.nix { };
  };
  darwinArmPackages = {
    claude-desktop = callPackage ./by-name/cl/claude-desktop/package.nix { };
    libreoffice = callPackage ./by-name/li/libreoffice/package.nix { };
    microsoft-teams = callPackage ./by-name/mi/microsoft-teams/package.nix { };
    openai-codex-desktop = callPackage ./by-name/op/openai-codex-desktop/package.nix { };
    remindctl = callPackage ./by-name/re/remindctl/package.nix { };
    spotify-spotx = callPackage ./by-name/sp/spotify-spotx/package.nix { };
    steam = callPackage ./by-name/st/steam/package.nix { };
    t3-code = callPackage ./by-name/t3/t3-code/package.nix { };
    vorssaint = callPackage ./by-name/vo/vorssaint/package.nix { };
  };
in
{
  anthropic-skills = callPackage ./by-name/an/anthropic-skills/package.nix { };
  openai-skills = callPackage ./by-name/op/openai-skills/package.nix { };
  ttf-ms-win11-auto = callPackage ./by-name/tt/ttf-ms-win11-auto/package.nix { };
}
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin darwinPackages
// pkgs.lib.optionalAttrs (
  pkgs.stdenv.hostPlatform.isAarch64 && pkgs.stdenv.hostPlatform.isDarwin
) darwinArmPackages
