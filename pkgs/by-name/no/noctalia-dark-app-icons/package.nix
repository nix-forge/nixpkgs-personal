{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  papirus-icon-theme,
  gtk3,
  librsvg,
  python3,
  writers,
}:
let
  source = import ./source.nix;
  iconThemeName = "Noctalia-Apps-Dark";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "noctalia-dark-app-icons";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "TaylanTatli";
    repo = "Sevi";
    inherit (source.sevi) rev hash;
  };

  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;
  nativeBuildInputs = [ gtk3 ];
  propagatedBuildInputs = [ papirus-icon-theme ];
  # Papirus propagates Breeze/Qt; this package contains only icon data.
  dontWrapQtApps = true;
  dontDropIconThemeCache = true;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit iconThemeName;
        inherit (finalAttrs) pname;
        index_theme = "${./index.theme}";
        papirus_icon_theme = papirus-icon-theme;
        zoom_symbolic_svg = "${./zoom-symbolic.svg}";
        sunshine_symbolic_svg = "${./sunshine-symbolic.svg}";
        papirus_icon_theme_src = papirus-icon-theme.src;
        readme = "${./README.md}";
      }
    }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ librsvg ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit iconThemeName;
        assetsCheck = lib.getExe (
          writers.writePython3Bin "check-installed-assets" {
            libraries = [ python3.pkgs.pillow ];
            flakeIgnore = [ "E501" ];
          } ./check_installed.py
        );
      }
    }
  '';

  # This is a locally versioned composition, not a Sevi release. Source and
  # color changes need artwork/license review rather than unattended updates.
  passthru = {
    inherit iconThemeName;
    seviRevision = source.sevi.rev;
  };

  meta = {
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Dark application icons and symbolic Zoom and Sunshine tray logos";
    homepage = "https://github.com/nix-forge/nixpkgs-personal";
    license = with lib.licenses; [
      cc-by-sa-40
      gpl3Only
    ];
    platforms = lib.platforms.linux;
  };
})
