# openai-skills

The package installs selected skills below `share/agent-skills`. Its directory
can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`.

```nix
# Select an exact set of reviewed upstream names.
pkgs.openai-skills.override { selectedSkills = [ "pdf" ]; }

# Select only components with reviewed free licenses.
pkgs.openai-skills.override { includeRestricted = false; }
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

The default retains all 39 curated skills, including eight Figma skills.
The free selection has 31 skills: Apache-2.0 examples and MIT-licensed Notion
and Vercel skills. It does not require unfree consent. Full selections do.

The [pinned Figma notice](https://github.com/openai/skills/blob/49f948faa9258a0c61caceaf225e179651397431/skills/.curated/figma/LICENSE.txt)
incorporates the [Figma Developer Terms](https://www.figma.com/legal/developer-terms/).
These provide limited integration-related permissions; their early-access
provisions limit Beta resources to testing. Availability in this catalog does
not establish unrestricted use or redistribution. All eight Figma directories,
including uppercase `LICENSE.TXT` notices, are covered by the inventory.

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
