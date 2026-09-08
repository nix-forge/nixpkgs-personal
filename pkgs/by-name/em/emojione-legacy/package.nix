{
  lib,
  stdenvNoCC,
  fetchurl,
  fontconfig,
  python3,
}:
let
  source = import ./source.nix;
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
    cat > "$out/share/doc/${finalAttrs.pname}/README.txt" <<'EOF'
    EmojiOne artwork by EmojiOne. Font distributed unmodified.
    Source: https://github.com/joypixels/emojione/tree/${source.revision}
    See LICENSE.md for upstream attribution and license terms.
    This historical font is for explicit family selection, not current Unicode coverage.
    EOF
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    fontconfig
    (python3.withPackages (p: [ p.fonttools ]))
  ];
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
    python3 - "$font" <<'PY'
    import sys
    from fontTools.ttLib import TTFont

    with TTFont(sys.argv[1]) as font:
        sample = "😀😁😂😃😄😅😆😇😈😉😊😋😌😍"
        cmap = font.getBestCmap()
        assert all(ord(char) in cmap and font.getGlyphID(cmap[ord(char)]) for char in sample)
        documents = font["SVG "].docList
        assert documents
        assert all(
            any(doc.startGlyphID <= font.getGlyphID(cmap[ord(char)]) <= doc.endGlyphID
                for doc in documents)
            for char in sample
        )
    PY
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
