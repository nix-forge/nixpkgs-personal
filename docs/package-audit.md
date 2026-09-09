# Package audit

Reviewed 2026-09-07. The [research](package-design-research.md) explains the
layout and language choices; the [standard](package-standard.md) defines the
contract checked by CI.

## Findings addressed

- Apple Color Emoji depended on the Apple font builder. It now fetches,
  verifies, installs and repairs its own pinned source.
- Windows font tooling and the emoji updater imported Apple package helpers.
  Their inspectors and Fontconfig configuration now live inside each package.
- Nineteen updaters imported repository-root helpers or delegated to a root
  script. Each now carries its own required helpers and runs outside the checkout.
- Eight public Apple developer font outputs were aliases. They now have separate
  package directories and manifests, with explicit manual update policies.
- An inherited overlay `callPackage` could resolve through the final package
  scope. Direct and nested calls now use the supplied upstream scope.
- The registry duplicated platform metadata in manual package groups.
  Directory discovery is now automatic. Flake outputs and overlay names use
  one metadata filter, and unsupported overrides leave upstream packages intact.
  Spotify's adapter selection now permits reading metadata on unsupported hosts.
- Firefox Emoji used the nonexistent `apache-20` license attribute. It now uses
  Nixpkgs' `asl20` identifier. The Twemoji wrapper now declares platforms and a
  description of its changed behavior.
- Prebuilt macOS bundle handling was inconsistent. Claude, LibreOffice and
  Teams now preserve vendor signatures by disabling generic fixup. Bundle and
  entrypoint checks cover the prebuilt packages that lacked them.
- Noctalia imported its build expression from a fetched source during evaluation.
  A package-local upstream expression now accepts the pinned source and version.
- Noctalia classified its linked `jemalloc` library as a native build tool.
  Strict dependency checking exposed this; it now belongs in `buildInputs`.
- Several wrappers and font builds lacked strict dependency separation. They
  now set `strictDeps`; the CEF helper uses an explicit local source set.
- Bibata's final unqualified `wait` could hide worker failures. Every worker PID
  is now checked, including the final partial batch.
- Package independence checks use the package Nixpkgs pin explicitly, even
  when the development partition selects a different pin for its tools.
- CI did not enforce package independence, omitted some package Python tests,
  and ran its dedicated Swift quality/sanitizer jobs for only OCR Capture.
  Those checks now cover the package collection and both native Swift utilities.
- The README's platform table and WireGuard/Rust paragraph described coverage
  and a package that were absent from this repository. The documentation now
  matches its public package inventory.

## Package inventory

Every row also passes the common dependency, metadata, directory and updater
import contract. The check column describes implemented checks; it does not
claim macOS builds or GUI tests were run from the Linux review host.

| Package | Exported platforms | Update policy | Package checks |
| --- | --- | --- | --- |
| `anthropic-skills` | macOS ARM64, Linux ARM64, Linux x64 | Local Python updater | Package installation checks |
| `apple-color-emoji` | Linux ARM64, Linux x64 | Local Python updater | Source identity, repaired glyph checks and 3 updater tests |
| `apple-fonts` | macOS ARM64, Linux ARM64, Linux x64 | Local Python updater | Per-file hash and face verification during installation |
| `apple-new-york` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Per-file hash and face verification during installation |
| `apple-sf-arabic` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Per-file hash and face verification during installation |
| `apple-sf-armenian` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Per-file hash and face verification during installation |
| `apple-sf-compact` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Per-file hash and face verification during installation |
| `apple-sf-georgian` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Per-file hash and face verification during installation |
| `apple-sf-hebrew` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Per-file hash and face verification during installation |
| `apple-sf-mono` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Per-file hash and face verification during installation |
| `apple-sf-pro` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Per-file hash and face verification during installation |
| `bibata-cursors-hyprcursor` | Linux ARM64, Linux x64 | Manual review | Package installation checks |
| `bitwarden-desktop` | macOS ARM64 | Local Python updater | Package installation checks |
| `claude-desktop` | macOS ARM64 | Local Python updater | Package installation checks |
| `emojione-legacy` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Package installation checks |
| `finder-favorites` | macOS ARM64 | Manual review | Native compiler, unit, self-test and install checks |
| `firefox-emoji` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Package installation checks |
| `google-fonts-design` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Family exclusion and license retention checks during installation |
| `libreoffice` | macOS ARM64 | Local Python updater | Package installation checks |
| `linearmouse` | macOS ARM64 | Local Python updater | Package installation checks |
| `mattpocock-skills` | macOS ARM64, Linux ARM64, Linux x64 | Local Python updater | Package installation checks |
| `microsoft-teams` | macOS ARM64 | Local Python updater | Package installation checks |
| `mplus-outline-fonts-compatible` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Remaining font files and excluded-file/policy checks |
| `mutant-standard-emoji` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Complete artwork encoding and shaping checks |
| `noctalia-dark-app-icons` | Linux ARM64, Linux x64 | Manual review | Package installation checks |
| `noctalia-personal` | Linux ARM64, Linux x64 | Manual review | C++ bar-icon policy test and pinned upstream build |
| `ocr-capture` | macOS ARM64 | Manual review | Native compiler, unit, self-test and install checks |
| `openai-codex-desktop` | macOS ARM64, Linux ARM64, Linux x64 | Local Python updater | Platform-specific package contract; 8 updater tests |
| `openai-skills` | macOS ARM64, Linux ARM64, Linux x64 | Local Python updater | Package installation checks |
| `pstack-skills` | macOS ARM64, Linux ARM64, Linux x64 | Local Python updater | Package installation checks |
| `remindctl` | macOS ARM64 | Local Python updater | Package installation checks |
| `spotify-spotx` | macOS ARM64, Linux x64 | Local Python updater | Offline patch marker; macOS bundle signing checks |
| `steam` | macOS ARM64 | Local Python updater | Package installation checks |
| `steam-cef-scale-override` | Linux x64 | Manual review | C ABI integration, invalid-input and ELF checks |
| `t3-code` | macOS ARM64 | Local Python updater | Package installation checks |
| `ttf-ms-win11-auto` | macOS ARM64, Linux ARM64, Linux x64 | Local Python updater | Extracted and installed manifest validation; 5 unit tests |
| `twemoji-color-font-optional` | macOS ARM64, Linux ARM64, Linux x64 | Manual review | Remaining font files and excluded-file/policy checks |
| `vorssaint` | macOS ARM64 | Local Python updater | Package installation checks |
| `wootility` | macOS ARM64 | Local Python updater | Package installation checks |

