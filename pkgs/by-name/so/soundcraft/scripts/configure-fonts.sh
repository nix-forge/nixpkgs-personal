# shellcheck shell=bash
# Keep regular and bold symbol fallbacks in the runtime closure.
substituteInPlace crates/ui-egui/src/fonts.rs \
  --replace-fail '@soundcraftDejaVu@' '@dejavuFonts@'
