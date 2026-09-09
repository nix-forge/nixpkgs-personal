{
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
  nativeInstallCheckInputs = [ librsvg ];
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
    ${
      lib.getExe (
        writers.writePython3Bin "check-installed-assets" {
          libraries = [ python3.pkgs.pillow ];
          flakeIgnore = [ "E501" ];
        } ./check-installed.py
      )
    } "$TMPDIR" "$icons"
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
