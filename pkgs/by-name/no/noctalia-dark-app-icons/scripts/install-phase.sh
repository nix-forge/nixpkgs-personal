# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

icons="$out/share/icons/@iconThemeName@"
docs="$out/share/doc/@pname@"
mkdir -p "$icons/scalable/apps" "$icons/scalable/status" "$docs"
install -m644 @index_theme@ "$icons/index.theme"

cp @papirus_icon_theme@/share/icons/Papirus/64x64/apps/zen-browser.svg "$icons/scalable/apps/zen-browser.svg"
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
install -m644 @zoom_symbolic_svg@ "$icons/scalable/status/zoom-symbolic.svg"
install -m644 @sunshine_symbolic_svg@ "$icons/scalable/status/sunshine-symbolic.svg"

install -m644 LICENSE "$docs/SEVI-LICENSE"
install -m644 AUTHORS "$docs/SEVI-AUTHORS"
install -m644 @papirus_icon_theme_src@/LICENSE "$docs/PAPIRUS-LICENSE"
install -m644 @readme@ "$docs/README.md"
gtk-update-icon-cache --force "$icons"

runHook postInstall
