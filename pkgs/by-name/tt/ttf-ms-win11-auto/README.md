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
