{
  lib,
  stdenvNoCC,
  fetchurl,
  fontconfig,
  python3,
  writers,
}:
let
  source = import ./source.nix;
  adobeLicense = fetchurl {
    url = "https://raw.githubusercontent.com/adobe-fonts/emojione-color/835b4ef8384f55ecf9abf7ecc943a3980884690b/LICENSE.md";
    hash = "sha256-p54R2CS+ck02LIwUO0EwiJxmzy70fxblrYO9eW3RgYM=";
  };
  baseUrl = "https://raw.githubusercontent.com/joypixels/emojione/${source.revision}";
  upstreamLicense = fetchurl {
    url = "${baseUrl}/LICENSE.md";
    hash = source.licenseHash;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "emojione-legacy";
  inherit (source) version;

  src = fetchurl {
    url = "${baseUrl}/assets/fonts/emojione-svg.otf";
    hash = source.fontHash;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  strictDeps = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 "$src" "$out/share/fonts/opentype/emojione-svg.otf"
    install -Dm444 ${upstreamLicense} "$out/share/doc/${finalAttrs.pname}/LICENSE.md"
    install -Dm444 ${adobeLicense} "$out/share/doc/${finalAttrs.pname}/LICENSE-ADOBE-MIT"
    cat > "$out/share/doc/${finalAttrs.pname}/README.txt" <<'EOF'
    Copyright 2016 Adobe Systems Incorporated.
    Emoji art supplied by EmojiOne. Original attribution: http://emojione.com
    Font distributed unmodified.
    Adobe's matching font: adobe-fonts/emojione-color commit
    835b4ef8384f55ecf9abf7ecc943a3980884690b. All font tables match except
    its added DSIG signature and the corresponding head checksum adjustment.
    Source: https://github.com/joypixels/emojione/tree/${source.revision}
    See LICENSE.md for upstream attribution and license terms.
    This historical font is for explicit family selection, not current Unicode coverage.
    EOF
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ fontconfig ];
  installCheckPhase = ''
    runHook preInstallCheck
    export XDG_CACHE_HOME="$TMPDIR/font-cache"
    mkdir -p "$XDG_CACHE_HOME/fontconfig"
    export FONTCONFIG_FILE="$TMPDIR/fonts.conf"
    cat > "$FONTCONFIG_FILE" <<EOF
    <fontconfig><cachedir>$XDG_CACHE_HOME/fontconfig</cachedir></fontconfig>
    EOF
    font="$out/share/fonts/opentype/emojione-svg.otf"
    cmp "$src" "$font"
    test "$(fc-scan --format '%{family}' "$font")" = 'EmojiOne'
    ${
      lib.getExe (
        writers.writePython3Bin "check-installed-assets" {
          libraries = [ python3.pkgs.fonttools ];
          flakeIgnore = [ "E501" ];
        } ./check-installed.py
      )
    } "$font"
    runHook postInstallCheck
  '';

  # Frozen compatibility release. Automatic updates could change the artwork,
  # family, or license; require an explicit source and license review instead.
  passthru.upstreamRevision = source.revision;

  meta = {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Legacy EmojiOne 2 color emoji font in SVG OpenType format";
    homepage = "https://github.com/joypixels/emojione";
    license = with lib.licenses; [
      mit
      cc-by-40
    ];
    platforms = lib.platforms.all;
  };
})
