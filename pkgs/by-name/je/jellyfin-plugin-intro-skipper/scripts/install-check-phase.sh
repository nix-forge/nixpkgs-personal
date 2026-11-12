# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -s "$out/IntroSkipper.dll"
grep -aFq 'introskipper.js' "$out/IntroSkipper.dll"
grep -aFq 'introskipper.css' "$out/IntroSkipper.dll"
cmp LICENSE "$out/share/doc/@pname@/LICENSE"
plugin_test_dir=$(mktemp -d)
cp @pluginCheck@ "$plugin_test_dir/check_jellyfin_plugin.py"
cp @pluginTests@ "$plugin_test_dir/test_plugin_load.py"
cp @lifecycleTests@ "$plugin_test_dir/test_owned_cleanup.py"
PYTHONPATH="$plugin_test_dir" python3 -B -m unittest discover -s "$plugin_test_dir" -p 'test_*.py'
rm -r -- "$plugin_test_dir"
python3 @pluginCheck@ @jellyfinBinary@ "$out/IntroSkipper.dll" @version@ @jellyfinVersion@
runHook postInstallCheck
