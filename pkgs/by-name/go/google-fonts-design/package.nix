{
  replaceVars,
  google-fonts,
  python3,

}:
google-fonts.overrideAttrs (old: {
  strictDeps = true;
  pname = "google-fonts-design";
  meta = old.meta // {
    maintainers = [ ];
    description = "Google Fonts catalog with duplicate primary font families excluded";
  };
  # These families have dedicated authoritative providers. The complete design
  # library remains available without a second copy of the primary roles.
  installPhase = old.installPhase + ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        fontPython = python3.withPackages (p: [ p.fonttools ]);
        finish_py = "${./filter_font_providers.py}";
      }
    }
  '';
})
