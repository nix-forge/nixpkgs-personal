# Grimblast region variant

This package changes Grimblast's region selector to use freeform `slurp`
selection without clickable monitor rectangles. It keeps the upstream
Grimblast package and dependencies on Linux. Unsupported platforms expose
metadata without evaluating Grimblast's Linux-only inputs. Review the matched
`slurp -o` command when updating Nixpkgs; `--replace-fail` deliberately stops
the build if upstream changes it. Updates follow the consuming Nixpkgs pin.
