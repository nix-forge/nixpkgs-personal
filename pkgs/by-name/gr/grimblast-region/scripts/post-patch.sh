# shellcheck shell=bash
# Region capture should not offer clickable monitor rectangles.
substituteInPlace grimblast --replace-fail 'slurp -o ' 'slurp '
