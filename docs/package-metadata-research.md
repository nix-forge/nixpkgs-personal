# Package metadata and unfree policy research

Reviewed: 2026-09-08. Scope: all 39 public `nixpkgs-personal` outputs and their
consumer interfaces. Nixpkgs reference:
[`801bef6abd86b91e51083066b83fb354a11fc640`](https://github.com/NixOS/nixpkgs/tree/801bef6abd86b91e51083066b83fb354a11fc640),
the revision in [flake.lock](../flake.lock). This extends the earlier
[package design research](package-design-research.md) with license-policy
behavior and package-specific metadata evidence.

## Answer

Declare the license of the installed payload and let the consuming Nixpkgs
instance enforce its policy. Source availability, payment, redistribution,
and Nix build provenance describe different properties. A downloaded free
application can contain vendor-built native code. A source-built package can
remain unfree.

The review found incorrect blanket Apache declarations on both vendor skill
catalogs, an outdated LibreOffice license declaration, and an unfree fetcher
name that defeated the documented Windows-font allowlist. Other metadata needs
verification against the actual outputs, including inherited metadata on font
and desktop variants. The findings below identify the evidence and the intended
package behavior; [the package audit](package-audit.md) records implementation
and validation.

## Configuration belongs to the consumer

Nixpkgs rejects unfree licenses during evaluation, including evaluated build
dependencies. `allowUnfreePredicate` allows selected package names while keeping
the default rejection. Flakes require an explicit `config` when importing
Nixpkgs; ordinary user configuration files do not control that import.
[Nixpkgs configuration reference](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/doc/using/configuration.chapter.md)

At this pin, `config.allowUnfreePackages` also accepts a list of package names
and composes additively with the predicate. `allowUnfree = true` admits all
unfree packages and therefore bypasses either narrower selector. Names use
`lib.getName`, which prefers `pname` and otherwise parses `name`.
[Configuration options](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/top-level/config.nix),
[policy implementation](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/stdenv/generic/check-meta.nix)

The collection deliberately uses two interfaces. Its [direct flake](../flake.nix)
imports Nixpkgs with `allowUnfree = true`. Its [ordinary import](../default.nix)
and overlay instantiate against the caller's package set, preserving that
caller's policy. Consenting metadata discovery for the overlay does not replace
the incoming package scope. Keep this distinction explicit in examples.

Before the correction, allowing only `ttf-ms-win11-auto` still rejected its ISO
fetcher. The URL-derived source name parsed as `26200.6584.250915`, so the
package and its restricted input had different allowlist names. Give the
fetcher a stable package-related name. Composite packages such as `apple-fonts`
also evaluate their constituent unfree font derivations; selective consent must
cover those names. Preserve the restrictive source license metadata.
[Windows font recipe](../pkgs/by-name/tt/ttf-ms-win11-auto/package.nix),
[Apple font composition](../pkgs/by-name/ap/apple-fonts/package.nix)

Do not set `meta.unfree` manually to control installation. Nixpkgs derives it
from `meta.license`. Prefer license attributes over strings: the pinned
implementation explicitly documents a string-license detection defect.
`checkMeta = true` enables metadata type validation, but type validation cannot
establish that the declared license matches the payload.
[Metadata checking implementation](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/stdenv/generic/check-meta.nix)

## Licenses and redistribution

Use a specific `lib.licenses` value when available. A license list describes
differently licensed components, rather than automatically offering a choice
between licenses. `unfreeRedistributable` describes permission to redistribute
the derivation output. An accessible download does not establish that permission.
[Metadata license reference](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/doc/stdenv/meta.chapter.md#sec-meta-license)

Both `unfree` and `unfreeRedistributable` have `free = false`. The latter also
sets `redistributable = true`; it still requires unfree consent. Noncommercial
licenses such as `cc-by-nc-sa-40` are also unfree, even when they permit sharing
under their stated conditions. Retain that precise license for
`mutant-standard-emoji` instead of replacing it with a generic label.
[Pinned license definitions](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/lib/licenses/licenses.nix)

`preferLocalBuild` changes build placement. `allowSubstitutes = false` disables
normal substitution, subject to Nix's override setting. Neither attribute
prevents someone from uploading a store path. They are scheduling controls,
not a license enforcement mechanism. Preserve the existing restricted-font
settings, but do not add them universally to packages merely because those
packages are unfree. Cache publication requires a separate policy.
[Nix 2.35 derivation attributes](https://nix.dev/manual/nix/2.35/language/advanced-attributes.html#build-scheduling)

## Provenance and metadata fields

Use `binaryNativeCode` for downloaded desktop application or CLI binaries.
Use `fromSource` for the compiled Swift/C utilities and source-rendered cursor
artwork. The available source types distinguish native code, interpreter
bytecode, firmware, and obfuscated code. Their `isSource` flags support a policy
separate from license freedom.
[Source type definitions](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/lib/source-types.nix)

The pinned upstream Google Fonts recipe classifies downloaded fonts as
`binaryBytecode`. Retain this convention for prebuilt font files and inherited
font variants. A font generated locally from the supplied source artwork can
use `fromSource`. Missing provenance implies no known non-source component;
explicit provenance makes this collection easier to audit. It does not certify
every transitive dependency.
[Upstream Google Fonts recipe](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/by-name/go/google-fonts/package.nix)

`allowNonSource = false` rejects a package whose provenance contains a type
with `isSource = false`, unless its corresponding predicate allows the package.
This means accurately marked fonts and free vendor-built applications can be
rejected independently of `allowUnfree`.
[Provenance policy implementation](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/stdenv/generic/check-meta.nix)

| Field | Policy for this collection |
| --- | --- |
| `description`, `homepage` | Supply factual package information and the upstream project URL |
| `platforms`, `badPlatforms` | Describe supported targets and actual exclusions |
| `mainProgram` | Name an installed executable in `bin`; omit for data and library outputs |
| `maintainers` | Identify people who maintain this expression; do not invent ownership |
| `hydraPlatforms` | Set only when Hydra scheduling needs a narrower platform list |
| `broken`, `knownVulnerabilities` | Record demonstrated failures or known issues; do not add speculative values |
| `changelog`, `downloadPage`, identifiers | Add accurate useful values; omit guesses |

These fields describe different contracts. Metadata changes alone do not rebuild
the package.
[Metadata reference](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/doc/stdenv/meta.chapter.md)

Hydra uses `hydraPlatforms` when present, otherwise the package platforms minus
bad platforms. An inherited Linux-only Hydra list can become stale when a
variant broadens supported systems. Review inherited maintainers, changelogs,
program names and build flags whenever a variant changes their meaning. Keep
valid upstream licenses and provenance rather than recreating them without
evidence.
[Hydra platform selection](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/pkgs/top-level/release-lib.nix),
[local font override](../pkgs/by-name/tw/twemoji-color-font-optional/package.nix)

## Build settings

Keep `strictDeps = true`, native tools in `nativeBuildInputs`, and target
libraries in `buildInputs`. Disabling an irrelevant configure or build phase
is appropriate for copied data. `dontFixup` skips the entire fixup phase;
`dontStrip` skips stripping only. Choose the narrow setting needed by the
package. Preserve phase hooks in custom phases. Enable `doCheck` or
`doInstallCheck` when the corresponding tests exist; merely declaring a phase
does not enable it. Target-execution checks need a compatible build platform.
[Standard environment reference](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/doc/stdenv/stdenv.chapter.md)

For signed macOS vendor bundles, preserve the bundle bytes through installation
and skip generic fixup that would modify them. Locally modified or compiled
bundles need signing after their final mutations, as explained in the existing
[build standard](package-standard.md#build-contract) and
[Apple signing documentation](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html).

`passthru.tests` are separate derivations; ordinary package builds do not
automatically run them. Keep CI explicitly connected to those tests. Do not
force a GUI launch into a sandbox merely to populate `doCheck`.
[Passthru test documentation](https://github.com/NixOS/nixpkgs/blob/801bef6abd86b91e51083066b83fb354a11fc640/doc/stdenv/passthru.chapter.md)

## Package-specific license evidence

- The full `anthropic-skills` catalog includes document skills whose pinned notices contain
  custom copying, modification and distribution restrictions. A blanket
  Apache-2.0 declaration cannot describe that installed catalog. Preserve those
  notices and account for the restricted components in its license metadata.
  [Pinned document-skill notice](https://github.com/anthropics/skills/blob/41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f/skills/docx/LICENSE.txt)
  Its canvas-design directory also includes 54 prebuilt fonts with OFL notices.
  Record both `fromSource` and `binaryBytecode`, and include OFL in the license
  list. [Pinned canvas assets](https://github.com/anthropics/skills/tree/41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f/skills/canvas-design/canvas-fonts)
  The implemented default now selects 14 reviewed free examples. Document skills
  and `doc-coauthoring`, which lacks an explicit license, need a restricted
  selection. Metadata follows the selected contents; see the
  [package README](../pkgs/by-name/an/anthropic-skills/README.md).
- `openai-skills` includes Figma skills governed by Figma Developer Terms.
  Other per-skill licenses remain applicable. Its repository name does not make
  the entire catalog Apache-2.0.
  [Pinned Figma skill notice](https://github.com/openai/skills/blob/49f948faa9258a0c61caceaf225e179651397431/skills/.curated/figma/LICENSE.txt)
  Four Notion skills and `vercel-deploy` use MIT. Include it in the aggregate metadata.
  [Pinned Notion notice](https://github.com/openai/skills/blob/49f948faa9258a0c61caceaf225e179651397431/skills/.curated/notion-knowledge-capture/LICENSE.txt),
  [pinned Vercel notice](https://github.com/openai/skills/blob/49f948faa9258a0c61caceaf225e179651397431/skills/.curated/vercel-deploy/LICENSE.txt)
- LibreOffice identifies MPL-2.0 as its distribution license and points to the
  installed LICENSE for its mixed third-party components. Retain the complete
  vendor notices and replace the old LGPL-only declaration with MPL-2.0.
  [LibreOffice license statement](https://www.libreoffice.org/licenses/)
- Bibata's pinned README expressly permits GPLv3 or later. `gpl3Plus` is
  accurate. The source has no standalone LICENSE file, so retain its upstream
  README attribution and license statement in the output.
  [Pinned Bibata README](https://github.com/rtgiskard/bibata_cursor/blob/f4ccfe8abb63fddc7b3ce51a866fd8378395cb3d/readme.adoc)
- Vorssaint's pinned README identifies GPL-3.0-or-later. Keep `gpl3Plus` and
  the installed license notice.
  [Pinned Vorssaint README](https://github.com/vorssaint/vorssaint-utils/blob/b686b87f8933a69ac88e7a4f8d8976c083ed6cd1/README.md)
- Bitwarden's repository includes GPL and commercial code, but this release's
  desktop build selects the OSS entrypoint. Retain GPL-3.0-only for this desktop
  package; do not infer its classification from the server or browser modules.
  [Release license scope](https://github.com/bitwarden/clients/blob/desktop-v2026.8.0/LICENSE.txt),
  [desktop build configuration](https://github.com/bitwarden/clients/blob/desktop-v2026.8.0/apps/desktop/webpack.config.js)
- The reviewed T3 Code, LinearMouse and remindctl releases use MIT. Their vendor
  binaries still need `binaryNativeCode`. The remindctl ZIP contains only the
  executable, so packaging must obtain its notice separately.
  [T3 Code notice](https://github.com/pingdotgg/t3code/blob/v0.0.39/LICENSE),
  [LinearMouse notice](https://github.com/linearmouse/linearmouse/blob/v0.11.4/LICENSE),
  [remindctl notice](https://github.com/openclaw/remindctl/blob/v0.3.5/LICENSE)

## Validation and limits

Research inspected the pinned Nixpkgs implementation, all package recipe
metadata, existing package standards, and the linked upstream statements.
On `x86_64-linux`, evaluating the original Windows-font package with a predicate
allowing only `ttf-ms-win11-auto` reproduced a rejected unfree ISO dependency.
Reading its metadata alone succeeded, showing why a successful metadata query
does not establish that the full derivation can instantiate.

This research did not build the desktop system or launch GUI applications.
Evaluation cannot establish native behavior, complete copyright ownership,
or redistribution permission beyond the upstream statements reviewed here.
Use the [package audit](package-audit.md) for the completed package checks and
their platform limits.
