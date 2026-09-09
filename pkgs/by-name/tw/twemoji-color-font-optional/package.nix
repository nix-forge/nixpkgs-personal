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
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Twitter color emoji font without default Fontconfig substitutions";
    platforms = lib.platforms.unix;
  };
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    cmp "$src/LICENSE-CC-BY.txt" "$out/share/doc/twemoji-color-font-optional/LICENSE-CC-BY.txt"
    cmp "$src/LICENSE-MIT.txt" "$out/share/doc/twemoji-color-font-optional/LICENSE-MIT.txt"
    test "$(find "$out/share/fonts" -type f | wc -l)" -gt 0
    test ! -e "$out/etc/fonts"
    runHook postInstallCheck
  '';
  # Provide the family explicitly without replacing normal text or Noto emoji.
  postInstall = (old.postInstall or "") + ''
    install -Dm644 LICENSE-CC-BY.txt "$out/share/doc/twemoji-color-font-optional/LICENSE-CC-BY.txt"
    install -Dm644 LICENSE-MIT.txt "$out/share/doc/twemoji-color-font-optional/LICENSE-MIT.txt"
    rm -rf "$out/etc/fonts"
  '';
})
