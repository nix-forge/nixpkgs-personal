# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

skill_root="$out/share/agent-skills"
mkdir -p "$skill_root"
install -Dm644 "$src/LICENSE" "$out/share/doc/@pname@/LICENSE"
while IFS= read -r -d "" skill_file; do
  source_skill="${skill_file%/SKILL.md}"
  skill_name="$(basename "$source_skill")"
  target_name="mattpocock-$skill_name"
  target_skill="$TMPDIR/$target_name"
  cp -R --no-preserve=ownership "$source_skill" "$target_skill"
  chmod -R u+w "$target_skill"
  sed -i "0,/^name: .*$/s//name: $target_name/" "$target_skill/SKILL.md"
  cp -R --no-preserve=ownership "$target_skill" "$skill_root/$target_name"
done < <(find "$src"/skills -mindepth 3 -maxdepth 3 -type f -name SKILL.md -print0 | sort -z)

runHook postInstall
