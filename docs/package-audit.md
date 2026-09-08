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