## Validation

- All 39 package directories pass the independence contract on their supported
  flake systems: 27 x86_64 Linux, 25 ARM64 Linux and 34 ARM64 macOS evaluations.
- Platform metadata is readable for all 39 packages on all three flake systems.
  Automatic discovery preserves all 86 public and 86 supported overlay
  derivations from the manual registry. Upstream Linux Steam, LibreOffice and
  Bitwarden remain unchanged when their personal overrides are unsupported.
- Evaluation also passes with import-from-derivation disabled.
- All 19 package updaters accept `--help` from isolated temporary copies.
- Negative controls reject a personal dependency and an outside-directory import.
- All 29 Python unit tests pass across four package suites.
- Ruff, type checking, Nix static checks and the configured formatter checks pass.
- All 27 native x86_64 Linux package outputs build successfully, including
  Noctalia with its C++ policy test and Mutant Standard with its complete
  encoding and shaping checks. Native macOS and ARM64 Linux builds run in the
  repository's CI matrix; this review runs on the `desktop` x86_64 Linux host.
  No system activation is part of this change.

## Metadata and unfree review, 2026-09-08

Scope: the complete 39-package collection at base
`cf6cad184f3d4f35bfde13336609fe2a7daacf3d`, with the changes recorded below.
The requirements are accurate licenses, consumer policy, provenance, platforms,
entrypoints and build settings. The [package standard](package-standard.md)
provides repository conventions; [metadata research](package-metadata-research.md)
provides the pinned Nixpkgs and upstream evidence.

### Initial metadata corrections

- Mark the full Anthropic and OpenAI skill catalogs unfree. Anthropic includes
  restricted document skills and 54 prebuilt OFL fonts; OpenAI includes Figma
  terms and MIT Notion skills. Keep the mixed license and provenance metadata.
- Declare MPL-2.0 for the official LibreOffice distribution.
- Give the Windows ISO fetcher `pname = "ttf-ms-win11-auto"` so the documented
  name predicate permits both the package and its source. Retain its original
  filename, hash, restrictive license and local-build settings. Remove the
  redundant `meta.priority = 5`, which only repeated Nixpkgs' default.
- Install omitted upstream notices for Matt Pocock skills, pstack skills,
  Bibata, M PLUS, Twemoji, Noctalia, Vorssaint and remindctl. Fetch remindctl's
  missing MIT notice from its matching release with a reviewed hash.
- Preserve remindctl's signed executable through installation. Both architectures
  in the pinned universal binary contain code-signature load commands.
- Use `stdenvNoCC` for the prebuilt Twemoji font. Remove its inherited
  `nix-update` script, which cannot update the source defined in upstream Nixpkgs.
  Its existing manual update policy follows the Nixpkgs pin.
- Enable Nixpkgs metadata type checks and add policy regression checks. Document
  that direct flake outputs enable unfree internally, while imports and overlays
  preserve the caller's policy.

No changes were needed to the other license classifications, supported platform
sets or executable names. Data packages, the CEF library, LinearMouse and macOS
Spotify correctly omit `mainProgram` because they install no `bin` entrypoint.
Linux Spotify retains `mainProgram = "spotify"`. Existing source-built utilities
and vendor binaries retain their distinct provenance. No new redistribution,
maintainer, vulnerability or broken-platform assertions were justified.

The follow-up [licensing changes](package-licensing.md) supersede the full-catalog
default above: Anthropic now selects free examples, and Noctalia records its
bundled Apache-2.0 component. The table reflects current defaults.

### Complete classification

