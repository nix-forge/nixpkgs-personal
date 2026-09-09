# apple-new-york

Apple's developer font distribution, pinned by URL, SHA-256, and a complete
font inventory in `source.json`. This directory builds independently with
upstream Nixpkgs and installs no default font selection policy.

```sh
nix build .#apple-new-york
```

The build verifies the extracted and installed font hashes and PostScript face
names. It preserves upstream notices and installs its manifest under `share/doc`.
Apple's font license applies; this is an opt-in unfree package with substitution
disabled. A content hash does not guarantee Apple retains a download forever.

Updates require reviewing this package's `source.json` against the versioned
Apple download and rebuilding to check every recorded font. There is no
unattended updater. Python handles archive inspection; Nix declares the build.

## License scope

Publishing this recipe does not distribute the downloaded fonts. The build
preserves the font bytes and the license accompanying this particular Apple
distribution. Apple's developer-font grant is scoped to permitted Apple-platform
interface mockups, subject to its eligibility and other conditions. It does not
establish a general desktop, web-embedding, modification, or redistribution grant.
A Linux packaging target describes technical support, not a broader license.
See [Apple's developer-font downloads and terms](https://developer.apple.com/fonts/).
The installed license is the source of the conditions for this exact payload.

Hosted CI evaluates this recipe without extracting the proprietary payload.
That is repository policy while the hosted-build permission is unresolved,
not a conclusion that publication of the recipe is prohibited.
