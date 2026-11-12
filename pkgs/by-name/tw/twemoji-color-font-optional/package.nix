{
  lib,
  stdenvNoCC,
  twemoji-color-font,
}:
(twemoji-color-font.override { stdenv = stdenvNoCC; }).overrideAttrs (old: {
  strictDeps = true;
  pname = "twemoji-color-font-optional";
  # This wrapper follows the Nixpkgs pin; upstream's nix-update command cannot
  # update a source defined outside this package directory.
  passthru = lib.removeAttrs (old.passthru or { }) [ "updateScript" ];
  meta = old.meta // {
    maintainers = [ ];
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Twitter color emoji font without default Fontconfig substitutions";
    platforms = lib.platforms.unix;
  };
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;
  # Provide the family explicitly without replacing normal text or Noto emoji.
  postInstall = (old.postInstall or "") + (builtins.readFile ./scripts/post-install.sh);
})
