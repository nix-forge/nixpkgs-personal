# shellcheck shell=bash
# shellcheck disable=SC2154
runHook preInstall
install -Dm755 "$(cat clipboard-test-path)" "$out/libexec/pdfcraft-native-clipboard-tests"
wrapProgram "$out/libexec/pdfcraft-native-clipboard-tests" \
  --prefix LD_LIBRARY_PATH : @runtime_library_path@ \
  --prefix PATH : @fontconfig_path@
mkdir -p "$out/share/doc/pdfcraft-native-clipboard-tests/licenses"
find -L . -type f \( -iname '*license*' -o -name 'OFL*' -o -name 'UFL*' -o -name 'Hack-Regular.txt' -o -name 'COPYING*' -o -name 'NOTICE*' -o -iname '*attribution*' \) \
  -not -path './target/*' -print0 | while IFS= read -r -d "" notice; do
  install -Dm644 "$notice" "$out/share/doc/pdfcraft-native-clipboard-tests/licenses/source/$notice"
done
(
  cd @cargo_deps@ || exit
  find -L . -type f \( -iname '*license*' -o -name 'OFL*' -o -name 'UFL*' -o -name 'Hack-Regular.txt' -o -name 'COPYING*' -o -name 'NOTICE*' \) \
    -print0 | while IFS= read -r -d "" notice; do
    install -Dm644 "$notice" "$out/share/doc/pdfcraft-native-clipboard-tests/licenses/dependencies/$notice"
  done
)
(
  cd @fonts@ || exit
  find -L . -type f -not -iname '*.ttf' -not -iname '*.otf' -print0 |
    while IFS= read -r -d "" notice; do
      install -Dm644 "$notice" "$out/share/doc/pdfcraft-native-clipboard-tests/licenses/font-input/$notice"
    done
)
cp @model_notice@ "$out/share/doc/pdfcraft-native-clipboard-tests/licenses/"
runHook postInstall
