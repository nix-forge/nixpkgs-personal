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
  awk -v original="$skill_name" -v target="$target_name" '
    NR == 1 { if ($0 != "---") exit 1; print; next }
    !closed && $0 == "---" { closed = 1 }
    !closed && /^name:/ {
      if ($0 != "name: " original || ++names != 1) exit 1
      print "name: " target
      next
    }
    { print }
    END { if (!closed || names != 1) exit 1 }
  ' "$target_skill/SKILL.md" >"$target_skill/SKILL.md.new" || {
    echo "Expected one matching name in $source_skill/SKILL.md frontmatter" >&2
    exit 1
  }
  mv "$target_skill/SKILL.md.new" "$target_skill/SKILL.md"
  cp -R --no-preserve=ownership "$target_skill" "$skill_root/$target_name"
done < <(find "$src"/skills -mindepth 3 -maxdepth 3 -type f -name SKILL.md -print0 | sort -z)

runHook postInstall
