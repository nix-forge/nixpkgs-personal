{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  coreutils,
  librsvg,
  python3,
  xcursorgen,
}:

let
  pname = "bibata-cursors-hyprcursor";
  source = import ./source.nix;
  licenseText = fetchurl {
    url = "https://raw.githubusercontent.com/spdx/license-list-data/v3.27.0/text/GPL-3.0-or-later.txt";
    hash = "sha256-+5gWaMGKJ54oX8TYP7oeg2zITdTapzyWl9PP0tispuA=";
  };
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
  postPatch = builtins.readFile ./scripts/post-patch.sh;

  buildPhase = ''
    source ${
      replaceVars ./scripts/build-phase.sh {
        python3_interpreter = python3.interpreter;
        inherit coreutils;
        buildThemes = lib.concatMapStringsSep "\n" (theme: ''
          build_theme ${lib.escapeShellArg theme} &
          pids+=("$!")
          if [ "''${#pids[@]}" -ge "$max_jobs" ]; then
            for pid in "''${pids[@]}"; do
              wait "$pid"
            done
            pids=()
          fi
        '') themes;
      }
    }
  '';

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit pname;
        inherit licenseText;
        installThemes = lib.concatMapStringsSep "\n" (theme: ''
          source ${replaceVars ./scripts/install-cursor-theme.sh { inherit theme; }}
        '') themes;
      }
    }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit pname;
        toString_builtins_length_themes = toString (builtins.length themes);
        checkThemes = lib.concatMapStringsSep "\n" (theme: ''
          source ${replaceVars ./scripts/check-cursor-theme.sh { inherit theme; }}
        '') themes;
      }
    }
  '';

  passthru = { inherit themes; };

  meta = {
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Bibata cursor themes with native Hyprcursor and XCursor fallbacks";
    homepage = "https://github.com/rtgiskard/bibata_cursor";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
