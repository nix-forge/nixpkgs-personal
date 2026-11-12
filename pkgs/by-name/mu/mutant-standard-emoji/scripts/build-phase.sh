# shellcheck shell=bash
runHook preBuild
python -m zipfile -e @compiledFont_src@ artwork
cp @compiledFont@/share/fonts/truetype/MutantStandardEmoji.ttf font.ttf
chmod u+w font.ttf
python @normalize_shaping_py@ font.ttf artwork/emoji
runHook postBuild
