# Windows font payload

The package pins Microsoft's versioned Enterprise Evaluation ISO and its SHA-256.
`manifest.json` records every extracted font file's SHA-256 and named PostScript
faces. The installer verifies the extracted payload and the installed copy using
the same inspector as apple-fonts. It retains Microsoft's license.rtf.

The updater resolves the published ISO, and generates the next inventory before
writing either source pin. Review source.nix and manifest.json together. The
build rejects a manifest from a different release or changed payload. It never
executes Windows installer code. Run the updater from the personal repository:

```text
nix develop .#apple-fonts -c python pkgs/by-name/tt/ttf-ms-win11-auto/update.py --check
```

Both the source and output are unfree and disable substitution. These attributes
do not prevent uploads; this repository's CI has no font cache publishing step.
Do not add proprietary outputs to a publishing hook without a separate policy.

## License scope

The Enterprise evaluation download is not a general font license. Microsoft's
[font FAQ](https://learn.microsoft.com/en-us/typography/fonts/font-faq) distinguishes
Windows use, document embedding, copying to other systems, and redistribution.
A user-supplied ISO or a Windows license does not by itself establish every one
of those permissions. Read the retained `license.rtf` for this exact edition.
The recipe is publicly shared instructions; it does not itself publish the ISO
or extracted fonts. Hosted CI evaluates the recipe without performing extraction
pending a reviewed grant for that hosted activity. Local builds remain available.
