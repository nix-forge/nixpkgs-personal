# Source-build review

Reviewed 2026-09-24 against the 48 public package directories in `pkgs/by-name`.
This records what each recipe installs, including packages added in the current
working tree. A source checkout is not by itself proof of a source build: the
installed executable, assembly, font, or WebAssembly module must be compiled
or generated in the derivation.

| Current treatment | Packages | Reason |
| --- | --- | --- |
| Built from source, sometimes with binary dependencies | `audiomuse-ai`, `aurral`, `codex-latest`, `bibata-cursors-hyprcursor`, `finder-favorites`, `grimblast-region`, `hyprlock-personal`, `jellyfin-plugin-intro-skipper`, `jellyfin-plugin-moonbase`, `jellyfin-plugin-subtitle-extract`, `maintainerr`, `moonfin` (Linux), `msdl-cli`, `mutant-standard-emoji`, `navidrome-plugin-audiomuseai-personal`, `nd-lyrics`, `noctalia-greeter-personal`, `noctalia-personal`, `ocr-capture`, `psscriptanalyzer`, `steam-cef-scale-override`, `vorssaint`, `wardrowbe-backend`, `wardrowbe-frontend` | The recipe compiles or transforms the package's own code from pinned source. See the retained inputs below; the classification does not imply that every dependency is compiled locally. |
| Source text or vector assets | `anthropic-skills`, `mattpocock-skills`, `noctalia-dark-app-icons`, `openai-skills`, `pstack-skills` | The deliverable is source text or SVG data; compilation would add no value. |
| Font binaries or distribution assets | `apple-color-emoji`, `apple-fonts`, `emojione-legacy`, `firefox-emoji`, `google-fonts-design`, `mplus-outline-fonts-compatible`, `ttf-ms-win11-auto`, `twemoji-color-font-optional` | These recipes select, repair, or install particular distributed fonts. Rebuilding historical or vendor fonts could change glyphs and family metadata; Apple and Microsoft inputs also have source and licensing limits. [Nixpkgs uses the prebuilt Twemoji font](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/by-name/tw/twemoji-color-font/package.nix) because its source build takes about 1.5 hours on Hydra. |
| Vendor application or patched vendor runtime | `bitwarden-desktop`, `chatgpt-latest`, `claude-desktop`, `libreoffice`, `linearmouse`, `microsoft-teams`, `moonfin` (macOS), `remindctl`, `spotify-spotx`, `steam`, `wootility` | Several are closed-source. `bitwarden-desktop`, `libreoffice`, `linearmouse`, `moonfin`, and `remindctl` publish source, but the macOS variants preserve signed vendor bundles. `spotify-spotx` patches a vendor Spotify installation. |

The `nd-lyrics` release archive was replaced by a Rust/WASI source build. The
`jellyfin-plugin-subtitle-extract` release assembly was replaced by a .NET 10
source build with pinned NuGet dependencies. Intro Skipper now builds its
dashboard with pinned pnpm dependencies and embeds it in a source-built .NET 10
assembly. All three retain their existing plugin paths and versions. The
source-built lyrics archive passed Navidrome 0.64.0's `plugin validate` command
on x86-64 Linux.

The deeper review found four concrete source-build candidates: the .NET 8
PSScriptAnalyzer module, Moonbase's .NET 8 server plugin, Moonbase's separately
released Flutter web client, and Moonfin's Linux Flutter application. The
PSScriptAnalyzer source build passed its PowerShell import and rule detection
check; its Gallery archive supplies only generated help XML. Moonbase's .NET
server and Flutter web components built with pinned dependency graphs, and
their combined package passed its install check. Moonfin's Linux Flutter build
passed its install check with explicit native plugin libraries. Moonbase's
[two-source build review](moonbase-source-build-research.md) records the exact
tags, build commands, payload inventory and checks needed for a complete
conversion. A partial Moonbase server rebuild would still retain the prebuilt
web client and must keep `binaryBytecode` in provenance metadata. The Moonbase
release license metadata now includes both its GPL-3.0 plugin and
GPL-2.0-or-later web client.

