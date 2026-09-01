{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  coreutils,
  librsvg,
  python3,
  xcursorgen,
}:

let
  pname = "bibata-cursors-hyprcursor";
  source = import ./source.nix;
  themes = [
    "Bibata-Modern-Amber"
    "Bibata-Modern-Amber-Right"
    "Bibata-Modern-Classic"
    "Bibata-Modern-Classic-Right"
    "Bibata-Modern-Ice"
    "Bibata-Modern-Ice-Right"
    "Bibata-Original-Amber"
    "Bibata-Original-Amber-Right"
    "Bibata-Original-Classic"
    "Bibata-Original-Classic-Right"
    "Bibata-Original-Ice"
    "Bibata-Original-Ice-Right"
  ];
in
stdenvNoCC.mkDerivation (_finalAttrs: {
  inherit pname;
  inherit (source) version;

  src = fetchFromGitHub source.src;

  nativeBuildInputs = [
    coreutils
    librsvg
    python3
    xcursorgen
  ];
  strictDeps = true;

  dontConfigure = true;
  enableParallelBuilding = true;

  # The upstream generator's fixed /tmp filename is safe only when themes are
  # rendered serially. Give every Python worker its own temporary SVG so Nix
  # can safely render variants in parallel.
  postPatch = ''
    substituteInPlace src/cursor_utils.py \
      --replace-fail \
        'import sys' \
        $'import os\nimport sys' \
      --replace-fail \
        "tmp = Path('/tmp/.cursor.0248.svg')" \
        "tmp = Path(os.environ['TMPDIR']) / f'.cursor.{os.getpid()}.svg'"
  '';

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" build

    build_theme() {
      ${python3.interpreter} src/cursor_utils.py \
        --hypr \
        --x11 \
        --theme "$1" \
        --out-dir "build/$1"
    }

    # `NIX_BUILD_CORES` is calculated by the client.  It can therefore reflect
    # a macOS host rather than the CPU allocation of an external Linux builder.
    # Use the actual build environment as the upper bound, then respect a
    # lower Nix-provided limit. This avoids overcommitting Determinate Nix's
    # default one-vCPU Linux VM while retaining parallel generation on native
    # multi-core Linux builders.
    max_jobs="$(${coreutils}/bin/nproc)"
    if [ -n "''${NIX_BUILD_CORES:-}" ] && [ "$NIX_BUILD_CORES" -lt "$max_jobs" ]; then
      max_jobs="$NIX_BUILD_CORES"
    fi
    running=0
    ${lib.concatMapStringsSep "\n" (theme: ''
      build_theme ${lib.escapeShellArg theme} &
      running=$((running + 1))
      if [ "$running" -ge "$max_jobs" ]; then
        wait -n
        running=$((running - 1))
      fi
    '') themes}
    wait

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    iconRoot="$out/share/icons"
    mkdir -p "$iconRoot"

    ${lib.concatMapStringsSep "\n" (theme: ''
      install -d "$iconRoot/${theme}"
      cp -R --no-preserve=mode,ownership "build/${theme}/${theme}/." "$iconRoot/${theme}/"
    '') themes}

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test "$(find "$out/share/icons" -mindepth 1 -maxdepth 1 -type d -name 'Bibata-*' | wc -l)" -eq ${toString (builtins.length themes)}

    ${lib.concatMapStringsSep "\n" (theme: ''
      themeRoot="$out/share/icons/${theme}"
      test -s "$themeRoot/manifest.hl"
      test -s "$themeRoot/index.theme"
      test -d "$themeRoot/hyprcursors"
      test -d "$themeRoot/cursors"
      test -e "$themeRoot/cursors/left_ptr"
      test "$(find "$themeRoot/hyprcursors" -name '*.hlc' -type f | wc -l)" -gt 0
    '') themes}

    runHook postInstallCheck
  '';

  passthru = { inherit themes; };

  meta = {
    description = "Bibata cursor themes with native Hyprcursor and XCursor fallbacks";
    homepage = "https://github.com/rtgiskard/bibata_cursor";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
