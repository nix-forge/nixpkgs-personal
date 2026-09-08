{ pkgs }:
let
  inherit (pkgs) callPackage;
  appleFonts = callPackage ./by-name/ap/apple-fonts/package.nix { };
  darwinPackages = {
    bitwarden-desktop = callPackage ./by-name/bi/bitwarden-desktop/package.nix { };
    linearmouse = callPackage ./by-name/li/linearmouse/package.nix { };
  };
  darwinArmPackages = {
    claude-desktop = callPackage ./by-name/cl/claude-desktop/package.nix { };
    finder-favorites = callPackage ./by-name/fi/finder-favorites/package.nix { };
    libreoffice = callPackage ./by-name/li/libreoffice/package.nix { };
    microsoft-teams = callPackage ./by-name/mi/microsoft-teams/package.nix { };
    ocr-capture = callPackage ./by-name/oc/ocr-capture/package.nix { };
    remindctl = callPackage ./by-name/re/remindctl/package.nix { };
    spotify-spotx = callPackage ./by-name/sp/spotify-spotx/package.nix { };
    steam = callPackage ./by-name/st/steam/package.nix { };
    t3-code = callPackage ./by-name/t3/t3-code/package.nix { };
    vorssaint = callPackage ./by-name/vo/vorssaint/package.nix { };
    wootility = callPackage ./by-name/wo/wootility/package.nix { };
  };
  codexDesktopPackages = {
    openai-codex-desktop = callPackage ./by-name/op/openai-codex-desktop/package.nix { };
  };
  linuxX64Packages = {
    spotify-spotx = callPackage ./by-name/sp/spotify-spotx/package.nix { };
    steam-cef-scale-override = callPackage ./by-name/st/steam-cef-scale-override/package.nix { };
  };
in
{
  anthropic-skills = callPackage ./by-name/an/anthropic-skills/package.nix { };
  apple-fonts = appleFonts;
  apple-new-york = appleFonts.developerFonts.apple-new-york;
  apple-sf-arabic = appleFonts.developerFonts.apple-sf-arabic;
  apple-sf-armenian = appleFonts.developerFonts.apple-sf-armenian;
  apple-sf-compact = appleFonts.developerFonts.apple-sf-compact;
  apple-sf-georgian = appleFonts.developerFonts.apple-sf-georgian;
  apple-sf-hebrew = appleFonts.developerFonts.apple-sf-hebrew;
  apple-sf-mono = appleFonts.developerFonts.apple-sf-mono;
  apple-sf-pro = appleFonts.developerFonts.apple-sf-pro;
  emojione-legacy = callPackage ./by-name/em/emojione-legacy/package.nix { };
  firefox-emoji = callPackage ./by-name/fi/firefox-emoji/package.nix { };
  google-fonts-design = callPackage ./by-name/go/google-fonts-design/package.nix { };
  twemoji-color-font-optional = callPackage ./by-name/tw/twemoji-color-font-optional/package.nix { };
  mplus-outline-fonts-compatible =
    callPackage ./by-name/mp/mplus-outline-fonts-compatible/package.nix
      { };
  mattpocock-skills = callPackage ./by-name/ma/mattpocock-skills/package.nix { };
  mutant-standard-emoji = callPackage ./by-name/mu/mutant-standard-emoji/package.nix { };
  openai-skills = callPackage ./by-name/op/openai-skills/package.nix { };
  pstack-skills = callPackage ./by-name/ps/pstack-skills/package.nix { };
  ttf-ms-win11-auto = callPackage ./by-name/tt/ttf-ms-win11-auto/package.nix { };
}
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  apple-color-emoji = callPackage ./by-name/ap/apple-color-emoji/package.nix {
    apple-fonts = appleFonts;
  };
  bibata-cursors-hyprcursor = callPackage ./by-name/bi/bibata-cursors-hyprcursor/package.nix { };
  noctalia-dark-app-icons = callPackage ./by-name/no/noctalia-dark-app-icons/package.nix { };
  noctalia-personal = callPackage ./by-name/no/noctalia-personal/package.nix { };
}
// pkgs.lib.optionalAttrs (
  pkgs.stdenv.hostPlatform.isLinux && pkgs.stdenv.hostPlatform.isx86_64
) linuxX64Packages
// pkgs.lib.optionalAttrs (builtins.hasAttr pkgs.stdenv.hostPlatform.system (import ./by-name/op/openai-codex-desktop/source.nix).sources) codexDesktopPackages
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin darwinPackages
// pkgs.lib.optionalAttrs (
  pkgs.stdenv.hostPlatform.isAarch64 && pkgs.stdenv.hostPlatform.isDarwin
) darwinArmPackages