## WebAssembly targets

Reviewed 2026-09-25 across the 48 package recipes. The relevant application
targets are:

| Package | Runtime | Treatment |
| --- | --- | --- |
| `jellyfin-plugin-moonbase` | Browser | The Flutter web client compiles Dart to WebAssembly and also ships Flutter's JavaScript fallback, matching [upstream's web release build](https://github.com/Moonfin-Client/Moonfin-Core/blob/2.6.0/.github/workflows/release-web-bundle.yml). Two serial Flutter passes avoid overlapping large compilers. The package's separate SQLite WebAssembly asset remains. |
| `nd-lyrics` | Navidrome WASI plugin host | The Rust plugin already compiles from source for `wasm32-wasip1`; its archive install check verifies the WebAssembly magic bytes. |
| `navidrome-plugin-audiomuseai-personal` | Navidrome WASI plugin host | The pinned [Nixpkgs plugin builder](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/by-name/na/navidrome/plugins/build-plugin.nix) compiles Go with `GOOS=wasip1` and `GOARCH=wasm`. |

The other web-facing package recipes use JavaScript, server-side Node, CSS, or
native desktop runtimes. A WebAssembly target is only useful when a specific
component has a compatible compiler and a measured benefit; moving an entire
Next.js server or Electron app to WebAssembly would change its runtime APIs.

The Crafting Apps source recipes added after the September review compile all
fourteen GUI applications, including Launcher and FigCraft, from pinned Rust
source. The apps and `craft-fonts` also install distributed font binaries, and
some apps embed model data. Their mixed `fromSource` and `binaryBytecode`
metadata preserves that distinction. FigCraft embeds all 57 faces from its
release-specific craft-fonts revision, with verified hashes and license notices;
its GUI, CLI and collaboration server compile from source. See the
[Crafting Apps review](research/artcraft-upstream-review-research.md) for the
selected revisions and platform validation limits.

Other prebuilt inputs found inside nominally source-built packages:

| Package | Retained input | Current reason and next validation |
| --- | --- | --- |
| `psscriptanalyzer` | Pluralize.NET NuGet assembly and Gallery help XML | The analyzer and built-in rules compile from tagged source. Pluralize.NET remains a pinned third-party .NET dependency; the Gallery contributes only generated help text. |
| `jellyfin-plugin-moonbase` | SharpCompress NuGet assembly, Flutter engine WebAssembly, fonts, and other web assets | The server and Dart app compile from source. The pinned NuGet and Flutter dependency graphs retain these upstream assets; the package declares mixed provenance and preserves Flutter's notices. |
| `moonfin` (Linux) | Flutter native engine, fonts, and WebAssembly assets | The app and native plugins compile from source; the Flutter SDK supplies its engine. Nixpkgs builds the linked PDFium library from source. |
| `aurral` | Honker Rust/N-API binaries from npm | The [Honker source](https://github.com/russellromney/honker) is public and has a `node-v0.5.1` source tag matching Aurral's Node binding. The installed extension is 0.4.6, while upstream's published extension tags jump from 0.4.0 to 0.5.0. Its matching source revision and N-API/SQLite compatibility need to be established before replacing either binary. The recipe already compiles other native addons such as `sharp`, `bcrypt`, and `better-sqlite3` locally. |
| `wardrowbe-backend` | ONNX Runtime Python dependency | The current pinned Nixpkgs `onnxruntime` recipe builds a wheel from a GitHub source checkout. The earlier manylinux-wheel classification no longer applies. Wardrowbe's install check imports ONNX Runtime and verifies its CPU provider on x86-64 Linux. |
| `audiomuse-ai` | Downloaded model weights | The weights are trained data, not a reproducible output of compiling the application source. The package records their hashes and `binaryBytecode` provenance separately. |
| `anthropic-skills`, `openai-skills` | Bundled font files | Source-text catalogs also contain font binaries; their package metadata already declares both provenance kinds. |

Source availability alone is insufficient to replace a signed macOS bundle.
[LinearMouse's build guide](https://github.com/linearmouse/linearmouse/blob/main/CONTRIBUTING.md)
requires Xcode and signing, and its maintainer [describes repeated Accessibility
permission prompts with ad-hoc signatures](https://github.com/linearmouse/linearmouse/discussions/325).
[remindctl reports a similar signing-identity problem for Reminders access](https://github.com/openclaw/remindctl/issues/57).
These packages require native build and permission testing before conversion.
The remaining open-source vendor bundles likewise need pinned build graphs and
platform validation. This review does not establish GUI behavior or bit-for-bit
equivalence with upstream releases.

The vendor application decisions are package-specific:

| Package | Source-build decision |
| --- | --- |
| `bitwarden-desktop` | [The clients monorepo](https://github.com/bitwarden/clients) is public, but the distributed macOS app includes a signed Electron runtime and native integrations. A replacement needs a pinned monorepo build, signing, and Keychain/biometric runtime checks. |
| `claude-desktop` | The application source is not published as a buildable release; keep the verified vendor bundle. |
| `libreoffice` | [Nixpkgs builds LibreOffice from source on Linux](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/applications/office/libreoffice/default.nix), but that recipe declares Linux platforms. This package serves the signed macOS bundle, which needs a separate Darwin build and signing workflow. |
| `linearmouse` | Source is public, but its macOS Accessibility identity must remain stable; retain the vendor-signed app until a native signing and permission test is available. |
| `microsoft-teams` | The installed desktop application is a proprietary vendor release. |
| `moonfin` | Linux builds the tagged source using Flutter 3.47 and the exact 2.6.0 dependency lock; the Flutter engine and bundled assets remain binary inputs. The macOS app retains its signed vendor bundle. |
| `remindctl` | Swift source is public, but Reminders authorization is tied to the executable's signing identity; keep the signed release until native permission checks pass. |
| `spotify-spotx` | SpotX modifies the proprietary Spotify app; building the patcher does not supply the Spotify client source. |
| `steam` | The client is a proprietary vendor release. |
| `wootility` | [Wooting publishes its issue tracker and SDKs](https://github.com/wootingkb), but no matching buildable Wootility desktop source for this package. |

Upstream build references: [Intro Skipper](https://github.com/intro-skipper/intro-skipper/tree/12.0/v12.0.4.0),
[Moonbase](https://github.com/Moonfin-Client/Plugin/tree/2.3.0),
[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer),
[Moonfin Core](https://github.com/Moonfin-Client/Moonfin-Core), and
[remindctl](https://github.com/openclaw/remindctl/tree/v0.3.5).

## Reconciliation of the current package set

Reviewed 2026-09-30 against all 59 public package directories. The public
flake exposes 48 on x86-64 Linux and 31 on Apple Silicon Darwin, with platform
overlap. Evaluation confirmed that each supported derivation has `strictDeps`,
a description, and a license. The previous 48-package table remains the record
of its 2026-09-24 review; these are the source-build findings for packages added
or changed since then.

| Packages | Installed output and source decision |
| --- | --- |
| `actual-cli`, `homebridge-blueair-purifier`, `homebridge-lg-thinq-mp`, `homebridge-samsung-tizen`, `homebridge-tsvesync`, `reactflux`, `wardrowbe-backend`, `wardrowbe-frontend` | Build application code from tagged or pinned upstream source with the matching language toolchain. Wardrowbe's ONNX Runtime dependency is source-built by the current Nixpkgs pin. The frontend still records prebuilt dependency assets separately. |
| `scrypted-server` | Compiles the matching `v0.147.0` TypeScript source tag and builds node-pty, sharp, and classic-level locally. It links sharp against Nixpkgs libvips and removes the npm native prebuilds from the installed output. Its package provenance is `fromSource`; the wider build toolchain has its own provenance. |
| `scrypted-plugin-arlo` | Builds the public Git commit recorded by release 0.11.54, using its upstream lockfile and `scrypted-webpack`. All 28 files in the locally built zip have the same names and SHA-256 content hashes as the previous npm release zip. The zip contains Python source text; runtime Python requirements remain a deployment concern. |
| `scrypted-plugin-homekit` | The public [Scrypted repository](https://github.com/koush/scrypted/tree/main/plugins/homekit) contains the plugin source and build instructions, but its HomeKit package remains at 1.2.65. [Release 1.2.69 metadata](https://registry.npmjs.org/@scrypted/homekit/1.2.69) names a Git commit absent from that repository and a local `homekit-scratchpad/HAP-NodeJS` dependency. The release source map includes HomeKit files missing from or different from the public tree. A public-tree build cannot honestly stand in for 1.2.69. The [release-source investigation](homekit-source-research.md) records the branch, history, and source-map evidence. Retain the release zip with `obfuscatedCode` provenance until matching source is published or a separately versioned source build passes deployment and pairing checks. |
| `stirling-pdf-v3` | The login-enabled release JAR contains proprietary authentication and UI components. The available repository source does not supply a complete build of that variant, so the recipe retains the pinned vendor release and non-source provenance. |

The package-policy evaluation now denies the Scrypted HomeKit artifact when
`allowNonSource = false`. Arlo's own output has source provenance, although
its build toolchain includes Nixpkgs' binary Cargo bootstrap. This review
covers package definitions and pinned inputs; it does not assert that
every transitive Nixpkgs dependency, browser engine, font, or trained model is
rebuilt by this repository.

## REA review, 2026-10-13

`rea` compiles its TypeScript application, matching native PTY addon, and Darwin
Swift helpers from pinned public source. Its unchanged locked EVMole dependency
includes precompiled WASM, so the recipe declares `fromSource` and
`binaryBytecode` and preserves the engine's MIT notice. The package-policy check
independently verifies this classification and rejects the package when a
consumer disables non-source inputs. The generated `skills` output contains
instructions and references with no runtime closure; its build and metadata
remain part of the same release derivation. See the
[REA packaging research](rea-packaging-research.md) for the input identities,
skill output decision, licenses, and Darwin helper requirements.

## Crafting Apps source inputs

The thirteen Crafting Apps compile their desktop and CLI executables from pinned
Rust source with locked offline Cargo dependencies: `cadcraft`, `deckcraft`,
`designcraft`, `effectcraft`, `figcraft`, `filmcraft`, `gridcraft`, `lightcraft`,
`pdfcraft`, `photocraft`, `soundcraft`, `vectorcraft`, and `wordcraft`. Their
installed outputs retain reviewed binary font inputs from upstream sources or
the pinned Craft font manifest. Curated variants replace selected bundled fonts
with redistributable alternatives and preserve their notices. `craft-fonts`
installs the validated distributed font binaries directly. PdfCraft additionally
bundles two pinned redistributable RTen OCR models. These fourteen outputs
therefore declare non-source provenance independently of their free licenses;
the application recipes also declare `fromSource` for their compiled code.

`craft-launcher` also compiles its Rust executable from source and retains
distributed font binaries. Its recipe pins Noto Sans CJK SC from the Craft font
input and preserves the bundled font notices. Its independent inventory entry
therefore includes non-source provenance alongside the compiled executable.

[The packaging research](artcraft-packaging-research.md) records the immutable
source pins, font notices, model attribution and per-application build plans.
Optional user-downloaded models are not part of the installed output.

The `chatgpt-latest` variant reuses the upstream recipe with pinned vendor binaries.
The `codex-latest` variant reuses the upstream source build and pins the matching
prebuilt V8 static archive and generated binding. Both have package-local release
updaters; these variants do not copy the upstream application recipes.
