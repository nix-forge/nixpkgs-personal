{ google-fonts, python3 }:
google-fonts.overrideAttrs (old: {
  strictDeps = true;
  pname = "google-fonts-design";
  meta = old.meta // {
    description = "Google Fonts catalog with duplicate primary font families excluded";
  };
  # These families have dedicated authoritative providers. The complete design
  # library remains available without a second copy of the primary roles.
  installPhase = old.installPhase + ''
    ${python3.withPackages (p: [ p.fonttools ])}/bin/python ${./finish.py} "$out" .
  '';
})
