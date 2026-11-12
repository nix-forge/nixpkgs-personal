# anthropic-skills

The package installs selected skills below `share/agent-skills`. Its directory
can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`.

```nix
# Select an exact set of reviewed upstream names.
pkgs.anthropic-skills.override { selectedSkills = [ "pdf" ]; }

# Select only components with reviewed free licenses.
pkgs.anthropic-skills.override { includeRestricted = false; }
```

`availableSkills`, `freeSkills`, and `restrictedSkills` are exposed through
passthru. An explicit `selectedSkills` list takes precedence over
`includeRestricted`. Unknown, duplicate, and empty selections are rejected.
The output license list and font provenance follow the selected contents.
The source fetch still retrieves the pinned upstream repository for validation;
selection controls installed skills, not which files the upstream archive contains.

Free skills keep the existing provider-prefixed directory and skill names.
A modification notice records that change. Restricted skills keep a prefixed
directory but retain their original `SKILL.md` name and all other bytes. An
integration must use the original name for these skills. Namespaces do not
expand any license grant. Every selected skill retains its upstream notices.

The default installs the 18 skills with reviewed Apache-2.0 licenses,
including the four document skills and canvas-design's OFL fonts. The document
skills can also be selected with
`selectedSkills = [ "docx" "pdf" "pptx" "xlsx" ];`.
`includeRestricted = true` selects all 19 skills, including `doc-coauthoring`,
which lacks an explicit per-skill license at this pin and is conservatively
classified unfree. It is preserved unchanged pending clarification.

At the [reviewed revision](https://github.com/anthropics/skills/tree/2c5958ecac7cee2b583967a2c4981d0f4a75c579),
the document skills' previous custom terms have been replaced with complete
[Apache-2.0 notices](https://github.com/anthropics/skills/blob/2c5958ecac7cee2b583967a2c4981d0f4a75c579/skills/docx/LICENSE.txt).
Their definitions now refer to those notices without the former proprietary
classification. The catalog records the reviewed notice and definition hashes.

## Updating the inventory

`catalog.json` records the reviewed license mapping, hashes of skill definitions
and notices, and prebuilt font paths. The build rejects additions, removals,
changed definitions or notices, and changed font inventories before installing.
This is a review trigger, not automated legal analysis of every source file.

Run `python3 update.py --dry-run` to preview an update. The updater validates the
fetched source against the inventory before changing `source.nix`. On a mismatch,
run `python3 catalog.py inspect /path/to/fetched-source`, review changed content
and terms, and update the relevant observations and license assignments in
`catalog.json`. Then rerun the updater. Do not automatically accept new hashes.

The build checks that restricted files and notices remain byte-identical.