The table describes installed payloads. "Source" includes source text and
locally compiled code; packages may leave the default source provenance implicit.
"Font binary" follows Nixpkgs' `binaryBytecode` convention. These are package
classifications, not an audit of every dependency's copyright notices.

| Package | Declared licenses | Unfree | Payload provenance |
| --- | --- | --- | --- |
| `anthropic-skills` | Apache-2.0, OFL-1.1 by default | No | Source, Font binary |
| `apple-color-emoji` | unfree, OFL-1.1 | Yes | Font binary |
| `apple-fonts` | unfree | Yes | Font binary |
| `apple-new-york` | unfree | Yes | Font binary |
| `apple-sf-arabic` | unfree | Yes | Font binary |
| `apple-sf-armenian` | unfree | Yes | Font binary |
| `apple-sf-compact` | unfree | Yes | Font binary |
| `apple-sf-georgian` | unfree | Yes | Font binary |
| `apple-sf-hebrew` | unfree | Yes | Font binary |
| `apple-sf-mono` | unfree | Yes | Font binary |
| `apple-sf-pro` | unfree | Yes | Font binary |
| `bibata-cursors-hyprcursor` | GPL-3.0-or-later | No | Source |
| `bitwarden-desktop` | GPL-3.0-only | No | Native binary |
| `claude-desktop` | unfree | Yes | Native binary |
| `emojione-legacy` | MIT, CC-BY-4.0 | No | Font binary |
| `finder-favorites` | MIT | No | Source |
| `firefox-emoji` | Apache-2.0, CC-BY-4.0 | No | Font binary |
| `google-fonts-design` | Apache-2.0, OFL-1.1, Ubuntu-font-1.0 | No | Font binary |
| `libreoffice` | MPL-2.0 | No | Native binary |
| `linearmouse` | MIT | No | Native binary |
| `mattpocock-skills` | MIT | No | Source |
| `microsoft-teams` | unfree | Yes | Native binary |
| `mplus-outline-fonts-compatible` | OFL-1.1 | No | Font binary |
| `mutant-standard-emoji` | CC-BY-NC-SA-4.0 | Yes | Source |
| `noctalia-dark-app-icons` | CC-BY-SA-4.0, GPL-3.0-only | No | Source |
| `noctalia-personal` | MIT, Apache-2.0 | No | Source |
| `ocr-capture` | MIT | No | Source |
| `openai-codex-desktop` | unfree | Yes | Native binary |
| `openai-skills` | Apache-2.0, MIT, unfree | Yes | Source |
| `pstack-skills` | MIT | No | Source |
| `remindctl` | MIT | No | Native binary |
| `spotify-spotx` | unfree | Yes | Native binary |
| `steam` | unfree | Yes | Native binary |
| `steam-cef-scale-override` | MIT | No | Source |
| `t3-code` | MIT | No | Native binary |
| `ttf-ms-win11-auto` | unfree | Yes | Font binary |
| `twemoji-color-font-optional` | CC-BY-4.0, MIT | No | Font binary |
| `vorssaint` | GPL-3.0-or-later | No | Source |
| `wootility` | unfree | Yes | Native binary |

### Validation and limits

- The regression check failed on the original Anthropic classification.
  The original Windows font allowlist also failed on its restricted ISO.
  Both now pass, while unrelated unfree packages remain rejected.
- `just check` evaluates all 39 package recipes on all three supported systems
  with metadata type checks and import-from-derivation disabled. It forces 86
  supported derivations, 27 Linux x64, 25 Linux ARM64 and 34 macOS ARM64, and
  their overlay counterparts. The policy check covers default rejection,
  selected unfree consent and independent source-provenance restrictions.
- `just test` passes the independence, package policy and Python suites.
  `just lint`, formatting and configured pre-commit checks pass.
- All 27 x86_64 Linux outputs build or reuse successfully, including Noctalia's
  C++ check, Bibata's installation checks, and the complete Font8 collection
  with source-specific evidence records.
- Additional builds verify the full Anthropic catalog, OpenAI's free selection,
  and the unchanged Apple emoji variant. The catalog installation checks compare
  restricted contents byte for byte; the unchanged emoji check compares the font
  with the downloaded source. The desktop package's updater and package-contract
  checks pass. CI selection tests cover the hosted-build exclusions.
- A Linux-only packaging check for remindctl verifies the pinned license,
  installed skill and byte-identical Mach-O executable. It deliberately does
  not execute that binary. An initial attempt to fetch through the Darwin
  derivation failed on platform mismatch; fetching through a Linux builder
  succeeded. The normal Darwin package evaluates with its native checks intact.
- PersonalMonitor's native build, bundle checks, helper self-test and strict macOS
  signature verification pass. The consuming Home Manager module evaluates to
  the renamed application path. Its privileged fan-control feature remains
  unavailable in the ad-hoc signed package.
- [NUR preparation](nur-submission.md#verified-checkout) verified all 34 native
  macOS outputs against the current checkout's derivation paths.
- No ARM64 Linux build, GUI launch, Reminders permission test,
  system activation or complete transitive license audit ran in this review.
  The package metadata review does not establish every upstream component's
  copyright ownership or grant redistribution rights.
