# shellcheck shell=bash
runHook preBuild
python @prepare_py@ emoji
nanoemoji --color_format glyf_colr_1 \
  --family 'Mutant Standard Emoji' \
  --output_file MutantStandardEmoji.ttf \
  --width 1024 --ascender 950 --descender -250 \
  --version_major 2024 --version_minor 6 \
  --noexec_ninja emoji/*.svg
ninja -C build -j "$NIX_BUILD_CORES"
python @finish_py@ build/MutantStandardEmoji.ttf @source_version@
runHook postBuild
