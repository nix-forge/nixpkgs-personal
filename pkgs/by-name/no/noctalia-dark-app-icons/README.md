# Noctalia dark application icons

An application icon overlay for dark desktops. It supplies ChatGPT, Zen Browser
and Visual Studio Code artwork, plus symbolic Zoom and Sunshine tray logos. It
inherits every other icon from upstream Papirus-Dark and hicolor. It works with
any freedesktop icon-theme consumer; Noctalia is not a package dependency.

Select `Noctalia-Apps-Dark` as the icon theme wherever this artwork is wanted.
The desktop configuration owns theme selection. The package does not modify
desktop entries, user settings or system services.

## Artwork and licenses

- ChatGPT and Visual Studio Code come from
  [Sevi](https://github.com/TaylanTatli/Sevi/tree/73bcbd5991ed7b9270fbe7d3944ac24208e6b726).
  Sevi credits Taylan Tatli, Reversal by yeyushengfan258 and Luv by Uri Herrera.
  Its license is CC-BY-SA-4.0; its README also identifies the Reversal base as
  GPL-3.0. `SEVI-LICENSE` and `SEVI-AUTHORS` accompany the installed artwork.
  This package changes ChatGPT's green background to a charcoal gradient.
  Visual Studio Code artwork is unmodified.
- Zen comes from the upstream Nixpkgs `papirus-icon-theme` package, by the
  [Papirus Development Team](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme).
  This package changes its cream background to charcoal and retains the orange
  logo. The GPL-3.0 license is installed as `PAPIRUS-LICENSE`.
- The Zoom tray symbol uses the camera shape from Papirus's Zoom icon without
  its blue background. The Sunshine tray symbol uses the logo paths from
  LizardByte Sunshine's GPL-3.0 icon. Noctalia tints both with the bar foreground.

The package includes `code` and `vscode` aliases for Visual Studio Code. It does
not claim dark artwork for applications beyond these three.

## Maintenance

`source.nix` pins the Sevi revision and source hash. Papirus follows the consumer's
upstream Nixpkgs revision. The local package version tracks this composition;
there is no unattended updater because source changes require an artwork and
license review. Color substitutions fail if the expected upstream colors change.

Compute Sevi's unpacked source hash on a case-sensitive filesystem using the
package's fetcher. Its icon aliases include names differing only by case.
Case-insensitive extraction loses aliases and produces a different hash; that
hash does not describe the complete upstream source. The pinned hash retains
every alias, as required by the Linux build.

Native package builds validate the icon cache and aliases, render all three app icons
at 16, 24, 32, 42 and 84 pixels for taskbars and docks, and check transparency,
dark background coverage and logo
contrast. The Zen orange and VS Code blue are also checked. Recheck visual quality
at dock size when updating either upstream source.
The build also renders the two tray symbols at 16, 24 and 32 pixels and checks
their transparency and monochrome output.
