{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  papirus-icon-theme,
  gtk3,
  librsvg,
  python3,
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
    runHook preInstall

    icons="$out/share/icons/${iconThemeName}"
    docs="$out/share/doc/${finalAttrs.pname}"
    mkdir -p "$icons/scalable/apps" "$docs"
    install -m644 ${./index.theme} "$icons/index.theme"

    cp ${papirus-icon-theme}/share/icons/Papirus/64x64/apps/zen-browser.svg "$icons/scalable/apps/zen-browser.svg"
    substituteInPlace "$icons/scalable/apps/zen-browser.svg" \
      --replace-fail '#e3e1d4' '#25272d'
    cp src/apps/scalable/chat-gpt.svg "$icons/scalable/apps/chatgpt.svg"
    substituteInPlace "$icons/scalable/apps/chatgpt.svg" \
      --replace-fail '#74aa9c' '#25272d' \
      --replace-fail '#96c0b3' '#3a3d45'
    cp src/apps/scalable/visual-studio-code.svg "$icons/scalable/apps/visual-studio-code.svg"
    # Nixpkgs' VS Code desktop entry uses Icon=vscode, while other builds use code.
    ln -s visual-studio-code.svg "$icons/scalable/apps/code.svg"
    ln -s visual-studio-code.svg "$icons/scalable/apps/vscode.svg"

    install -m644 LICENSE "$docs/SEVI-LICENSE"
    install -m644 AUTHORS "$docs/SEVI-AUTHORS"
    install -m644 ${papirus-icon-theme.src}/LICENSE "$docs/PAPIRUS-LICENSE"
    install -m644 ${./README.md} "$docs/README.md"
    gtk-update-icon-cache --force "$icons"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    librsvg
    (python3.withPackages (p: [ p.pillow ]))
  ];
  installCheckPhase = ''
    runHook preInstallCheck
    icons="$out/share/icons/${iconThemeName}"
    gtk-update-icon-cache --validate "$icons"
    cmp "$icons/scalable/apps/code.svg" "$icons/scalable/apps/visual-studio-code.svg"
    cmp "$icons/scalable/apps/vscode.svg" "$icons/scalable/apps/visual-studio-code.svg"
    for icon in chatgpt zen-browser vscode; do
      for size in 16 24 32 42 84; do
        rsvg-convert --width "$size" --height "$size" \
          --output "$TMPDIR/$icon-$size.png" "$icons/scalable/apps/$icon.svg"
      done
    done
    python3 - "$TMPDIR" "$icons" <<'PY'
    import configparser
    import sys
    from pathlib import Path
    from PIL import Image

    renders, icons = map(Path, sys.argv[1:])
    theme = configparser.ConfigParser()
    theme.read(icons / "index.theme")
    assert theme["Icon Theme"]["Inherits"].split(",") == ["Papirus-Dark", "hicolor"]
    assert theme["scalable/apps"]["Context"] == "Applications"
    for icon in ("chatgpt", "zen-browser", "vscode"):
        for size in (16, 24, 32, 42, 84):
            with Image.open(renders / f"{icon}-{size}.png") as image:
                image = image.convert("RGBA")
                assert image.size == (size, size)
                pixels = list(image.get_flattened_data())
                opaque = [(r, g, b) for r, g, b, a in pixels if a > 240]
                assert len(opaque) > size * size * 0.4, (icon, "missing artwork")
                assert image.getpixel((0, 0))[3] == 0, (icon, "opaque canvas")
                dark = sum(max(rgb) < 100 for rgb in opaque)
                visible = sum(max(rgb) > 150 for rgb in opaque)
                assert dark > len(opaque) * 0.3, (icon, "background is not dark")
                assert visible > len(opaque) * 0.05, (icon, "logo lacks contrast")
                if icon == "zen-browser":
                    assert any(r > 180 and r > g * 1.5 for r, g, b in opaque)
                if icon == "vscode":
                    assert any(b > 100 and b > r * 1.5 for r, g, b in opaque)
    PY
    runHook postInstallCheck
  '';

  # This is a locally versioned composition, not a Sevi release. Source and
  # color changes need artwork/license review rather than unattended updates.
  passthru = {
    inherit iconThemeName;
    seviRevision = source.sevi.rev;
  };

  meta = {
    description = "Dark application icon variants for ChatGPT, Zen and Visual Studio Code";
    homepage = "https://github.com/nix-forge/nixpkgs-personal";
    license = with lib.licenses; [
      cc-by-sa-40
      gpl3Only
    ];
    platforms = lib.platforms.linux;
  };
})
