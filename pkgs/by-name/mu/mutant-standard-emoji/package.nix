{
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
  fontconfig,
}:
let
  source = import ./source.nix;
  python = python3.withPackages (ps: [
    ps.nanoemoji
    ps.uharfbuzz
  ]);
  checkFont = artwork: ''
    runHook preInstallCheck
    export FONTCONFIG_FILE=${./fonts.conf}
    export XDG_CACHE_HOME="$TMPDIR/font-cache"
    mkdir -p "$XDG_CACHE_HOME"
    font="$out/share/fonts/truetype/MutantStandardEmoji.ttf"
    family=$(fc-scan --format '%{family}' "$font" 2> "$TMPDIR/fc-scan.log")
    # fc-scan can exit successfully after configuration errors.
    if [ -s "$TMPDIR/fc-scan.log" ]; then
      cat "$TMPDIR/fc-scan.log" >&2
      exit 1
    fi
    test "$family" = 'Mutant Standard Emoji'
    python ${./check.py} "$font" ${artwork}
    runHook postInstallCheck
  '';
  # Keep vector compilation separate from the inexpensive encoding pass.
  compiledFont = stdenvNoCC.mkDerivation (_finalAttrs: {
    pname = "mutant-standard-emoji";
    inherit (source) version;

    src = fetchurl {
      url = "https://mutant.tech/dl/${source.version}/mtnt_${source.version}_code_svg.zip";
      hash = source.artworkHash;
    };

    strictDeps = true;
    nativeBuildInputs = [ python ];
    unpackPhase = ''
      runHook preUnpack
      python -m zipfile -e "$src" source
      cd source
      runHook postUnpack
    '';
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      python ${./prepare.py} emoji
      nanoemoji --color_format glyf_colr_1 \
        --family 'Mutant Standard Emoji' \
        --output_file MutantStandardEmoji.ttf \
        --width 1024 --ascender 950 --descender -250 \
        --version_major 2024 --version_minor 6 \
        --noexec_ninja emoji/*.svg
      ninja -C build -j "$NIX_BUILD_CORES"
      python ${./finish.py} build/MutantStandardEmoji.ttf ${source.version}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm444 build/MutantStandardEmoji.ttf \
        "$out/share/fonts/truetype/MutantStandardEmoji.ttf"
      doc="$out/share/doc/mutant-standard-emoji"
      mkdir -p "$doc"
      cp license.txt credits.txt 'design credits.txt' "$doc/"
      cp ${./README.md} "$doc/README.md"
      runHook postInstall
    '';

    doInstallCheck = true;
    nativeInstallCheckInputs = [ fontconfig ];
    installCheckPhase = checkFont "emoji";

    meta = {
      sourceProvenance = [ lib.sourceTypes.fromSource ];
      description = "Mutant Standard emoji artwork compiled as a scalable COLRv1 font";
      homepage = "https://mutant.tech";
      license = lib.licenses.cc-by-nc-sa-40;
      platforms = lib.platforms.unix;
    };
  });
in
stdenvNoCC.mkDerivation {
  inherit (compiledFont) pname version meta;
  strictDeps = true;
  nativeBuildInputs = [ python ];
  dontUnpack = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    python -m zipfile -e ${compiledFont.src} artwork
    cp ${compiledFont}/share/fonts/truetype/MutantStandardEmoji.ttf font.ttf
    chmod u+w font.ttf
    python ${./normalize-shaping.py} font.ttf artwork/emoji
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -R ${compiledFont} "$out"
    chmod -R u+w "$out"
    install -m444 font.ttf "$out/share/fonts/truetype/MutantStandardEmoji.ttf"
    install -m444 ${./encoding.md} "$out/share/doc/mutant-standard-emoji/encoding.md"
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ fontconfig ];
  installCheckPhase = checkFont "artwork/emoji";

  passthru = { inherit compiledFont; };
}
