# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck

cmp "$src/LICENSE" "$out/share/doc/@pname@/LICENSE"

installed_skill_count="$(find "$out/share/agent-skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
test "$installed_skill_count" -gt 0
test "$installed_skill_count" -eq "$(find "$out/share/agent-skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l)"
while IFS= read -r skill_file; do
  grep -q '^---$' "$skill_file"
  grep -Eq '^name: mattpocock-[a-z0-9-]+$' "$skill_file"
done < <(find "$out/share/agent-skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | sort)

runHook postInstallCheck
