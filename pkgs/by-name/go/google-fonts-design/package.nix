{ google-fonts, python3 }:
google-fonts.overrideAttrs (old: {
  pname = "google-fonts-design";
  # These families have dedicated authoritative providers. The complete design
  # library remains available without a second copy of the primary roles.
  installPhase = old.installPhase + ''
    ${python3.withPackages (p: [ p.fonttools ])}/bin/python ${./finish.py} "$out" .
  '';
})
