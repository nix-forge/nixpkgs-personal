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

- The current `anthropic-skills` document skills carry complete Apache-2.0 notices,
  replacing the historical custom copying, modification and distribution terms.
  [Reviewed document-skill notice](https://github.com/anthropics/skills/blob/2c5958ecac7cee2b583967a2c4981d0f4a75c579/skills/docx/LICENSE.txt)
  Its canvas-design directory also includes 54 prebuilt fonts with OFL notices.
  Record both `fromSource` and `binaryBytecode`, and include OFL in the license
  list. [Pinned canvas assets](https://github.com/anthropics/skills/tree/41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f/skills/canvas-design/canvas-fonts)
  The implemented default selects 18 reviewed free skills, including the four
  document skills. `doc-coauthoring`, which lacks an explicit license, needs a restricted
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

## Application metadata review, 2026-10-12

Reference pin: `151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4`, from the owning package repository lock. These findings guide implementation; static research does not establish GUI behavior or bundle launchability.

### Nix metadata

The contribution guide requires factual descriptions, capitalization, no leading article, no package-name self-reference and no final punctuation. It requires the actual payload license, non-source provenance when applicable, an installed primary `mainProgram`, and maintainers for new submissions. Prefer a literal program name over `pname`. Maintainers must accept maintaining the expression. Existing upstream maintainers do not automatically own personal variants. Missing maintainer consent remains an upstream-submission prerequisite, not justification to invent identities. [Pinned contribution guide](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/README.md#meta-attributes)

`mainDarwinApp` names the actual application directory, INCLUDING its `.app` suffix. It is distinct from `mainProgram` and should describe a bundle installed under `Applications`. Data/library packages need neither. Preserve supported platforms and licenses based on actual payloads; do not confuse free licensing with source-built provenance. [Pinned metadata manual](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/doc/stdenv/meta.chapter.md)

Compatibility evidence: `mainDarwinApp` is a string in the pinned checker and absent from the 25.11 and 26.05 checkers. The existing conditional `lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"` therefore preserves older caller compatibility. This is an inference from schemas, not a claim that metadata alone changes `nix run`. [Pinned checker](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/stdenv/generic/check-meta.nix), [25.11 checker](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/pkgs/stdenv/generic/check-meta.nix), [26.05 checker](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/pkgs/stdenv/generic/check-meta.nix)

### Linux desktop integration

Reuse upstream desktop IDs, localized names, actions and MIME claims where accurate. A desktop entry needs `Type`, `Name`, and an executable `Exec` unless D-Bus activation applies. `Version` describes the specification version, not the application release. `Icon` must resolve to an installed asset; a theme name carries no filename extension. Only claim supported MIME types, URL schemes and notification behavior. StartupWMClass needs evidence of the real mapped class; D-Bus activation cannot be invented. [Desktop keys](https://specifications.freedesktop.org/desktop-entry/latest/recognized-keys.html)

`Exec` is a desktop command line, not a shell command: use desktop quoting, keep `%U`/`%F` as standalone arguments, and pick the field code matching actual argument support. At most one file/URI field code is allowed. `TryExec` should resolve to the same installed command. [Exec specification](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html)

Use `makeDesktopItem` for newly authored entries; its own check invokes `buildPackages.desktop-file-utils` validation. `copyDesktopItems` copies declared desktop items during the install hook. Validate vendor entries after substitutions too. Syntax validation does not prove executable/icon/MIME behavior, so add package-local installed-artifact checks. [Desktop helper source](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/make-desktopitem/default.nix), [Copy hook](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/setup-hooks/copy-desktop-items.sh)

AppStream uses stable reverse-DNS component IDs and installed `share/metainfo/*.metainfo.xml`. `metadata_license` concerns the XML content; `project_license` concerns the software. Keep upstream licensing and identity. [Generic component specification](https://github.com/ximion/appstream/blob/main/docs/xml/metainfo-component.xml)

Desktop-application metadata needs name, summary, description and a `launchable` desktop ID alongside its identity/license fields. That launchable must match the installed desktop file. Preserve upstream metadata and validate it with `appstreamcli validate --no-net`; avoid inventing authors, screenshots or release dates. [Desktop application specification](https://github.com/ximion/appstream/blob/main/docs/xml/metainfo-desktopapp.xml)

### Darwin bundles

Use a structured plist writer for locally authored bundles. Validate a reverse-DNS `CFBundleIdentifier`, actual `Contents/MacOS/CFBundleExecutable`, display/name values, `CFBundlePackageType=APPL`, and the installed icon named by the plist. Plist structure version is `6.0`. Release versions are numeric major.minor.patch values; keep source revisions in a separate custom key. [Apple Core Foundation keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)

Build versions contain numeric components. The deployment minimum must match the actual toolchain/dependencies. App Store category is separate from Nix metadata and should be factual when supplied, but is not a universal requirement for non-store apps. [Apple build version](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleVersion), [Bundle configuration](https://developer.apple.com/documentation/bundleresources/bundle-configuration)

Preserve signed vendor bundles and their plist bytes. Changing their metadata invalidates sealed resources. Modified/source-built bundles must finish mutations before signing, with nested code signed first. Recursive verification is appropriate; generic `--deep` signing is discouraged. Nix wrappers with external store symlinks cannot promise Developer ID/Gatekeeper conformity merely from a plist test. [Apple signing tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)

### Implementation

The review covers every package directory, including inherited metadata on
variants. Existing license and non-source policy checks remain independent of
the metadata declarations. Text and source-built outputs without an explicit
provenance declaration now record `fromSource`.
Descriptions use factual language, and primary command names use literal strings.

All application bundles have a Darwin selector on compatible Nixpkgs versions.
Package-local checks validate plist identities, executable references and declared
icon files without changing vendor signatures. Local Darktable metadata uses the
platform deployment minimum; locally authored plist writers declare structure
version `6.0`. Linux install checks validate patched vendor entries and verify
that launcher command and icon references resolve within the installed output.
Existing desktop IDs, MIME associations, translations and AppStream assets remain
authoritative. Existing AppStream passthru checks continue to validate offline.

Personal variants must not assign their modified expression to an upstream
maintainer without consent. Unassigned expressions retain empty or omitted
maintainer lists until a maintainer accepts responsibility. The Nixpkgs reference
already contains the public `IanHollow` identity, so an accepted assignment can
use `lib.maintainers.IanHollow` without a repository-specific maintainer registry.
[Pinned maintainer list](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/maintainers/maintainer-list.nix)

The `package-app-metadata` check exercises malformed plist identities, executable
paths and missing icon references, plus valid store symlinks and vendor build
numbers. The independence report records main commands, Darwin bundle names,
maintainers and provenance for each supported recipe. Metadata evaluation and
artifact checks do not establish GUI behavior or complete redistribution rights.

Native verification also detected a stale hash for the pinned OpenAI Darwin ZIP.
Two downloads from the official pinned URL produced the same replacement hash.
The archive's application reports the expected version and passes recursive
strict signature verification with OpenAI's Developer ID. The source hash now
matches that verified archive; no vendor bundle contents were changed.

### Verification

The final package snapshot passes `just check` for all three exported systems,
with metadata type checking and import-from-derivation disabled. Native
`aarch64-darwin` passes `just test`, Python formatting, Ruff, type checking and
the application metadata fixture checks. Bitwarden, LinearMouse, ChatGPT and
OCR Capture build natively and pass their installed-bundle checks. Documentation
passes Markdown validation. Static review covers the combined metadata patch.

The review does not build every application or launch a GUI. Linux recipes have
installed-entry checks, but complete native Linux application builds remain
separate validation. Maintainer acceptance remains necessary before upstream
submission. Existing repository work stays separate from this review.

## Desktop metadata and update review, 2026-10-13

This follow-up asks how Linux `desktopItems` and Darwin application metadata
should track package updates. It uses the same Nixpkgs pin as the application
review above. The recommendations below come from source inspection and the
specifications; they do not report additional package builds.

### Desktop item installation

The pinned hook is named `copyDesktopItems`. Declare it in `nativeBuildInputs`
and pass desktop-file derivations or file paths in `desktopItems`. It registers
a post-install hook and copies files to the executable output's
`share/applications` directory. A custom install phase must call
`runHook postInstall`. The hook installs read-only files, so modifications after
copying need deliberate writable handling.
[Pinned copy hook](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/setup-hooks/copy-desktop-items.sh)

Use `makeDesktopItem` for a launcher authored by the package. It produces
`share/applications/<name>.desktop` and validates the result with a build-platform
`desktop-file-validate`. Its `name` is the filename stem; `desktopName` is the
displayed application name. Its `Version=1.5` is the desktop specification
version and must not track the application version. The helper leaves optional
values unset when they are `null` and supports actions and vendor extensions.
[Pinned desktop item builder](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/make-desktopitem/default.nix)

Keep accurate upstream desktop entries when they already exist. Recreating them
with a writer can discard translations, actions and protocol associations.
Patch the executable references needed for the Nix output, then validate the
installed result. An inherited package's desktop entry can remain inherited
when the wrapper still implements its contract. A server, plugin, font or
command-line utility does not need a menu launcher merely because it is a
package. This recommendation follows the desktop specification's application
entry semantics.
[Desktop entry keys](https://specifications.freedesktop.org/desktop-entry/latest/recognized-keys.html)

Keep the filename identity stable across releases. For new entries, use the
upstream application ID where available. `Exec` uses desktop quoting rather than
shell syntax, and its file or URI field code must match the application's actual
argument handling. Verify every action's executable too. Theme icons must resolve
to installed artwork. Use registered categories and supported MIME associations;
leave D-Bus and startup claims unset unless the application implements them.
[Desktop filenames](https://specifications.freedesktop.org/desktop-entry/latest/file-naming.html),
[Exec syntax](https://specifications.freedesktop.org/desktop-entry/latest/exec-variables.html),
[Category registry](https://specifications.freedesktop.org/menu/latest/category-registry.html)

### Release metadata without build-time discovery

Use source-owned versions and dates when rendering AppStream templates. Its
release date should describe the upstream release or source snapshot. A build
clock, checkout modification time or a copied date from another release cannot
provide that information. The release specification recommends dates for release
entries; the validator reports a missing-time issue for an undated stable entry.
The complete release list is optional. If the date cannot be established, omit
that list rather than inventing a date or silencing validation.
[Release specification](https://github.com/ximion/appstream/blob/main/docs/xml/releases-data.xml),
[Validator implementation](https://github.com/ximion/appstream/blob/main/src/as-validator.c)

The creative application source pins already carry an
`<version>-unstable-YYYY-MM-DD` snapshot version. A package can validate and derive
the date from that pin and classify the corresponding AppStream entry as a
snapshot. This removes the repeated date literal from the shell template without
network access, import-from-derivation or a new clock dependency. A future stable
release should instead obtain its reviewed release date through the updater.
This is a packaging recommendation based on the current pin format, not evidence
that every version suffix is an upstream publication date.
[Example source pin](../pkgs/by-name/ve/vectorcraft/source.nix),
[Current desktop asset installation](../pkgs/by-name/ve/vectorcraft/scripts/linux-install-desktop-assets.sh)

### Darwin identity and version sources

For an unchanged vendor bundle, preserve its plist and read its metadata during
update inspection and installation checks. Bundle directory, display name and
`CFBundleExecutable` are separate values. The executable must resolve within
`Contents/MacOS`; renaming a directory does not imply renaming the executable.
Keep established identifiers and document associations unless the upstream
contract changes. Locally authored plists should derive release values from the
same pin as the application. The structure version `6.0` and package type `APPL`
are format constants and should remain constants.
[Apple bundle keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html)

`CFBundleShortVersionString` describes the released version and uses three
numeric components. `CFBundleVersion` identifies a build and can use one to
three numeric components. Use a source-provided build number when it exists;
for a locally built release, a validated numeric release version is a suitable
deterministic default. Store a Git revision separately rather than appending it
to these fields. Preserve valid vendor values instead of imposing a local
version rewrite on a signed bundle.
[Apple release version](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring),
[Apple build version](https://developer.apple.com/documentation/BundleResources/Information-Property-List/CFBundleVersion)

An updater can inspect the hash-verified release ZIP with a structured archive
and plist parser, without extracting executable files. Require one outer
application bundle, then record its directory and display names separately.
Read the declared executable during installation rather than storing a second
pin for it. Ignore nested helper bundles when selecting the outer application.
Reject unsafe or ambiguous values before writing the source manifest. Cross-check
release versions and source-side application naming where available. A fixed
expected display name can prevent automatic updates after an upstream rename;
stable identifiers and protocol names can remain explicit invariants. This
approach records the verified bundle directory and display names, and reads
`CFBundleExecutable` from the copied plist without changing signed bundle bytes.

Finish local branding and plist changes before signing. Sign nested code before
its enclosing bundle and validate signatures after installation where supported.
Preserving or generating metadata alone does not establish Gatekeeper acceptance
or GUI behavior. Update tests should exercise renamed display names, distinct
executables, version changes and ambiguous bundles without contacting a live
release service.
[Apple signing procedure](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)

### Metadata implementation

Locally generated Linux entries use `makeDesktopItem` and the native
`copyDesktopItems` hook. Moonfin and T3 declare the installed `TryExec` command.
Craft Launcher uses the registered Settings/PackageManager categories. The other
Craft applications retain upstream entries, MIME associations and translations.
Their AppStream snapshot dates now derive from the date in each immutable source
version, and their release entries declare `type="snapshot"`. These dates describe
the pinned snapshots, not an asserted publication date.

Vendor bundle checks compare their release metadata against recipe values while
preserving distinct vendor build numbers and signed contents. Steam explicitly
uses its bootstrap build field; LibreOffice permits its documented extra numeric
release-build component. Strict authored version formatting applies to OCR Capture
and Darktable. OCR Capture derives both version fields from its release value.
Darktable unpacks its dependency's actual source archive and preserves the upstream
plist template, icon and supported document associations. Vorssaint compilation
reads the deployment minimum from the same upstream plist installed in its bundle.
The declaration checker validates optional property-list settings without adding
unrelated capabilities or privacy permissions.
