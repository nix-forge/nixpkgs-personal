# shellcheck shell=bash
# shellcheck disable=SC2154
package_root="$out/lib/node_modules/rea-agents"
mkdir -p "$skills/share/agent-skills" "$skills/share/licenses/rea"
cp -R "$package_root/skills/." "$skills/share/agent-skills/"
install -m644 LICENSE "$skills/share/licenses/rea/LICENSE"
rm -r "$package_root/skills"
ln -s "$skills/share/agent-skills" "$package_root/skills"
