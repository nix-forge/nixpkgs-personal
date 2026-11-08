{ lib, mplus-outline-fonts }:
mplus-outline-fonts.githubRelease.overrideAttrs (old: {
  strictDeps = true;
  pname = "mplus-outline-fonts-compatible";
  meta = old.meta // {
    maintainers = [ ];
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "M PLUS outline fonts without files duplicated by Google Fonts";
  };
  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;
  # Google Fonts owns these identical filenames; retain the standalone styles.
  postInstall = (old.postInstall or "") + (builtins.readFile ./scripts/post-install.sh);
})
