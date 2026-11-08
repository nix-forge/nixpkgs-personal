# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
install -Dm644 packaging/linux/ai.storyteller.@pname@.desktop \
  "$out/share/applications/ai.storyteller.@pname@.desktop"
substituteInPlace "$out/share/applications/ai.storyteller.@pname@.desktop" \
  --replace-fail "Exec=@pname@ " "Exec=$out/bin/@pname@ " \
  --replace-fail "TryExec=@pname@" "TryExec=$out/bin/@pname@"
mkdir -p "$out/share/icons"
cp -r assets/app-icon/hicolor "$out/share/icons/"
install -Dm644 packaging/linux/ai.storyteller.@pname@.mime.xml \
  "$out/share/mime/packages/ai.storyteller.@pname@.xml"
mkdir -p "$out/share/metainfo"
substitute packaging/linux/ai.storyteller.@pname@.metainfo.xml.in \
  "$out/share/metainfo/ai.storyteller.@pname@.metainfo.xml" \
  --subst-var-by VERSION "@version@" --subst-var-by DATE "@releaseDate@"
# Release kind and date come from the immutable source metadata.
substituteInPlace "$out/share/metainfo/ai.storyteller.@pname@.metainfo.xml" \
  --replace-fail '<release version="@version@"' '<release type="@releaseType@" version="@version@"'
for executable in "$out/bin/"*; do
  wrapProgram "$executable" \
    --prefix LD_LIBRARY_PATH : "@runtimeLibraryPath@" \
    --prefix PATH : "@desktopToolsPath@"
done
