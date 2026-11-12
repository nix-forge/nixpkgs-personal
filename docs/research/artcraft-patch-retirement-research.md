# ArtCraft patch retirement

Latest release audit: 2026-10-16. VectorCraft is updated to 0.12.0 and its
superseded font-registration patch is retired; 47 patches remain. The other
13 applications and shared font package already use their latest eligible
sources. See the [release and patch audit](#latest-stable-release-and-patch-audit-2026-10-16).
Earlier sections retain their dated source and test evidence.
The [current 47-patch status matrix](#remaining-47-patches-upstream-status-2026-10-16) distinguishes merged, open, local, mixed and toolchain work.

Reviewed 2026-10-14. Thirteen applications now use the new stable releases published that day. Launcher remains at stable 0.4.1 and craft-fonts retains its reviewed source snapshot. No application follows an unpinned development branch.

Eleven obsolete patch files were retired. Launcher mixed patches were split into independently tracked changes without changing any of the 37 resulting source files. PdfCraft's production clipboard backend change is separate from its package-only native regression. These splits add four files, so the inventory changes from 57 to 50 files. Fewer obsolete fixes and clear ownership matter more than reducing the file count by combining unrelated changes.

The [lifecycle registry](../artcraft-patch-lifecycle.json) records every remaining local patch artifact, its exact hash, reviewed application revision, upstream references, reason and removal condition. The source-pin check independently discovers applications from the existing app list and hashes their patch files. Missing entries, stale source revisions, changed patch bytes and orphaned records fail validation. A source update requires reviewing the decisions; simply regenerating hashes is not a review.

## Stable source updates

| Application | Version | Immutable source |
| --- | --- | --- |
| cadcraft | [0.7.0](https://github.com/storytold/cadcraft/releases/tag/v0.7.0) | [`fc4e98315a8d`](https://github.com/storytold/cadcraft/tree/fc4e98315a8d771b5ab832f0ade0b5e7b106df7f) |
| deckcraft | [0.7.0](https://github.com/storytold/deckcraft/releases/tag/v0.7.0) | [`d78e657e4cb1`](https://github.com/storytold/deckcraft/tree/d78e657e4cb1e490ceb5445785c052d9cf5ad963) |
| designcraft | [0.8.0](https://github.com/storytold/designcraft/releases/tag/v0.8.0) | [`11a51d5b665a`](https://github.com/storytold/designcraft/tree/11a51d5b665aec8d6e675bd107a8a01514f10d00) |
| effectcraft | [0.10.0](https://github.com/storytold/effectcraft/releases/tag/v0.10.0) | [`05955c08b4fd`](https://github.com/storytold/effectcraft/tree/05955c08b4fd025f1a09882df72e6dbff1a8148a) |
| figcraft | [0.6.0](https://github.com/storytold/figcraft/releases/tag/v0.6.0) | [`833f0d2c27f0`](https://github.com/storytold/figcraft/tree/833f0d2c27f0acbae5394848930ae531fc89c724) |
| filmcraft | [0.8.0](https://github.com/storytold/filmcraft/releases/tag/v0.8.0) | [`f03e21556d8e`](https://github.com/storytold/filmcraft/tree/f03e21556d8e3a7155b91892d958debd5255d7af) |
| gridcraft | [0.7.0](https://github.com/storytold/gridcraft/releases/tag/v0.7.0) | [`d9d09f0baa91`](https://github.com/storytold/gridcraft/tree/d9d09f0baa912e88c5111107903fc8c640214b57) |
| lightcraft | [0.8.0](https://github.com/storytold/lightcraft/releases/tag/v0.8.0) | [`16dbb90499d3`](https://github.com/storytold/lightcraft/tree/16dbb90499d3c63a6582fcbba1b2550a6e2da032) |
| pdfcraft | [0.8.0](https://github.com/storytold/pdfcraft/releases/tag/v0.8.0) | [`9931329b9fae`](https://github.com/storytold/pdfcraft/tree/9931329b9fae0b05373b4dc3ac7c58541f0891a4) |
| photocraft | [0.9.0](https://github.com/storytold/photocraft/releases/tag/v0.9.0) | [`c699e3cda69f`](https://github.com/storytold/photocraft/tree/c699e3cda69f4852b43c0b191ab0091aaeff9d6a) |
| soundcraft | [0.7.0](https://github.com/storytold/soundcraft/releases/tag/v0.7.0) | [`3a28a657692c`](https://github.com/storytold/soundcraft/tree/3a28a657692c1b98b28c276d8f61df9471074f0f) |
| vectorcraft | [0.11.0](https://github.com/storytold/vectorcraft/releases/tag/v0.11.0) | [`0a33cff3f6e2`](https://github.com/storytold/vectorcraft/tree/0a33cff3f6e2a1e9e672f4c3816f58cd8d3d032e) |
| wordcraft | [0.7.0](https://github.com/storytold/wordcraft/releases/tag/v0.7.0) | [`fc41918814f6`](https://github.com/storytold/wordcraft/tree/fc41918814f62645b6746ed68e71e8c2c2e85d6f) |

Source and dependency inputs use fixed hashes. New Git sources in DesignCraft, PdfCraft and PhotoCraft have explicit Cargo output hashes. The installer preserves their actual root license and notice files, including the single Apache LICENSE in winit and BSD LICENSE.md in winprint, instead of requiring every repository to use two MIT/Apache filenames. PhotoCraft metadata includes the added BSD license. DeckCraft uses the stable release's reviewed Latin font input and retains its complete notices.

## Retired patches

| Package | Removed patch | Why it can retire |
| --- | --- | --- |
| effectcraft | `system-font-search-phase-fixture.patch` | The stable release fixes the fallback priority contract. Keep its public-fallback regression instead of the older test-only workaround. |
| filmcraft | `frame-pool-test-isolation.patch` | Even the previous pin tests allocation identity rather than a shared global reuse counter. The extra mutexes no longer isolate an asserted invariant. |
| lightcraft | `portable-lock-spawn-fixture.patch` | Stable resolves the child executable through PATH instead of /bin/true. Its real-child and lock-reacquisition regression remains. |
| lightcraft | `lightcraft-fault-file-identity.patch` | Stable fault injection matches source paths by filesystem identity, so case aliases reach the intended failure. Partial-move, collision and metadata-repair scenarios remain. |
| lightcraft | `unicode-filesystem-invalid-name-fixture.patch` | Stable probes whether invalid-byte names are supported and runs those cases where possible. Catalog and symlink checks retain a valid-folder fallback. |
| lightcraft | `lightcraft-case-alias-expectations.patch` | Stable compares pending paths by volume-aware identity and checks actual directory-entry spelling. Collision checks remain without assuming case aliases are distinct paths. |
| lightcraft | `native-export-dialog-height-fixture.patch` | Stable expects the extra Apple Photos row on macOS: 876-point height there and 846 elsewhere. Width and fit assertions remain. |
| photocraft | `photocraft-translation-policy.patch` | The new stable source already contains the translation policy and catalog entries. |
| photocraft | `turkish-animation-preference.patch` | The new stable source already contains the translation policy and catalog entries. |
| figcraft | `ruzstd-bounded-decompression.patch` | Stable 0.6.0 already locks the bounded ruzstd 0.9.1 decoder. |
| pdfcraft | `hayro-logging-lock.patch` | Vendored Hayro now has a quiet default when logging is disabled. Retain that upstream default and remove the older logging feature and lock workaround. |
| photocraft | `zero-rss-reading.patch` | Replaced by the exact #5399 manifest feature backport after the original sampler failure reproduced on the desktop ARM builder and all four actual testkit tests passed with statm. The helper now obtains an available reading instead of suppressing zero. |

A merged fix on development main was not sufficient while a package still selected an older stable source. These removals follow exact source inspection, not merge status alone.

## Remaining ownership

| Kind | Files | Policy |
| --- | --- | --- |
| packaging-policy | 12 | Intentional distribution branding, selected fonts or immutable-path integration. Keep only while required by that policy. |
| platform-workaround | 7 | Sandbox, emulation or package-native test accommodation. Diagnose the underlying environment and preserve separate native coverage. |
| toolchain-workaround | 2 | Repair belongs to a compiler or dependency. Track that upstream and retest the original reproducer before removal. |
| upstream-backport | 7 | Accepted upstream fix not yet included in the packaged stable release. Retire after inclusion and regression validation. |
| upstream-candidate | 22 | Keep while the pinned source lacks the fix. Follow existing PRs; adapt unsent changes before upstream submission. |

Launcher backup preservation is the exact accepted commit a2e490094b705c089bd44f79f2d1a13466d97d62, directly based on the packaged stable revision. Atomic state/settings remain a separate adaptation of proposal 314; only the identical tempfile dependency move is deduplicated. Autostart quoting and Unix test helpers are separated from immutable bundle paths and discovery priority. Their old and new patched source files are byte-identical.

The registry covers `.patch` artifacts, including vendor/compiler patch files. Normal package integration is separate: release metadata substitution, macOS bundle construction/signing, immutable executable and font paths, runtime wrappers, curated font attribution and exact Cargo lock selection remain Nix responsibilities. Remove those source rewrites when upstream exposes an equivalent configurable input. Vendor repairs executed from phase hooks are included in the patch registry.

## Further upstream work

- DesignCraft and VectorCraft now have focused registration PRs ready for review with synthetic ordering regressions. Full crate tests with empty and representative explicit font input remain pending; existing script and loaded-document fallback priority must remain covered.
- FigCraft's XDG user-directory PR is separate from full Fontconfig discovery. A complete replacement still needs shared discovery across both scanners, bounded helper execution/output, opt-out handling and conventional fallback. The earlier unbounded subprocess candidate is not ready to submit.
- Launcher's narrow default-store ownership PR protects macOS bundle links and self-update while preserving discovery order. Generic Linux PATH binaries already have external-ownership protection. Custom stores, wrapper/version handling and AppImage work remain separate.
- EffectCraft temporal arithmetic still needs a compiler or emulator reproducer. The Launcher Unicode process lookup failure now reproduces locally; a portable repair remains unresolved, as detailed below. Do not describe a local workaround as a general upstream fix.
- Native-font and GPU test accommodations must retain separate host coverage. Do not upstream a patch that only removes useful tests to fit a sandbox.

The initial retirement pass opened no further upstream PRs. The follow-up below records later contributions and merged status. Existing contributions and overlapping PRs are linked per patch in the registry.

## Validation boundaries

Source and Git input hashes were calculated from immutable fetches. Retained source patches were applied to the exact new stable snapshots without fuzz; the rebased Rust files were parsed with cached rustfmt. Independent review caught and corrected a DeckCraft rebase error and stale README pins before integration.

The lifecycle validator has rejection tests for stale source pins, changed bytes, undocumented patches/apps and duplicate records. License installer tests fail with the old two-filename assumption and pass with the corrected helper; inputs with no license or an empty license still fail. These are focused source/tooling checks, not application compilation.

The required `just check` completed check-definition evaluation for x86_64-linux, aarch64-linux and aarch64-darwin with import-from-derivation disabled. All 15 outputs also evaluated for Intel Darwin using the existing nixpkgs 26.05 compatibility pin. The source-pin check ran successfully as a strict-sandbox Nix build, including the lifecycle rejection tests and all 50 records. These evaluation checks do not compile applications.

Full application compilation and the native/cross runtime matrix for these new revisions are separate validation. Earlier completed build receipts apply only to their recorded source revisions. Linux validation belongs on the Linux builder; Darwin validation needs an appropriate Darwin host. Do not infer a passing new build from metadata resolution or a passing older release.

### Strict-sandbox source preparation

| Package | Result | Scope |
| --- | --- | --- |
| cadcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| craft-launcher | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| deckcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| designcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| effectcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| figcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| filmcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| gridcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| lightcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| pdfcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| photocraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| soundcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| vectorcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |
| wordcraft | Passed | Unpack/patch and full locked offline Cargo metadata; no application compilation. |

## Upstream follow-up

Rechecked 2026-10-15. The original 15 proposals now comprise three merged PRs, ten open PRs and two closed duplicates: EffectCraft #1479 and FigCraft #348. Across all 24 contributions, nineteen are open and ready for review, three are merged and two are closed. The latest stable application sources still match the pins above, so merge status alone does not retire these patches.

The release check compares every advertised stable tag and its peeled commit with the selected source. All fourteen application releases remain unchanged, including Launcher 0.4.1. Craft-fonts still has no release or tag, and its current main remains the selected snapshot [`3d9ab3a`](https://github.com/storytold/craft-fonts/commit/3d9ab3a132ed0eff457e424226a435a901da30d3). No version bump or immediate patch deletion follows from this check.

[FigCraft #472](https://github.com/storytold/figcraft/pull/472) has merged the rename-fixture repair, and the maintainer closed [our #348](https://github.com/storytold/figcraft/pull/348#issuecomment-6190438076) as its duplicate. The accepted test retains Cmd+R everywhere and Ctrl+R off macOS. Current main contains it, but stable 0.6.0 does not. Retire the rename portion independently when a selected source includes that behavior; the separate About-window concern does not share its acceptance status.

[PdfCraft #1553](https://github.com/storytold/pdfcraft/pull/1553#issuecomment-6187421793) and [#2135](https://github.com/storytold/pdfcraft/pull/2135#issuecomment-6186230364) also merged after stable 0.8.0. The former discovers configured UI fallback-font directories through a bounded pure-Rust parser and still performs its once-only startup scan on the UI thread. It is useful design precedent, not full Fontconfig matching or a FigCraft fix. The latter repairs production OCR downsampling for image pages whose boxes are recorded in pixels; it remains separate from the physical-size fixture in #2399.

| Accepted repair | Source inclusion | Current action |
| --- | --- | --- |
| [LightCraft #1795](https://github.com/storytold/lightcraft/pull/1795), screenshot and HEIF associations | Merged after stable 0.8.0 | Retain two backports. Validate the unpatched desktop entry and AppStream image after a release update. |
| [DeckCraft #746](https://github.com/storytold/deckcraft/pull/746), screenshot | Merged after stable 0.7.0 | Retain one backport. Upstream uses a different valid image reference; judge equivalent behavior instead of requiring an identical diff. |
| [DesignCraft #957](https://github.com/storytold/designcraft/pull/957), screenshot | Merged after stable 0.8.0 | Retain one backport and review any separate immutable-image-URL preference after the source update. |
| [WordCraft #1668](https://github.com/storytold/wordcraft/pull/1668), optional document fonts | Merged after stable 0.7.0; this was an existing contributor's proposal | Retain the runtime backport. Its Chinese priority and stronger family assertion differ from upstream; validate those independently before removing the whole patch. |
| [Launcher #332](https://github.com/storytold/craft-launcher/pull/332), recovery backup preservation | Already accepted, still absent from stable 0.4.1 | Retain the exact accepted head commit backport. |

These account for six accepted-upstream backport files. Discovery precedence is now explicitly distribution policy rather than a universal ordering repair. No additional immediate deletion was established by this audit. The remaining 50 files comprise 22 upstream candidates, six accepted backports, twelve policy patches, eight platform accommodations and two toolchain workarounds. CADCraft and craft-fonts have no local patch files.

### New contribution

[WordCraft #1981](https://github.com/storytold/wordcraft/pull/1981) fixes two font-cache test fixtures and is now ready for review after contributor review. The merged font-registration repair makes Thai available even with system fallback disabled, so Thai is no longer a reliable missing-glyph fixture. The change keeps the existing cache insertion, reuse and invalidation assertions and checks Thai coverage when supplied. Only tests change. Rustfmt, independent source review and contributor review passed; Cargo tests and full CI remain pending. Run the two fixtures both with no optional input and with Thai font input before treating the repair as fully validated.

[EffectCraft #1540](https://github.com/storytold/effectcraft/pull/1540) is now ready for review after contributor review, honoring `FONTCONFIG_PATH` in the existing Unix configuration scanner. Five focused regressions fail before the repair; all nine standalone configuration tests pass afterward. Those nine comprise three existing pure configuration tests and six new tests. The existing font-face integration test remains unchanged and was not run; full Cargo CI remains pending. Independent review found and corrected an unreadable-first-configuration edge case before publication.

Twelve controlled comparisons against Fontconfig distinguish this fix from the local fallback. The repaired scanner covers the selected supported font files in eleven cases, including path order, missing/unreadable entries, relative/default names, absolute overrides, non-Unicode paths and empty path components. A separate valid font ten directories deep is still missed by the bounded walker and found by the existing `fc-list` fallback. Therefore keep that downstream patch and its executable-path hook; the new PR does not replace all its behavior. In the ordinary desktop configuration, the unmodified upstream scanner already covers every Fontconfig-listed file in the application's supported TrueType/OpenType formats. The remaining difference is demonstrated in controlled configurations, not assumed from conventional directory layout.

### Further proposals and limits

DesignCraft #987, VectorCraft #2111, FigCraft #474 and Launcher #459 are ready for review after contributor review. Their recorded Cargo and platform checks remain pending.

- [DesignCraft #987](https://github.com/storytold/designcraft/pull/987) and [VectorCraft #2111](https://github.com/storytold/vectorcraft/pull/2111) register every explicitly supplied document-font family. Both retain the exact existing script-specific prefix and explicit optional input. Their extracted ordering regressions fail before and pass after; full crate tests, real-font parsing and DesignCraft composition fixtures remain pending. Independent review corrected a Malayalam lazy-load fixture and a missing-Arabic-font assumption. No default embedding or UI-language preference is introduced, consistent with [VectorCraft #1605](https://github.com/storytold/vectorcraft/pull/1605) and [#1424](https://github.com/storytold/vectorcraft/pull/1424).
- [FigCraft #474](https://github.com/storytold/figcraft/pull/474) honors absolute `XDG_DATA_HOME` for Unix user fonts, with standard fallback and byte-path tests. Both extracted path regressions fail before and pass after. This smaller fix reaches both scan entry points but does not implement full Fontconfig discovery. The earlier subprocess candidate has unbounded output, no deadline and changes only one scan path; do not publish it or remove the downstream patch on its evidence. Full Cargo and platform checks remain pending.
- [Launcher #459](https://github.com/storytold/craft-launcher/pull/459) protects macOS bundle links into the conventional `/nix/store` and disables self-update for the Nix-owned launcher. Generic Linux PATH installations already receive the existing Binary ownership protection. The new guard preserves bundle identity, discovery order and existing messages; custom stores and complete UI ownership presentation remain outside its scope. The final extracted ownership helper passes two boundary and executable/bundle-link tests. An additional source-extracted ownership regression fails before the guard and passes afterward; ordinary application and AUR policy assertions pass in both versions. That harness uses minimal type shims and does not compile the native crate. The real native entry-point regression, Cargo CI and macOS runtime tests remain unrun. Existing [#314](https://github.com/storytold/craft-launcher/pull/314), [#335](https://github.com/storytold/craft-launcher/pull/335), [#328](https://github.com/storytold/craft-launcher/pull/328), [#420](https://github.com/storytold/craft-launcher/pull/420) and [#424](https://github.com/storytold/craft-launcher/pull/424) cover other repairs.
- The Launcher Unicode process lookup failure reproduces under the C locale and succeeds with an installed C.UTF-8 locale. An unconditional upstream locale override is not portable: the [glibc 2.35 announcement](https://sourceware.org/pipermail/libc-announce/2022/000033.html) states that C.UTF-8 must be installed. Keep the controlled Nix accommodation while investigating a portable process-discovery fix.
- SoundCraft review [141](https://github.com/storytold/soundcraft/pull/141) requests system-font discovery rather than bundled fonts. Keep this distribution's permitted symbol-font selection downstream. Branding removal and selected CJK priorities are also distribution policy.
- Candle device bounds already have relevant open proposals. PdfCraft's geometry PR follows the merged OCR fixture repair without duplicating its scope. The RTen failure now has an exact compiler-pairing reproducer and an existing Nixpkgs owner. GCC still needs the original full translation-unit failure, and temporal arithmetic still needs the original full effects-test reproduction; the reduced results are recorded below.

The [NixOS community thread](https://www.reddit.com/r/NixOS/comments/1x1haxe/artcraft_apps_for_nixos/) links alternative packaging and existing Nixpkgs proposals. [ipeglin/artcraft-nix](https://github.com/ipeglin/artcraft-nix) packages release AppImages and documents a conventional-font-directory workaround; [Hy4ri/artcraft-flake](https://github.com/Hy4ri/artcraft-flake) offers another flake. Those implementations are useful comparison points, but they do not prove source-build fixes are obsolete. Keep package discovery and font configuration independent of creating a host-wide conventional-path symlink.

### Per-patch decisions

The following covers every retained patch at the reviewed stable pins. An open proposal is not an accepted fix; a merged fix is not necessarily in the selected release. References and exact patch hashes remain in the lifecycle registry.

| Package | Patch | Decision and next action |
| --- | --- | --- |
| craft-launcher | `appimage-runtime-and-safe-refresh.patch` | Existing open PR #328 already implements AppImage runner and safe desktop-entry refresh. PR #355 protects manager/customized entries; PR #120 concerns one-time legacy repair. Keep downstream adaptation until a released pin contains equivalent code. Do not create a duplicate. |
| craft-launcher | `atomic-state-upstream-314.patch` | Open PR #314 already repairs predictable temporary files and reuses atomic settings writer. Stable and current main paths/settings writer remain unfixed. Keep the regression tests and no duplicate PR. |
| craft-launcher | `autostart-exec-quoting.patch` | Our open PR #420 is the portable fix. Main login.rs is byte-identical to stable. Keep downstream adaptation until the packaged pin includes the renderer and regressions. |
| craft-launcher | `gcc-libgomp-device-uid-buffer.patch` | Original compile command recovered; actual target.c reproduces the warning and passes with the local bound. A smaller unsigned-format candidate also passes a guarded public-entry reduction and full translation-unit compile, with no reachable runtime overflow claim. Keep the package fix pending GCC-channel review and required runtime-library tests; no GitHub mirror PR. |
| craft-launcher | `macos-quit-handshake.patch` | Open PR #335 already adds craft-quit with the exact pinned dependency. Issue333 and independent macOS comment reproduce crash and successful handshake/Cmd+Q after repair. Tray Quit still untested in that follow-up. Current main has no craft_quit callback. |
| craft-launcher | `nix-bundle-integration.patch` | Immutable bundle paths, wrapper substitution and downstream product label are package policy. Upstream requires ArtCraft Launcher identity. Do not send the patch unchanged. A future general configurable external-install adapter could reduce the path-specific part. |
| craft-launcher | `nix-cjk-fonts.patch` | Build-time permitted CJK path is intentional distribution policy. Hardcoded upstream system-font paths do not discover Nix profiles. A later Fontconfig implementation must preserve script-specific selection, TTC indices and missing-font fallback; PR #262 explicitly acknowledges guessed paths. No standalone source fix is ready from this three-line override. |
| craft-launcher | `nix-discovery-priority.patch` | The patch deliberately gives Nix ownership precedence over earlier PATH entries, existing manifest and macOS bundles. This is a distribution policy choice rather than a demonstrated universal ordering bug. Existing regression depends on the CJK font build input as a store target; a portable ownership proposal must use independent executable fixtures and define precedence explicitly. |
| craft-launcher | `nix-linux-process-locale.patch` | Retain at the selected pin. [#482](https://github.com/storytold/craft-launcher/pull/482) replaces native locale-dependent matching with raw procfs bytes and protects mutation on incomplete scans. Focused live C-locale and spacing regressions pass. Backend entry-point tests and other platforms remain unrun; preserve the existing Flatpak host path. |
| craft-launcher | `nix-managed-applications.patch` | Retain and follow [the ownership PR](https://github.com/storytold/craft-launcher/pull/459). Linux PATH Binary installs already have mutation protection; the proposal repairs default-store macOS bundle ownership and self-update. It does not replace custom-store, wrapper/version or AppImage hunks. Reduce the composite patch only after a containing source pin and native/macOS validation. |
| craft-launcher | `preserve-update-backups-upstream-a2e490.patch` | Exact accepted commit a2e490094b705c089bd44f79f2d1a13466d97d62 from merged PR #332 is in current main but absent from latest stable 0.4.1. Retain until a released pin contains it. Main install.rs includes private temporary backup directory and failed-rollback retention; stable still deletes predictable .old. |
| craft-launcher | `remove-restricted-marks.patch` | Upstream AGENTS requires original product identity; modified distributable follows separate branding obligations. Do not propose replacing upstream marks. Keep as distribution policy, with future supported branding configuration as separate design work. |
| craft-launcher | `unix-restart-test-path-helpers.patch` | Our open PR #424 changes two executed helper paths to PATH while preserving restart-order timing assertions. Main self_update.rs remains byte-identical to stable. No duplicate. |
| deckcraft | `approved-ui-fonts.patch` | Retain. PR #42 remains open and already removes default vendor emoji, so do not duplicate it. The selected Ubuntu/Hack stack and exact glyph policy are distribution choices; keep or expose configuration rather than impose that stack upstream. Split portable default-font feature selection from curated faces if42 lands. |
| deckcraft | `appstream-screenshot.patch` | Retain until a source update includes746. Then remove semantic fix and choose whether a tiny immutable-image-URL policy still belongs downstream. Do not open another PR. |
| designcraft | `appstream-screenshot.patch` | Retain until a source update includes957. Then remove semantic fix and evaluate immutable-image-URL policy separately. |
| designcraft | `register-all-craft-fonts.patch` | Retain and follow [the registration PR](https://github.com/storytold/designcraft/pull/987). Existing Japanese priority and optional-empty input remain supported. Full font/compose tests with representative explicit input remain pending; independently preserve useful fixture changes when retiring at a containing pin. |
| designcraft | `remove-restricted-marks.patch` | Retain as downstream branding policy. Do not propose removing upstream own logo. Main renderer changed its texture wrapper and needs rebase on any update. |
| effectcraft | `appstream-screenshot.patch` | Existing PR #1480 remains open. Pinned source and main still reference the missing demo JPEG. Keep until an upstream source update includes the replacement screenshot. |
| effectcraft | `fontconfig-discovery.patch` | Retain with its executable hook. [#1540](https://github.com/storytold/effectcraft/pull/1540) covers configuration search; [#1592](https://github.com/storytold/effectcraft/pull/1592) covers deep cycle-safe traversal without the rejected new entry cap. Both source inclusion and configured-file equivalence remain retirement requirements; full Fontconfig matching is not established. |
| effectcraft | `relative-footage-path-order.patch` | Existing1391 includes sorting the expected footage paths, alongside CLI changes. Both current pin and main retain the unordered expectation. Keep locally, avoid duplicate standalone PR. |
| effectcraft | `remove-restricted-marks.patch` | Upstream intentionally retains its restricted mark. Keep package rebranding; a public configurable-branding option needs maintainer agreement and independent demand, not a mark removal PR. |
| effectcraft | `system-font-fixture.patch` | Retain at the selected pin. [#1591](https://github.com/storytold/effectcraft/pull/1591) separates deterministic file-backed discovery/lazy loading from preserved native macOS and Linux assertions, with an explicit exact-test gate. It overlaps #1298 at the test, not its rescan UI. Validate portable sandbox tests before retirement. |
| effectcraft | `temporal-offsets.patch` | Actual optimized ARM effects test reproduces the false overflow; native optimized and ARM unoptimized controls pass. Same-binary translation controls and a literal-one instruction reduction match the accepted QEMU #4448 optimizer fix. Keep the existing repair on ARM Linux until the active builder uses the validated fixed interpreter and selected-source regressions pass; no EffectCraft arithmetic PR is warranted. |
| figcraft | `native-window-app-id.patch` | Retain and follow [#346](https://github.com/storytold/figcraft/pull/346). The maintainer integrated upstream work and added FreeBSD desktop-entry identity handling while preserving the reviewed Linux fix. The current maintainer head differs from the original contributor-reviewed head; no fresh FreeBSD runtime check is claimed. |
| figcraft | `nix-fontconfig-discovery.patch` | Retain at the selected pin. [#582](https://github.com/storytold/figcraft/pull/582) supplies shared optional configured-file enumeration with raw filename framing, output limits and a qualified query deadline. #474 and #568 remain complementary. Validate both entry points and fixed executable integration at a containing source; retain distribution-specific font counts independently. |
| figcraft | `portable-ui-regressions.patch` | Keep the exact accepted [#472](https://github.com/storytold/figcraft/pull/472) rename-test backport at stable 0.6.0; our #348 closed as a duplicate. Replace the production padding workaround with [#347](https://github.com/storytold/figcraft/pull/347)'s revised test-only geometry repair, ready after contributor review. Retire each hunk independently at a containing source pin after its regression passes. |
| filmcraft | `japanese-font-test-system-fallbacks.patch` | Existing1944 remains open; source still does not filter the named optional Chinese/Korean system fallback entries. Keep patch and Japanese precedence/glyph assertions; do not duplicate. |
| filmcraft | `remove-restricted-marks.patch` | Keep replacement attribution for restricted upstream wordmark; it implements distribution policy, not a product bug. |
| filmcraft | `system-font-fixture.patch` | Retain the local fixture at the stable pin and follow [#2072](https://github.com/storytold/filmcraft/pull/2072). It adds deterministic file-backed discovery/lazy loading and keeps the exact native macOS Helvetica/count/layout assertions in a mandatory macOS xtask gate. Remove only at a containing source after unpatched sandbox validation. |
| gridcraft | `appstream-screenshot.patch` | Existing1361 remains open. Pin/main have no screenshots block. Keep screenshot backport until source update includes it, no duplicate. |
| lightcraft | `appstream-screenshot.patch` | PR #1795 merged into integration1843, commit556f3d040f32c7f92dc4d71a180f69d104f718a0. Main uses attributed hero-tetons.jpg with correct caption and type=source, but source revision/dimensions differ from local patch. Pin16db still references missing demo image; keep as backport. Optional image dimensions do not justify another PR. |
| lightcraft | `candle-metal-device-bounds.patch` | Candle main still calls Device::all().swap_remove(ordinal) unchecked. Existing3413 and3645 repair this.3413 review asks simpler feature-dependent tests and questions hosted runner GPU availability. Keep vendor fix for Candle0.9.2; do not open a third duplicate or claim all hosted Macs have usable GPUs. |
| lightcraft | `heif-mime-types.patch` | PR #1795 merged. Exact reverse patch applies to main desktop entry; exact forward patch applies to pinned16db. Keep until stable source includes image/heic and image/heif. Latest stable remains v0.8.0 at16db. |
| lightcraft | `profile-hover-test-deadline.patch` | Pin/main still use normal SETTLE wait. Local600second asserted deadline is an emulated ARM allowance with unchanged hover/texture assertions. No portable race or product defect is reproduced, so do not upstream an unconditional10minute wait. Better future work isolates scheduler readiness with a small deterministic test before changing production/test policy. |
| pdfcraft | `font-input-attribution.patch` | Curated font source revision and permitted Apache/OFL faces differ from official release input. Keep matching attribution. Existing1484 already integrates broader font delivery, notices and regression coverage; do not duplicate. |
| pdfcraft | `native-script-fonts.patch` | Keep while using curated Droid Chinese preference; it intentionally changes Hant priority. Existing1484 implements bundled Chinese fallback policy and coverage;1446 adds user preferences and2064 system Hans/Hant fallback for names. These scopes overlap but are not interchangeable. Do not submit package-only font assertions requiring the curated input wholesale. |
| pdfcraft | `native-wayland-clipboard-fixture.patch` | Retain at the selected pin. [#2622](https://github.com/storytold/pdfcraft/pull/2622) adds the opt-in isolated native fixture and runner with selection, exact-test and signal cleanup guards. Production #2261 remains separate. Adapt the package runtime guard and validate the accepted fixture before dropping this source injection; keep X11 coverage independently. |
| pdfcraft | `native-wayland-clipboard.patch` | Existing2261 remains open. Pin/main lack Linux arboard wayland-data-control feature. Keep production feature/lock patch until included; no second Wayland PR. |
| pdfcraft | `ocr-fixture-resolution.patch` | Retain at the stable pin. PR #1197 is merged and supplies the 300 DPI scan plus relative placement tolerance. [#2399](https://github.com/storytold/pdfcraft/pull/2399), now ready after contributor review, addresses the remaining physical-size assumption and adds model-independent geometry coverage. Cached 0.7.1 behavior reproduces the sizing mechanism; new engine/OCR tests remain pending. Merged PR #2135 remains separate production downsampling work. Retire only after both repairs reach the selected source and their regressions pass. |
| pdfcraft | `remove-restricted-marks.patch` | Keep plain attribution replacing restricted marks. Upstream keeps its own branding by policy. |
| pdfcraft | `rten-vnni-intrinsic.patch` | Retain for the selected toolchain. The exact standard-intrinsic probe fails with source-built Rust 1.98.1/LLVM 21 and passes with matching official LLVM 22/std. Existing [Nixpkgs #524570](https://github.com/NixOS/nixpkgs/pull/524570) owns the global upgrade; maintainers closed [#544495](https://github.com/NixOS/nixpkgs/pull/544495) rather than restore a Rust-specific LLVM pin. No RTen assembly PR or duplicate toolchain PR. Removal requires the actual selected compiler and unpatched RTen/PdfCraft validation. |
| photocraft | `headless-shortcut-test.patch` | Retain at the selected pin. [#6227](https://github.com/storytold/photocraft/pull/6227) preserves GPU-independent capture assertions and adds separate checked native snapshots using the GPU lock and Nextest group. Actual UI compilation and visual review remain pending; documentation guard tests are not rendering evidence. |
| photocraft | `register-all-craft-fonts.patch` | Retain as selected-input policy.2169 already proposes portable Arabic registration with explicit size/script budget; avoid a broad competing registration PR. |
| photocraft | `statm-rss-sampling.patch` | Exact manifest backport of existing [#5399](https://github.com/storytold/photocraft/pull/5399), replacing zero suppression. Actual unchanged testkit tests reproduce the ARM failure with smaps and pass with statm. Retain until equivalent feature selection reaches the selected source and unpatched regressions pass. |
| soundcraft | `appstream-screenshot.patch` | Retain and follow583; no new PR. |
| soundcraft | `packaged-symbol-fonts.patch` | Retain packaged DejaVu input and Linux glyph test downstream. Do not propose compiled font bundle upstream;141 owner explicitly requests runtime system fallback, and31/495 already cover discovery mechanisms. |
| vectorcraft | `register-all-craft-fonts.patch` | Retain and follow [the registration PR](https://github.com/storytold/vectorcraft/pull/2111). The existing Japanese/Arabic/Thai prefix stays first and other supplied faces follow in manifest order. Full text tests with empty and representative explicit input remain pending; retire only at a containing pin. |
| wordcraft | `optional-thai-cache-miss-fixture.patch` | Retain. PR #1981 proposes this independent cache-fixture repair; merged1668 does not fix the negative-cache assumption. Cargo validation remains pending. |
| wordcraft | `register-all-craft-fonts.patch` | Retain until source includes1668 or replace runtime portion with exact1668 backport. Do not open new runtime PR. Keep or upstream separately stronger all-supplied-family assertion, which merged1668 Arabic regression does not fully cover. |

### Remaining workaround follow-up

[PdfCraft #2399](https://github.com/storytold/pdfcraft/pull/2399) is ready for review after contributor review of [`cbcbce7`](https://github.com/storytold/pdfcraft/commit/cbcbce7d37d9788cf22d01b6f9e50274b5237e86), following merged [#1197](https://github.com/storytold/pdfcraft/pull/1197). Its 300 DPI scan is imported at explicit 300 DPI rather than the metadata-free PNG default of 72 DPI. The new geometry regression needs no OCR models and retains every existing recognition, placement, undo and repeat-run assertion. A cached PdfCraft 0.7.1 CLI reproduces a 612 by 792 point page becoming 2550 by 3300 points under default import and returning to its original size with explicit DPI. Seven relevant functions are byte-identical in the refreshed source, but the new engine/OCR tests and Clippy remain unrun. No application was compiled for this contribution.

The RTen workaround now has an exact standard-intrinsic compile reproducer. Source-built Rust 1.98.1 with LLVM 21.1.8 rejects it at optimization levels 0 and 3; the same Rust release with matching official LLVM 22.1.8 and std compiles it. No AVX-512 instruction is executed. This isolates the compiler pairing from OCR and RTen. Existing global [Nixpkgs #524570](https://github.com/NixOS/nixpkgs/pull/524570) owns the LLVM upgrade. Maintainers closed the competing Rust-specific [#544495](https://github.com/NixOS/nixpkgs/pull/544495); its closure-size and default-alignment concerns argue against recreating it. [PdfCraft packaging #571437](https://github.com/NixOS/nixpkgs/pull/571437) and [sdroxide #555859](https://github.com/NixOS/nixpkgs/pull/555859) contain the matching diagnostic. Keep SIMD and the package workaround until the actual selected compiler and unpatched path validate.

Reduced GCC 16 probes reproduce the UID format warning on x86_64 and the configured aarch64 user-emulation path. The real callers exclude negative device ordinals; nonnegative values fit, and a domain-constrained reduction passes. The INT_MIN demonstration truncates safely through snprintf. This is no proof of reachable overflow. Obtain the original full command and preprocessed source before choosing a compiler or library repair, following [GCC's bug-report requirements](https://gcc.gnu.org/bugs/) and [contribution process](https://gcc.gnu.org/contribute.html). No mirror PR or mailing-list message was created.

EffectCraft's bounded temporal arithmetic also passes reduced checks on both targets: 57,840 products with overflow checks and six frame-rate comparisons. Those runs do not reproduce or disprove the original full effects-test failure. Retain the accommodation until that exact regression runs unmodified with the affected flags and builder; do not turn a mathematically safe multiplication into a claimed application defect.

The private EffectCraft traversal prototype confirms that cycle tracking can discover fonts below the current depth limit while retaining sibling aliases. Its proposed 65,536-entry shared budget would also change which large collections and later roots are scanned. That tradeoff, retained-path memory and actual caller diagnostics need a reviewed resource contract before a PR. The prototype does not replace full Fontconfig behavior. Launcher's locale workaround likewise remains downstream: direct procfs scanning would need to preserve wrapper matching and Flatpak host-namespace checks, and an unconditional C.UTF-8 override assumes that locale is installed.

PhotoCraft's RSS and shortcut accommodations, plus PdfCraft's native clipboard fixture, remain necessary at their current pins. Existing [PhotoCraft #5399](https://github.com/storytold/photocraft/pull/5399) changes the sampler, but native measurements do not establish guest correctness. Removing an unchecked GPU render alone does not supply separate rendering coverage. The Wayland fixture still needs its opt-in compositor, ownership handshake and cleanup runner before it is useful as a portable upstream test.

### Review follow-up on 2026-10-15

[FigCraft #347](https://github.com/storytold/figcraft/pull/347) now follows the [maintainer's requested test repair](https://github.com/storytold/figcraft/pull/347#issuecomment-6190520621). It restores the six-point production cell padding and checks actual table geometry at three body-text sizes. The viewport stays bounded, measured columns and the name minimum survive, and horizontal scrolling reaches the final column. Five extracted UI tests pass with default fonts and the pinned Inter faces using locked egui/egui_extras 0.36.2. The original fit assertion fails with Inter at 648 points; disabling horizontal scrolling makes the replacement fail. Seven transitive patch versions differ from the application lockfile. The focused program uses theme, translation and registry substitutes and excludes the unchanged whole-app About-tab test. Full application tests and Cargo CI remain pending. The contributor reviewed revision [`d0c1c129`](https://github.com/storytold/figcraft/commit/d0c1c12969e8756230b8ceb866b86d4645afc4da); it is now ready for review.

The local composite patch now contains that test-only repair and the exact merged #472 rename fixture. Both apply without fuzz to stable 0.6.0. Production credits code remains byte-identical to the selected source; the older native-only rename workaround is replaced with the accepted test that preserves broader shortcut coverage. Shared craftrules instructions referenced by upstream were unavailable through the repository API; the available FigCraft instructions were followed, with full CI deferred under the requested build limits.

The maintainer changed two FigCraft branch heads. [#474's integration commit](https://github.com/storytold/figcraft/commit/a51b8d2271f68a859d37f9c18048d1468a71dfb3) preserves the exact reviewed helper, tests and CLI documentation; its roadmap and inherited community-batch files changed. [#346's maintainer commit](https://github.com/storytold/figcraft/commit/e100c165fba1ff6955a7701b5adbef541653581b) adds FreeBSD desktop-entry handling after a similar integration. The original Linux identity fix remains. These current heads are recorded separately from the human-reviewed heads; the contributor's earlier review does not cover every inherited upstream change. Preserve the maintainer integrations rather than overwriting their branches automatically.

[Nixpkgs #574123 received a changes-requested review](https://github.com/NixOS/nixpkgs/pull/574123#pullrequestreview-5530442473) asking for a smaller, easier-to-review change. The [revised contribution](https://github.com/NixOS/nixpkgs/commit/120a024c8f8fc4b7e29f1f26ff2dd284420869d0) has eleven changed lines in one file, removes the unrelated buildPerlPackage reformat and Python test, and retains the cross-compilation interpreter fix. Focused read-only target checks pass and the native behavior is unchanged. Fresh package builds remain unrun; source checks are not build evidence.

[VectorCraft #2111's new discussion](https://github.com/storytold/vectorcraft/pull/2111#issuecomment-6192338597) confirms its registration scope complements #1424's CJK preference work. [The latter's approval](https://github.com/storytold/vectorcraft/pull/1424#pullrequestreview-5529504924) specifically preserves unspecified and loaded-face priority. Both remain open; whichever lands second needs a source rebase, not a duplicate proposal.

The captured status check covers the 22 existing contribution URLs and 65 distinct PR references from the ledger, with a separate complete follow-up of FigCraft #472. Every captured comment, review and nested review-thread connection reports no remaining page. All new relevant feedback was read. The repositories report Discussions disabled; this does not establish that every external forum was searched. This follow-up also revises the local FigCraft test patch, with no source-pin update or full application build.

### Further font-test and scanner proposals

[FilmCraft #2072](https://github.com/storytold/filmcraft/pull/2072) is ready after contributor review and separates portable font-file discovery from native host-font integration. The new test discovers the existing Inter Bold asset through `DirectorySource`, verifies file-backed metadata and lazy loading, then checks real font parsing and a glyph. The exact original macOS count, Helvetica Bold resolution and layout assertions remain in an explicit native test. `cargo xtask native-fonts` selects it and rejects zero-test discovery; macOS `cargo xtask ci` invokes that gate. No font-registration policy, asset or dependency changes.

The actual focused text test passes on Linux and native AArch64 macOS in a reduced workspace of the upstream text/color sources and manifests, with retained dependency versions/checksums and no craft-fonts input. An eager-loading mutation fails. On macOS, the native test is listed exactly once and passes; disabling actual system-font registration makes it fail at zero discovered faces, and restoring the source passes. Two extracted runner-discovery tests pass, including rejection of a successful libtest process selecting zero tests; removing the guard fails both. The macOS runs use the development profile and report installed-toolchain deployment-target warnings. Full release-mode xtask invocation, workspace CI, Clippy, wasm and tests with the optional craft-fonts input remain pending. This gives the existing sandbox fixture a concrete upstream retirement path without deleting it at the current pin. EffectCraft #1298 already edits related discovery coverage, so no competing copy of this change was proposed there.

[FigCraft #568](https://github.com/storytold/figcraft/pull/568) is ready after contributor review and fixes a general scanner stall found during the remaining-font-discovery audit. The scanner opens font-looking paths before reading the header; a FIFO can block that open. The fix skips entries whose resolved metadata is not a regular file, preserving ordinary font symlinks and existing traversal policy. A bounded child-process regression fails before the fix and passes after, kills/reaps a stalled child, and rejects a successful empty test selection through a completion marker. The Unix fixture explicitly skips if POSIX `mkfifo` is unavailable.

A private Linux probe using the actual extracted scanner and a separate Skrifa 0.47.0 lockfile confirms direct/symlinked FIFO stalls before the guard and completion after it. A real Inter font and its symlink retain their indexed face sets; broken links and sockets are skipped and depth-limited discovery sets match. Sorted output establishes those sets; unchanged source control flow supports preservation of traversal order. This metadata guard makes no filesystem-replacement race guarantee. Full crate/application tests, other native platforms, wasm and upstream CI remain pending. It neither implements full Fontconfig discovery nor retires `nix-fontconfig-discovery.patch`, and no extra downstream patch was added for it.

Both contributions passed independent source review and focused formatting/application checks. Their reviewed heads are [`ae76a26d`](https://github.com/storytold/filmcraft/commit/ae76a26d66cbd8299b80a65a026a3b47bafa4d6e) and [`5454bdc2`](https://github.com/storytold/figcraft/commit/5454bdc2449b1fc8fa9fc826ebc8a4d3f758e2f7). The existing 22 contributions and ledger references were refreshed before these drafts, with no further maintainer feedback or release/tag changes. The selected stable pins remain unchanged; all 50 retained patch hashes are checked against the registry.

### Initial remaining upstream work

Before the six-scope follow-up below, a file-by-file reconciliation of all 50 patches identified three known functional gaps that need a portable upstream solution and three optional test-infrastructure opportunities. At that point none had a new, independently validated implementation ready for submission. These are six work scopes, not a promise or requirement for six separate PRs. Existing overlapping proposals must be respected.

| Primary next action | Patch files | Interpretation |
| --- | ---: | --- |
| Existing upstream follow-up | 28 | A proposal, accepted fix or compiler owner already covers the relevant general work. Some composite files retain policy or stronger tests. |
| Intentional downstream policy | 12 | Curated fonts, attribution, branding, immutable paths or discovery precedence should remain distribution choices. |
| Known functional gap needing design | 3 | Additional general behavior is needed beyond existing proposals; a portable contract and regression evidence come first. |
| Optional portable test infrastructure | 3 | Better upstream fixtures or runners could remove accommodations; keeping package-specific validation is also legitimate. |
| Diagnosis before deciding on a proposal | 4 | Current evidence does not justify an upstream repair or safe removal. |
| Total | 50 | Each file has one primary next action; this differs from the registry's patch-kind classification. |

The three functional gaps are:

| Package and patch | Remaining upstream scope |
| --- | --- |
| Launcher `nix-linux-process-locale.patch` | Portable Unicode process matching that preserves wrapper matching and Flatpak host namespaces. The C-locale failure reproduces, but assuming C.UTF-8 is installed is not a portable repair. |
| EffectCraft `fontconfig-discovery.patch` | Deep font traversal with explicit cycle, alias, root-priority, resource-limit and partial-result behavior. [#1540](https://github.com/storytold/effectcraft/pull/1540) repairs configuration search paths; it does not remove this traversal gap. |
| FigCraft `nix-fontconfig-discovery.patch` | Bounded configured-font discovery shared by both entry points, preserving opt-out and priority. [#474](https://github.com/storytold/figcraft/pull/474) and [#568](https://github.com/storytold/figcraft/pull/568) address narrower XDG and special-file problems. |

The three test opportunities are EffectCraft `system-font-fixture.patch`, PhotoCraft `headless-shortcut-test.patch` and PdfCraft `native-wayland-clipboard-fixture.patch`. EffectCraft needs a portable/native split coordinated with [#1298](https://github.com/storytold/effectcraft/pull/1298), which edits the same test and strengthens native Linux coverage. PhotoCraft needs GPU-independent shortcut assertions plus meaningful separate rendering coverage, preserving the intent of [#323](https://github.com/storytold/photocraft/pull/323). PdfCraft needs an opt-in isolated compositor runner, ownership handshake and cleanup while retaining existing native/X11 coverage; [#2261](https://github.com/storytold/pdfcraft/pull/2261) already owns production Wayland support. None should become a PR that merely deletes coverage.

At that point the four diagnosis-first files were Launcher `gcc-libgomp-device-uid-buffer.patch`, EffectCraft `temporal-offsets.patch`, LightCraft `profile-hover-test-deadline.patch` and PhotoCraft `zero-rss-reading.patch`. Their existing reduced probes do not establish the original full failure or safe removal. [PhotoCraft #5399](https://github.com/storytold/photocraft/pull/5399) already changes RSS sampling, so a competing sampler PR would be premature. RTen remains with the existing Nixpkgs compiler owner because its selected compiler-pairing failure has been isolated.

The 28 existing-follow-up files include partial composites: Launcher runtime/refresh and ownership, DeckCraft approved fonts, and DesignCraft, VectorCraft and WordCraft registration. Existing proposals can retire their portable runtime hunks while distribution policy or stronger local tests remain. FigCraft's UI patch and PdfCraft's OCR patch also combine independently accepted and proposed repairs. These residual tests do not automatically require another upstream PR.

No patch is removed from this accounting alone. Retirement requires a selected source containing equivalent accepted behavior and the relevant unpatched regression passing in its affected environment. Merge status by itself is insufficient. The existing per-patch table and registry retain each file's evidence and removal condition.

### Local Fontconfig path correction

The remaining audit found a defect in FigCraft's existing downstream Fontconfig parser: it discarded valid Linux paths that were not UTF-8. The same font scanner accepts native byte paths. The parser now constructs `Path` values from Unix `OsStr` bytes, rejects empty, NUL-containing and relative records, and retains sorted directory deduplication. Its parser regression includes a non-UTF8 parent, and the existing package real-font fixture now constructs its path and listing without lossy text conversion.

Fontconfig 2.18.3 actually lists a real Inter font under a directory containing byte 0xff. The original helper drops that directory and finds no face; the repaired helper preserves it and the extracted actual FigCraft SFNT scanner indexes Inter Regular. The parser regression fails against the original helper and passes after the fix. This proof uses the stable candidate's helper and a previously validated main-source scanner in a separate Skrifa probe, not a full package crate build. The updated full package real-font test remains unrun. Newline-delimited filenames and subprocess resource limits remain separate limitations. This improves one existing patch without adding a patch or PR, and it does not retire the Fontconfig fallback.

### Six-scope upstream follow-up

At the conclusion of the six-scope stage, six independently reviewed proposals addressed all three identified functional gaps and all three test opportunities. All six were marked ready for upstream review on 2026-10-15 after contributor approval of their unchanged heads. No application build or source-pin update was made, and no local patch was removed.

| Scope | Proposal and evidence | Remaining validation |
| --- | --- | --- |
| Native Linux process matching | [Launcher #482](https://github.com/storytold/craft-launcher/pull/482) reads raw procfs command-line bytes, preserves literal wrapper/argument matching and stops update/removal on incomplete scans. The existing C-locale regression fails before; ten copied actual-source tests pass afterward. A real procps comparison verifies trailing empty arguments and genuine spaces. | The backend-only attempt stopped before compilation because offline dependency metadata was missing. The real mutation-entry-point test, full CI and other native platforms remain unrun. The five-second deadline is cooperative, and inaccessible processes retain existing best-effort behavior. |
| Deep font libraries | [EffectCraft #1592](https://github.com/storytold/effectcraft/pull/1592) replaces the depth cutoff with an iterative branch-ancestry walk. Two actual reduced text-crate tests fail before and pass after on Linux and native ARM macOS. A global-seen mutation fails alias preservation. | Full CI, upstream-toolchain formatting, Clippy, wasm and Windows remain unrun. Collection work remains uncapped; aliases can revisit subtrees and active-depth directory handles remain an OS resource constraint. This does not establish full Fontconfig equivalence. |
| Portable/native font tests | [EffectCraft #1591](https://github.com/storytold/effectcraft/pull/1591) checks a real permitted font through DirectorySource, lazy loading and a glyph in a private database. It preserves native macOS assertions and #1298's Linux intent in an explicit exact-test gate. Frozen-source portable/native tests pass on Linux and native ARM macOS, with explicit selected-test checks and isolated targets. Eager-load and disabled-registration mutations fail. | Full release xtask, upstream-toolchain formatting, CI, Clippy, wasm and optional font-input combinations remain unrun. Companion #1298 changes the same test and may require a rebase. |
| Shortcut capture and snapshots | [PhotoCraft #6227](https://github.com/storytold/photocraft/pull/6227) retains every capture assertion in a shared helper and adds explicit checked native snapshots at both scales. The native test uses the existing GPU lock and Nextest GPU group. Its fresh-output documentation checks reject zero selected tests and a missing image. | Actual UI compilation, rendering, visual inspection, Clippy and full CI remain unrun. The small real libtest proof produces output receipts, not rendered images; it validates only the command guard. |
| Shared configured-font discovery | [FigCraft #582](https://github.com/storytold/figcraft/pull/582) appends exact configured Linux font files through a shared collector, preserving opt-out and conventional priority. Five actual reduced-crate tests pass. Both public APIs fail before and pass after with empty embedded fonts and a real deep non-UTF8/newline/backslash path; actual Fontconfig framing also passes. | Full-workspace lock resolution stopped on unrelated uncached metadata; only the existing rustix dependency edge changed. Other-platform compilation and full CI remain unrun. The query deadline is cooperative; process creation, synchronous cleanup and font-file IO can take longer. |
| Isolated native clipboard check | [PdfCraft #2622](https://github.com/storytold/pdfcraft/pull/2622) supplies an opt-in Rust runner and native PNG/Create/export fixture. Ten runner tests, three failing guard mutations and four real compositor SIGINT/SIGTERM scenarios pass. The exact runner also passes a cached 0.7.1 native clipboard roundtrip. | Current-main UI execution, the default Cargo artifact-build path, full xtask checks and other platforms remain unrun. The cached source commit is unknown; that proof validates the runner with a prior fixture. #2261 is still the production prerequisite. Kernel I/O can exceed deadlines, and SIGKILL cannot run cleanup. |

That stage moved six files to existing upstream follow-up: 34 have a proposal, accepted fix or dependency owner, 12 remain distribution policy and four remain diagnosis-first. None of these six identified scopes still lacks a proposal. The file count stays 50. Review approval does not replace the source-equivalence and regression checks needed to remove a local patch.

The reviewed proposal heads are [Launcher `f15c9a87`](https://github.com/storytold/craft-launcher/commit/f15c9a87db24dc5e531726cacf3569df972b8e91), [EffectCraft tests `0c1f263f`](https://github.com/storytold/effectcraft/commit/0c1f263f12708256193b841b64016761dbbce079), [EffectCraft traversal `bb68c73e`](https://github.com/storytold/effectcraft/commit/bb68c73e3fc210b72064baece657b36ff84dab00), [PhotoCraft `3834845a`](https://github.com/storytold/photocraft/commit/3834845a603f5c520fe2b6c7ed566fbda391b0d2), [FigCraft `fdf8970b`](https://github.com/storytold/figcraft/commit/fdf8970b40b6512b712169a72b03184fa201c64d) and [PdfCraft `c507d023`](https://github.com/storytold/pdfcraft/commit/c507d0235c0a34e325bd9cc944d50e4b7bdeb526).

A status check of all 30 contribution URLs at 18:33 UTC on 2026-10-15 found twenty-three open and ready for review, five merged and two closed. No reviewed head changed. The six newly ready proposals have no posted checks or maintainer feedback yet; that is not a CI pass.

[FigCraft #346](https://github.com/storytold/figcraft/pull/346) and [#474](https://github.com/storytold/figcraft/pull/474) merged during this follow-up. Their complete discussion connections were read: each contains a maintainer merge confirmation with no review or inline threads. The window-identity repair is now an upstream backport; the XDG fix remains one part of the broader configured-font patch. Neither merge changes the selected stable pin or proves the full composite patch can retire.

The prior cap-based EffectCraft prototype was not submitted. The smaller traversal change preserves the existing total-library policy and makes its resource limitations explicit. Fontconfig fallback removal still requires selected-source equivalence checks; merge status alone is insufficient.

### Diagnosis follow-up

The original GCC 16.2 ARM cross-compile failure is now tied to its derivation and emitted compiler command. Fortified `snprintf` produced a truncation warning in the optimizer-generated `gomp_get_uid_for_device.part.0`, promoted to an error by `-Werror`. This establishes a build failure, not a buffer overflow: `snprintf` bounds writes, and the reviewed public callers exclude negative fallback ordinals. [Current GCC main](https://github.com/gcc-mirror/gcc/blob/f16aa1c29ef9fe49ef11f9735e8d01954dfb8b01/libgomp/target.c) and the [GCC 16 branch](https://github.com/gcc-mirror/gcc/blob/8d06be85e7b25e32eb98613f3dc52ce8cd6efd72/libgomp/target.c) retain the original allocation bound. The package fixture deliberately tests defensive full-signed-input formatting through a private helper; its wording now states that limit. It does not reproduce the complete translation-unit build.

[GCC's warning documentation](https://gcc.gnu.org/onlinedocs/gcc/Warning-Options.html#index-Wformat-truncation) allows optimization-dependent false positives. The clone name is a reason to test lost range information, not proof of that cause. A [GCC bug report](https://gcc.gnu.org/bugs/) needs the preprocessed input and exact options; the original preprocessed file was not recovered. A [runtime-library contribution](https://gcc.gnu.org/contribute.html) also needs the relevant library build and regression results. A newly reconstructed complete `target.c` translation unit reproduces the original diagnostic and compiles with the downstream bound. Controls disabling partial inlining, reducing fortification to level 2 and removing fortification still fail, so neither initial hypothesis alone explains the warning. The reconstructed preprocessed file is retained separately from the lost original; no full compiler, runtime-library or application build was run. Do not open a GitHub mirror PR or submit an arbitrary larger buffer as a demonstrated runtime repair. A smaller private candidate formats the known nonnegative ordinal as unsigned. It preserves valid UID strings and passes both the complete translation unit and a smaller reduction retaining the public guards. The unchanged reduction reproduces the warning without injecting negative private-helper calls. Independent review passed, but device, plugin, ABI and runtime-library regressions remain unrun; the candidate is not submission-ready.

The original EffectCraft failure is also recovered: `auto_levels_temporal_smoothing_reads_neighbour_frames` panicked at the checked integer multiplication in an optimized ARM test with Rust 1.98.1 and LLVM 21.1.8. The [original function](https://github.com/storytold/effectcraft/blob/d60cb71e297a4bb76851b27b48c0014b56ccab69/crates/effects/src/color2.rs), [selected source](https://github.com/storytold/effectcraft/blob/05955c08b4fd025f1a09882df72e6dbff1a8148a/crates/effects/src/color2.rs) and [retrieved main](https://github.com/storytold/effectcraft/blob/0311bdc34d0dc10c2d18ff7875b4f52d483e5e27/crates/effects/src/color2.rs) are byte-identical. The bounded product remains within [-240,240]. That arithmetic fact and earlier unoptimized probes cannot explain the actual failure; no application arithmetic rewrite is justified from them alone. The original emulator version is unknown.

The recovered original LightCraft ARM failure was a hover-state mismatch: the preview remained `render` instead of `hover` after an existing 120-second predicate wait. The 120- and 600-second values are cooperative budgets checked between synchronous UI steps, not hard wall-clock limits. The suite took 1887.57 seconds, but the log does not identify whether slow rendering, contention or a scheduling defect prevented completion. [Merged #199](https://github.com/storytold/lightcraft/pull/199) had already fixed the earlier quiet-settle race. Later [merged #445](https://github.com/storytold/lightcraft/pull/445) cached shared demo generation to address worker starvation; the [selected source includes that cache](https://github.com/storytold/lightcraft/blob/16dbb90499d3c63a6582fcbba1b2550a6e2da032/crates/engine/src/demo.rs).

Keep the ARM-only hover allowance pending an unpatched selected-source run. No available test executable had sufficient provenance for a fresh focused UI check, and no application was built for this investigation. A future run should confirm exact test selection, measure the actual hover predicate wait, and record pending renders and memory budget at its deadline. Begin with the isolated fixture, then use a bounded contention cohort. No new global-timeout or readiness PR is justified by the current evidence. [Open #1424](https://github.com/storytold/lightcraft/pull/1424) concerns a different settings test; its memory-budget concern has no demonstrated connection to this hover failure.

Focused effects-crate testing now reproduces the historical temporal failure with the actual unmodified code, original locked dependencies, optimization level 3 and debug assertions. Native x86 passes; normal ARM execution fails repeatedly; ARM optimization level 0 passes. The existing downstream patch passes both the original test and its added bounded-time test at level 3. Every run verifies exact test selection. The 87 retained package identities and checksums match the original lock, and copied sources were restored and verified. Initial offline metadata failures are excluded from test results.

The same frozen ARM test binary fails under default QEMU 11.1.1, passes with `-one-insn-per-tb`, and still fails when only direct block chaining is disabled. An independent small instruction check initially passed with dynamic operands, then reproduced a false overflow when the multiplier was literal one in the same translation block. Its stored high and low product words were correct; the overflow branch was wrong. The same small binary passes with one-instruction blocks. All six cached 11.1.1 interpreter variants reproduce it.

[Existing QEMU #4448](https://gitlab.com/qemu-project/qemu/-/issues/4448) and the accepted [fold_multiply2 fix](https://gitlab.com/qemu-project/qemu/-/commit/e2ef4fc38cebeed8e621e30aa0d3c3c6a0389ba9) identify the matching stale value-tracking problem; [11.1.2 contains the repair](https://gitlab.com/qemu-project/qemu/-/blob/v11.1.2/tcg/optimize.c). This supplies the correct upstream owner without an EffectCraft production arithmetic PR. The package now applies its unchanged workaround hunks only on ARM Linux, with the patch header corrected to describe emulation compatibility. Native ARM was not independently tested. A substitution-only realization from pinned Nixpkgs `55bfb4d7437bd4e09ab7cba58a43bd68eb310044` obtained QEMU 11.1.2 from the trusted Nix cache with local and remote builds disabled. Both unchanged frozen binaries fail under 11.1.1 and pass under 11.1.2 in normal translation mode, including exact selection of the original effects test. No emulator or application was compiled for this comparison. The active builder remains on 11.1.1; no system activation occurred. Keep the workaround until that builder is updated and the selected-source unpatched package regression passes.

[QEMU's policy](https://www.qemu.org/docs/master/devel/code-provenance.html#use-of-ai-generated-content) permits AI-assisted debugging but declines AI-generated contributions. No new QEMU patch, generated reproducer or report was submitted. Research found the existing accepted repair instead. The initial REST discussion request was restricted, but a later public GraphQL query retrieved all 30 issue notes with no remaining page. The discussion includes the same AArch64 SMULH linux-user regression and literal-one trigger. It confirms the existing owner and accepted fix; targeted searches still do not establish an exhaustive search of every external forum.

PhotoCraft now has a demonstrated retirement path for the old suppression patch. The original `sampler_reports_a_peak` failure reproduces using the unchanged selected `perf.rs`: the configured desktop ARM target reports three passes and one `unwrap(None)` failure with default smaps sampling. Enabling only the existing memory-stats feature from [PR #5399](https://github.com/storytold/photocraft/pull/5399) yields four passes. Native x86 Linux passes all four tests in both modes. Every selected test was verified; the first sysroot setup error is excluded from these results. All 23 external probe package identities and checksums match the selected source lock.

[QEMU 11.1.1](https://github.com/qemu/qemu/blob/v11.1.1/linux-user/syscall.c#L7990) synthesizes zero RSS fields in smaps. The actual ARM sampler with statm reports positive readings that increase while a faulted 32 MiB allocation is held and decrease after it is freed. These are emulator-process readings, including emulator overhead, not isolated guest-only totals or a native ARM performance baseline. Statm counters are approximate. No full application, Nix sandbox, native ARM kernel or non-Linux run is established by this probe.

The Linux recipe therefore replaces `zero-rss-reading.patch` with `statm-rss-sampling.patch`, the unchanged diff from [the existing proposal's immutable head](https://github.com/storytold/photocraft/commit/0f0acd5e90dfb11f65d3976b78ead74e723835e5). It applies without fuzz to the selected manifest and produces that exact upstream manifest. Original sampling code and four tests remain unchanged; source pins and Cargo.lock stay unchanged. Both Linux targets use the supported feature, and Darwin keeps its existing patch selection. No competing PR is needed. Remove the backport when equivalent feature selection reaches the selected source and the affected unpatched tests pass.

After these changes, 50 patch files remain. Thirty-six have an existing upstream proposal, accepted fix or dependency owner; twelve remain distribution policy. The GCC UID candidate needs runtime-library validation before the correct upstream submission process, and the LightCraft allowance still needs a current unpatched UI run. These are different next actions, not four missing application PRs. The historical tables above describe earlier audit stages.

### PR feedback audit on 2026-10-15

A fresh audit captured all 30 tracked contribution URLs at 20:30 UTC, reading every returned issue comment, submitted review and inline review thread. Every connection reports no remaining page, including nested thread comments and head check contexts. The inventory remains 23 open, five merged and two closed. Review bodies matter independently of the aggregate review-decision field, which does not report every submitted change request.

| PR | Finding and next action |
| --- | --- |
| [VectorCraft #2111](https://github.com/storytold/vectorcraft/pull/2111#pullrequestreview-5537984107) | A reviewer requires an actual complete `cargo xtask ci` run covering formatting, Clippy, tests, assets, brands, layers and wasm, then a checked checklist and reported outcome. The focused selector checks do not satisfy this gate. Keep the checklist unchecked while the instruction to avoid full application builds remains in effect. No source defect or immediate rebase is requested. |
| [FigCraft #582](https://github.com/storytold/figcraft/pull/582#issuecomment-6199517141) | The maintainer is holding the proposal for the upstream owner's decision about runtime `fc-list` execution and a direct `rustix` dependency. This is a policy hold, not a request to bypass that decision with another implementation. The branch also conflicts; reconcile after the owner decides, preserving newer XDG and color-font support and the upstream 256 MiB cap. |
| [PdfCraft #2399](https://github.com/storytold/pdfcraft/pull/2399) | No reviewer request, but the branch now needs maintenance. A read-only merge against main `13e3154ab3c0eee937038ea188c0a731a331c5e7` finds five additive conflicts in the two roadmap files. The engine change merges cleanly as the original fixture/geometry repair and remains needed. Preserve all upstream progress records, retain the candidate milestone record and independently review the resulting three-file diff before updating the same PR. |
| [Nixpkgs #574123](https://github.com/NixOS/nixpkgs/pull/574123#pullrequestreview-5530442473) | The active changes-requested review refers to an older commit. The approved current eleven-line revision already removes the Python test and unrelated formatting. Await maintainer re-review; no new code request is present. Posted lint/evaluation and infrastructure checks pass with some jobs skipped; they do not establish fresh XMLTwig native/cross package builds. |
| [FigCraft #347](https://github.com/storytold/figcraft/pull/347) | The older padding concern is already addressed: the reviewed revision restores the original padding and uses geometry/scroll assertions. Await re-review without repeating the change. No new feedback or posted CI is present. |
| [FigCraft #568](https://github.com/storytold/figcraft/pull/568) | The maintainer merged current main into the reviewed branch. Independent inspection verifies that the production regular-file guard and every original test byte are preserved, with XDG tests appended. Ubuntu test and wasm checks pass. Record the maintainer head separately from the original human-reviewed head; no corrective code change is needed. |

The verified FigCraft integration head is [`46316c98`](https://github.com/storytold/figcraft/commit/46316c9895cb8178bcba80bfe92ee4c440e87203), whose parents include the exact original reviewed head `5454bdc2449b1fc8fa9fc826ebc8a4d3f758e2f7`. The remaining contributions have no new actionable feedback. DesignCraft #987 has a passing FreeBSD build/test check; most other heads have no posted checks, which is not a CI pass. A later compact query confirms GridCraft #1361 is mergeable, resolving its initially unknown mergeability without a head change.

This was a read-only PR audit. No PR branch or review state changed, and no full application build ran. The current source pins and local patches remain unchanged by this audit. Follow-up work should update existing PRs where appropriate, preserve maintainer-owned integration changes and respect the upstream policy hold.

### Research boundaries

The audit checked immutable pinned and main source snapshots, latest stable tags, relevant issue comments, PR reviews and inline threads. GitHub CLI REST requests reached a rate limit during the broader searches; targeted searches continued through the GitHub connector and direct source artifacts. Search terms do not establish an exhaustive search of all issues, all discussion history or every external forum. No new full application builds or native runtime matrix ran for this follow-up. Earlier strict-sandbox source-preparation receipts remain scoped to their recorded sources.

## EffectCraft temporal workaround retired after the builder update (2026-10-15)

The configured desktop ARM Linux interpreter is now QEMU 11.1.2, including the
accepted [TCG optimizer fix](https://gitlab.com/qemu-project/qemu/-/commit/e2ef4fc38cebeed8e621e30aa0d3c3c6a0389ba9).
The selected EffectCraft source remains
[`05955c08`](https://github.com/storytold/effectcraft/commit/05955c08b4fd025f1a09882df72e6dbff1a8148a).
Its original `auto_levels_temporal_smoothing_reads_neighbour_frames` test was
compiled from unchanged source with optimization level 3, debug assertions and
explicit overflow checks. Every retained dependency identity and checksum
matches the selected upstream lock.

The identical ARM executable fails with multiplication overflow under QEMU
11.1.1 and passes under 11.1.2. After activation, direct execution through the
registered binfmt handler also passed inside a Nix derivation with `sandbox =
true` and `sandbox-fallback = false`: exactly one test passed, zero failed.
Only the executable and its required ARM library closures were declared; the
interpreter came from the daemon's configured sandbox paths. No broader host
store binding or custom interpreter path was added for this check.

Remove `temporal-offsets.patch` and its package reference entirely, including the
downstream-only bounded-time test. The original upstream smoothing regression
remains enabled. This is an emulator fix, so no EffectCraft arithmetic PR is
needed. Other builders using the affected QEMU release should update their
interpreter rather than restore this source workaround.

This check covers the selected effects-crate regression, not a full application
build, the complete workspace suite, native ARM hardware or a fresh all-platform
package matrix. The test executable was compiled separately; the sandbox receipt
proves its execution inside the Nix build sandbox, not that its compilation was
sandboxed. After this retirement, 49 ArtCraft patch files remain. The earlier
50-patch count describes the preceding audit stage.

## GCC runtime validation and remaining upstream work (2026-10-15)

The GCC workaround is still needed. A standalone build of GCC 16.2.0's actual
`libgomp` shared library reproduces the original `target.c` format-truncation
error with the selected ARM cross compiler. The build uses optimization level 2,
fortification level 3, `-fno-strict-overflow` and the recovered hardening flags.
The existing downstream buffer bound and a separate one-line unsigned-format
candidate both build the shared runtime and its Fortran modules successfully.
No compiler bootstrap or application build was needed.

The smaller candidate changes the fallback ordinal format from `%d` to `%u`
and explicitly casts the ordinal to `unsigned`. Reviewed public callers exclude
negative ordinals before this helper is reached, so valid UID strings remain
unchanged. This addresses a build warning. It does not establish a reachable
buffer overflow or justify a security report. Retrieved
[GCC main](https://github.com/gcc-mirror/gcc/blob/d871a07ca522c4c54139833b9042a662745b7bd8/libgomp/target.c)
and the [GCC 16 branch](https://github.com/gcc-mirror/gcc/blob/8d06be85e7b25e32eb98613f3dc52ce8cd6efd72/libgomp/target.c)
still contain the original formatting.

Six unchanged upstream test programs pass with each repaired runtime on the
registered ARM QEMU 11.1.2 interpreter. They cover the C and Fortran device-UID
APIs, C parallel execution and C/Fortran target fallback. Loader traces confirm
that each program uses its newly built comparison library. The original runtime
cannot serve as a running baseline because its hardened build fails. The
comparison therefore uses the existing downstream repair as its baseline.

These twelve passing program runs are a focused comparison, not a complete
DejaGNU regression run. No offload plugin or hardware device was available, so
positive-device fallback formatting remains outside the public API test coverage.
A separate probe links the actual complete `target.c` with the other runtime
objects and passes eight valid-domain formatting, cache and provider cases for
each repair. Its synthetic private device descriptors do not replace public
offload-device coverage. The existing package fixture has a different purpose:
it tests defensive capacity for signed private-helper inputs that public callers
exclude. Its negative-input result must not be presented as a public runtime defect.

Retain `gcc-libgomp-device-uid-buffer.patch` and its existing fixture while the
smaller candidate is prepared for human and upstream review. Replacing a working
local repair solely to reduce the diff would not remove the dependency on a patch.
[GCC's contribution process](https://gcc.gnu.org/contribute.html) uses mailing-list
submission and requires regression evidence for the affected runtime.
[GCC's AI policy](https://gcc.gnu.org/ai-policy.html) requires a human to submit
contributions and reserves acceptance of generated code to maintainers under
its stated conditions. The candidate and evidence are prepared privately for
human review. No GitHub mirror PR, mailing-list message, DCO certification or GCC
commit has been made by this investigation.

## LightCraft hover follow-up (2026-10-15)

The selected LightCraft 0.8.0 source already includes several relevant upstream
repairs. In addition to the predicate wait in
[PR #199](https://github.com/storytold/lightcraft/pull/199) and shared demo cache
in [PR #445](https://github.com/storytold/lightcraft/pull/445), it includes the
render-pool and condition-variable fix in
[PR #557](https://github.com/storytold/lightcraft/pull/557).
[Issue #630](https://github.com/storytold/lightcraft/issues/630) identifies that
last repair as the resolution of its demo-initialization deadlock. Render-panic
handling from [PR #1149](https://github.com/storytold/lightcraft/pull/1149) is also
present. A fresh review of the relevant discussion and review comments found no
basis for duplicating those fixes or proposing a general ten-minute wait.

The remaining question is whether the original profile-hover test passes on the
selected source under current ARM emulation, including bounded contention.
Existing cached application outputs and historical suite logs cannot establish
that. Validation therefore uses the actual UI-library test target, with the
original fixture and selected locked dependencies, rather than an application
build or a replacement scheduler test. Compilation and runtime results must be
reported separately. The local 120- and 600-second waits remain cooperative
budgets between synchronous UI steps; neither guarantees a strict wall deadline.

The actual unpatched ARM UI-library target was compiled with Rust 1.98.1,
selected lock identities and checksums, upstream optimization and debug/overflow
checks, and the Linux HEIF, SAM and denoise features. No application binary was
built. The original profile test passed alone in 131.72 seconds, with one test
passed and 845 filtered out.

A two-test run restricted to four CPUs failed before the patched hover wait:
the profile fixture found zero variant thumbnails, and a 1:1 loupe companion
found no texture. The same executable and two tests passed with the configured
eight CPUs and eight Rayon threads in 185.72 seconds, with two passed and 844 filtered out. A subsequent
four-test run on eight CPUs with eight Rayon threads passed the profile fixture again but failed three
loupe companions on missing textures, with one passed, three failed and 842
filtered out in 199.93 seconds. The whole cohort is therefore not green.

All runs retained the original fixture assertions, used a 1536 MiB application
memory budget and QEMU 11.1.2, and completed without the runtime resource
watchdog terminating them. The contention results are consistent with CPU
throughput affecting readiness, but do not alone establish a renderer defect or
a deadlock. The profile fixture completes its original hover, texture, history,
click and favorite assertions under both eight-CPU cohorts. The separate loupe
failures need stage and renderer-state evidence before an upstream proposal.
They must not be hidden by the passing target test or described as failures of
the hover wait changed by the local patch.

Retire `profile-hover-test-deadline.patch`, its recipe reference and its lifecycle
entry. The selected original fixture passes alone and in the fully passing
two-test cohort at the configured eight-CPU setting. Retaining a hover-only
extension does not repair the separate pre-hover and loupe failures. No global
timeout increase or duplicate readiness PR is justified. After this retirement,
48 ArtCraft patch files remain; the earlier 49-patch count describes the
preceding stage.

This evidence covers focused UI-library tests under emulation. It does not
establish a full eight-thread UI-suite pass, a full application build, native ARM
hardware behavior or a new platform matrix. Compilation and execution took
place through the desktop workload runner, outside a Nix build derivation; they
are not new sandboxed compilation or execution receipts.

A final diagnostic rerun used a copied UI test crate with logging only; original
waits and assertions were unchanged. Only that UI crate was recompiled, with
cached dependencies. All original checkout hashes and the original executable
remained unchanged. The same four-test selection again passed the profile test
and failed the three loupe companions in 205.35 seconds.

Each failing companion's actual settle call returned false after approximately
120 seconds. Its expected region texture was absent, the region render was
pending, one render was in flight and no renderer failure was reported. The
initial main-image settles had succeeded. This identifies deadline exhaustion
while region rendering remained pending, rather than a premature quiet-spell
success or a reported render panic. The application budget remained 1536 MiB; the sampled
work gate was empty at the failure snapshots. These observations do not establish
a portable application defect or justify another upstream readiness PR.

The profile's diagnostic hover settle succeeded in 81.624 seconds with the hover
texture and loupe present and no render in flight. Its following original
120-second predicate wait returned true immediately. Do not retain or upstream
the 600-second hover extension to address unrelated region-render deadlines.
The full emulated UI suite still needs separate validation before claiming it
passes; these focused failures remain recorded even though this specific patch
can be removed.

## LightCraft loupe timeouts and emulated test resources (2026-10-15)

The follow-up reuses the selected unmodified ARM UI test executable, its original
assertions, 120-second settle budgets and a 1536 MiB application cache budget.
No LightCraft compilation or application build is needed for these comparisons.
The exact cohort contains the 1:1 native-window, side-by-side single-decode and
wipe-window tests described above.

| Execution context | Original selected scope | CPU affinity | Rayon workers | Test threads | Result | Libtest time |
| --- | --- | --- | --- | --- | --- | --- |
| Workload scope | 1:1 native-window test alone | Eight logical CPUs | 8 | 1 | 1 passed | 145.21 s |
| Workload scope | Three loupe tests | Eight logical CPUs | 8 | 1 | 3 passed | 152.00 s |
| Workload scope | Same three loupe tests | Eight logical CPUs | 8 | 3 | 3 failed | 168.51 s |
| Workload scope | Same three loupe tests | All 16 logical CPUs | 8 | 3 | 3 passed | 156.07 s |
| Strict Nix sandbox | Same three loupe tests | All 16 logical CPUs | 8 | 1 | 3 passed | 143.83 s |
| Strict Nix sandbox | Same three loupe tests | All 16 logical CPUs | 8 | 3 | 1 passed, 2 failed | 160.58 s |

The eight-CPU affinity chooses one thread on each physical core. The additional
eight logical CPUs are SMT siblings, not eight additional physical cores. The
last workload-scope comparison changes only CPU affinity. The failed concurrent run averaged
7.905 busy logical CPUs and accumulated 59.0 seconds of scope CPU pressure. The
successful unrestricted run averaged 10.572 and accumulated 2.9 seconds of scope
CPU pressure. No memory-limit event or external watchdog stopped either run.
This supports a runtime-resource explanation for these failures without changing
application code or weakening tests.

The sequential comparison also benefits from a shared process cache. Its first
cold test takes approximately 143 seconds; the remaining two add approximately
nine seconds. Do not attribute that result solely to reduced CPU oversubscription.
The [selected scene cache](https://github.com/storytold/lightcraft/blob/16dbb90499d3c63a6582fcbba1b2550a6e2da032/crates/engine/src/demo.rs)
single-flights a running generation for one key. It may evict ready entries under
its memory limit, so it is not a permanent once-per-process guarantee. Cache
churn across the full suite has not been measured by this cohort.

A separate tiny ARM Rust probe ran inside a real Nix derivation with strict
sandboxing and fallback disabled. It sees 16 CPUs and affinity 0-15 despite
`NIX_BUILD_CORES=8`. Its cgroup namespace reports `0::/`, and the cgroup CPU quota
file is unavailable. Rust therefore cannot use that hidden quota to reduce its
[available-parallelism result](https://doc.rust-lang.org/std/thread/fn.available_parallelism.html).
Compiler concurrency is not a bound on application worker pools. Both the global
and dedicated scene Rayon pools honor `RAYON_NUM_THREADS`; each renderer also
has its own job pool.

Ordinary x86-to-ARM cross package builds do not run these target library tests
by default. The selected [stdenv platform gate](https://github.com/NixOS/nixpkgs/blob/7fd4004d0511991fff3a0524856a9be09e28c5f0/pkgs/stdenv/generic/make-derivation.nix)
requires the build platform to execute the host platform. Explicit QEMU target
execution is a separate validation step. A native ARM derivation dispatched to
an emulated builder is another execution mode and must not be confused with
native-host cross compilation.

The selected [Cargo check hook](https://github.com/NixOS/nixpkgs/blob/7fd4004d0511991fff3a0524856a9be09e28c5f0/pkgs/build-support/rust/hooks/cargo-check-hook.sh)
sets `RUST_TEST_THREADS` after `preCheck`, so setting it only in `preCheck` is
ineffective. Libtest arguments after `--` are the supported explicit override;
`RAYON_NUM_THREADS` independently controls the Rayon pools. Test policy should
belong to the explicit emulation runner, preserving native ARM behavior.

The unchanged three-test cohort also passes sequentially inside a real Nix
sandbox, with `sandbox = true`, fallback disabled, eight Rayon workers and the
normal unrestricted affinity: three passed, zero failed, 843 filtered out in
143.83 seconds. It uses the already-built frozen ARM executable, its declared
ARM runtime libraries and the daemon's registered QEMU 11.1.2 interpreter. No
extra sandbox paths or cgroup mounts were introduced. This proves target test
execution under these settings, not sandboxed LightCraft compilation or a full
application build. The tiny CPU probe was also compiled separately.

The matching concurrent strict-sandbox run passed the 1:1 fixture and failed the
wipe and side-by-side texture assertions: one passed, two failed, 843 filtered
out in 160.58 seconds. Its input binary, Rayon count, memory budget, interpreter
and normal affinity match the serial sandbox run; only libtest concurrency and
the derivation identity change. No watchdog or external resource supervisor
stopped the process. Keep this failure in the validation record. The daemon
also has an 11.2-CPU quota, while the manual workload scope has no numeric quota.
The direct-to-sandbox comparison changes execution context and timing as well
as quota, so it does not isolate quota as the cause.

Use an explicit emulated-test policy for this resource-heavy cohort: retain the
runner's normal affinity, budget Rayon separately from compilation and pass
`--test-threads=1` to libtest. Eight Rayon workers and the three original loupe
fixtures are verified in the strict sandbox. Their internal renderer and Rayon
concurrency remains active. This is a measured option for focused QEMU checks,
not an architecture-wide native ARM package setting or a full-suite guarantee.
Keep the original waits, full-size inputs and texture assertions.

No new upstream renderer, cache or global-timeout PR is justified by these
results. Existing relevant repairs are already selected, and the original tests
complete under a bounded setup. A fuller investigation could still identify a
portable defect, but the current evidence does not establish one. Native ARM
hardware remains the appropriate control for representative full-suite runtime.
Those focused runs did not validate the complete UI suite, default automatic
Rayon count, native ARM execution or a fresh all-platform package matrix. The
complete-suite run below uses the explicit emulated-test policy.

## Explicit QEMU UI runner and complete-suite validation (2026-10-16)

LightCraft now exposes `mkEmulatedUiTest`, a Linux execution-check factory.
Callers supply a separately built ARM UI-library test executable, its target
runtime libraries, immutable fixture paths and an explicit QEMU package at
version 11.1.2 or newer. The factory does not depend on the application output or
change native ARM checks. It uses normal CPU affinity, eight Rayon workers,
one libtest thread, CPU rendering and fresh HOME/XDG state. Memory budgets below
64 MiB are rejected because upstream would ignore them.

The helper discovers the entire executable and its upstream ignored tests, runs
without selection filters or added skips, and checks every outcome against that
inventory. A zero or incomplete suite, mismatched inventory, crash, timeout or
failed test fails the check. It retains partial logs and a structured receipt,
handles interruption and child cleanup, and prints its receipt to the Nix build
log on failure. Normal libtest capture retains failed-test diagnostics; verbose
profiling is disabled for the full run. Thirteen focused process-boundary tests
cover failure propagation, count validation, environment isolation and cleanup.

The original cached executable embedded a developer-source path in
`CARGO_MANIFEST_DIR`. Two locale catalog tests read files relative to it. The
selected 823-file source tree and locked dependency identities were verified
and copied into an immutable store source. Only the UI test crate was rebuilt
against that location, reusing cached dependencies; no application or dependency
code generation occurred. Its optimization level, debug assertions, overflow
checks and selected features remain unchanged. The complete test inventory
still contains 846 tests, including the same three upstream-ignored performance
probes. Those ignores are reported separately and are not counted as passes.

A strict-sandbox preflight using explicit QEMU 11.1.2 passed both locale readers
and all three original loupe tests: five passed, zero failed, 841 filtered out,
in 141.67 seconds. This preflight is separate from the full unfiltered run.
Compilation of the supplied UI artifact happened outside the Nix sandbox;
execution receipts must not be described as sandboxed compilation.

The complete selected 0.8.0 UI-library suite ran under explicit QEMU 11.1.2 with
`sandbox = true` and fallback disabled: **842 passed, one failed, three upstream
ignored, zero filtered**, in 1839.74 seconds. All 846 discovered test names and
outcomes reconcile with the final summary; there was no timeout or incomplete
run. The three upstream-ignored performance probes are
`tests_keyword_sidebar::probe_keyword_sidebar_cost`, `tests_masking::grid_frame_100k` and
`tests_preview_limit::in_the_loupe::profile_slider_drag`. All non-ignored loupe tests,
profile-hover checks and locale readers passed in this unfiltered run.

The sole failure was
`export_task::contact_sheet_tests::contact_sheet_menu_dialog_picker_and_background_export`:
`export did not finish` at the original 20-second completion assertion. The
runner correctly returned failure and retained its full log and receipt. The
selected test can hide a worker error behind that assertion as well as time out
on slow work, so the message alone does not establish the cause.

Upstream [PR #1406](https://github.com/storytold/lightcraft/pull/1406), merged after
the selected release, already replaces this test's full demo with a small
procedural image and polls its picker/export worker directly. It preserves the
20-second guard and PDF/photo-count assertions while reporting export errors.
[Native Windows reports](https://github.com/storytold/lightcraft/pull/1250) also
identify this fixture as sensitive to loaded-suite timing. No duplicate PR,
broader timeout, source pin change or new source patch was added for this run.
The full result supports the explicit QEMU test policy for the loupe cases; the
complete suite remains failing on the selected release. Native ARM execution,
other platforms and sandboxed compilation require separate evidence.

A separate strict-sandbox control ran only the original contact-sheet test with
the same executable, fixtures, QEMU, normal affinity, Rayon count, memory budget
and fresh HOME/XDG policy, with profiling absent. It passed in 13.72 seconds:
one passed, zero failed, 845 filtered. This supports sensitivity to full-suite
context or timing rather than an unconditional export failure. It does not
prove why the full-run worker missed its deadline or erase that failed result.
Prefer the existing upstream fixture repair when adopting a release containing
it; do not add a duplicate PR, blanket timeout or new packaging patch from this
evidence. No additional compilation was needed for the control.

## Verification of the upstream contact-sheet fixture repair (2026-10-16)

The selected LightCraft v0.8.0 UI suite completed under strict Nix sandbox execution
with **842 passed, 1 failed, 3 upstream-ignored and 0 filtered**. Its sole failure was
`contact_sheet_menu_dialog_picker_and_background_export`, which exhausted its original
20-second completion guard. That same original test passed in isolation, so an isolated
candidate pass would not establish a repair.

A matched comparison retained the first 32 tests in the full suite's exact order,
including all 31 predecessors of the failure:

| UI test artifact | Passed | Failed | Filtered | Entire prefix time |
| --- | --- | --- | --- | --- |
| Selected source, unchanged fixture | 31 | 1 | 814 | 22.37 seconds |
| Selected source plus upstream fixture hunk | 32 | 0 | 814 | 3.32 seconds |

Both executions used explicit QEMU 11.1.2, normal CPU affinity, eight Rayon workers, one
outer test thread, a 1536 MiB application budget, fresh HOME/XDG directories, CPU
rendering and no profiling. Their exact discovered inventory, emulator version and
recorded runtime policies matched. The candidate retained the original 20-second guard
and all picker, PDF-header, Letter-landscape page-size and photo-count assertions.

Only the test hunk from [upstream commit
af4c5e10](https://github.com/storytold/lightcraft/commit/af4c5e102c9f97529f582003b99c21b89067e906),
already merged through [PR #1406](https://github.com/storytold/lightcraft/pull/1406),
was applied to the experimental artifact. All 823 selected source-file hashes were
checked; the sole changed file contains this test-only hunk. It uses a one-photo
procedural catalog and polls the real picker/export worker without repeatedly rendering
the surrounding gallery. It also reports worker errors directly instead of letting an
error appear as a completion timeout. The nominal photo dimensions are 96×64; this is
not a measurement of actual procedural source-generation size, which also depends on
renderer level buckets.

The repair fixes the reproduced prefix failure under this configuration. This comparison
does not identify which individual fixture change is responsible or prove the precise
scheduling cause of the original timeout. The candidate UI-library target was compiled
from cached dependencies outside a Nix build sandbox, then executed inside the strict
sandbox; no application or dependency code-generation rebuild was performed.

The full candidate UI suite then completed with **843 passed, zero failed, three
upstream ignored, zero filtered**, in 1842.62 seconds. All 846 discovered names and
outcomes reconciled with the final summary; its receipt reports a complete successful
run. All 40 non-ignored tests in the loupe module passed. The unchanged-source
full-suite failure above remains part of the record.

The experimental hunk has **not** been adopted by the package recipe, and native ARM
package behavior remains unchanged. No duplicate upstream PR is needed.

## Latest stable release and patch audit (2026-10-16)

All fourteen application release endpoints and the shared font repository were
checked against the committed pins. Only VectorCraft has a newer published stable
release; the other applications retain their current stable releases. The font
repository has no release tags, and its reviewed immutable snapshot remains the
current source. Development-branch fixes are not treated as released fixes.

| Package | Latest eligible version | Update |
| --- | --- | --- |
| cadcraft | [0.7.0](https://github.com/storytold/cadcraft/releases/tag/v0.7.0) | Already current |
| craft-launcher | [0.4.1](https://github.com/storytold/craft-launcher/releases/tag/v0.4.1) | Already current |
| deckcraft | [0.7.0](https://github.com/storytold/deckcraft/releases/tag/v0.7.0) | Already current |
| designcraft | [0.8.0](https://github.com/storytold/designcraft/releases/tag/v0.8.0) | Already current |
| effectcraft | [0.10.0](https://github.com/storytold/effectcraft/releases/tag/v0.10.0) | Already current |
| figcraft | [0.6.0](https://github.com/storytold/figcraft/releases/tag/v0.6.0) | Already current |
| filmcraft | [0.8.0](https://github.com/storytold/filmcraft/releases/tag/v0.8.0) | Already current |
| gridcraft | [0.7.0](https://github.com/storytold/gridcraft/releases/tag/v0.7.0) | Already current |
| lightcraft | [0.8.0](https://github.com/storytold/lightcraft/releases/tag/v0.8.0) | Already current |
| pdfcraft | [0.8.0](https://github.com/storytold/pdfcraft/releases/tag/v0.8.0) | Already current |
| photocraft | [0.9.0](https://github.com/storytold/photocraft/releases/tag/v0.9.0) | Already current |
| soundcraft | [0.7.0](https://github.com/storytold/soundcraft/releases/tag/v0.7.0) | Already current |
| vectorcraft | [0.12.0](https://github.com/storytold/vectorcraft/releases/tag/v0.12.0) | Updated |
| wordcraft | [0.7.0](https://github.com/storytold/wordcraft/releases/tag/v0.7.0) | Already current |
| craft-fonts | [0.1.0-unstable-2026-10-11](https://github.com/storytold/craft-fonts/commit/3d9ab3a132ed0eff457e424226a435a901da30d3) | Already current |

VectorCraft now selects release 0.12.0 at
[`8bc65329286d`](https://github.com/storytold/vectorcraft/tree/8bc65329286dc1b84aa392997bb205613c3e96cb),
published 2026-10-16. Its exact upstream Cargo lockfile replaces the previous
lock. The shared PDF reader/writer introduces `craft-pdf`, `hayro-interpret`,
`hayro-jbig2`, `hayro-syntax` and `krilla` from the immutable craft-libs revision
[`ca50d63b773c`](https://github.com/storytold/craft-libs/tree/ca50d63b773c99f96e75c77ce5a1d21e7c9cda0d).
Each Git package has an explicit source hash. Their root notices reference
nested license texts outside the Cargo workspace member. VectorCraft's notice
installer now preserves each dependency's complete `licenses/` subtree with its
relative paths, including the PDF writer's MIT/Apache and ICC-profile terms.
The regression fails against the former root-only installer and passes with
the fix; three cases cover nested bytes/paths, root-only older inputs and the
existing required-license check. An install-only check against the actual new
immutable Git source also preserved all sixteen nested texts, root notices and
source metadata, including repeated inputs from the same Git revision.
Existing print/UI Git inputs and
the font input are unchanged. The release retains Rust 1.95 as its minimum.
The font snapshots required by FigCraft and DeckCraft retain their separate
Latin manifest; substituting the default font branch would remove that input.

The local VectorCraft `register-all-craft-fonts.patch` is removed in full.
Release 0.12.0 includes [the accepted registration fix](https://github.com/storytold/vectorcraft/pull/2111)
and its [implementation](https://github.com/storytold/vectorcraft/commit/83f40f135acd8b0fc68102c302e1f6c14e708c58):
the Japanese/Arabic/Thai fallback prefix stays first, remaining supplied faces
follow in manifest order, and upstream regressions check family/style lookup,
mixed-script deduplication and empty input. Two dependency-free tests of the
exact extracted upstream helper passed. This is focused helper validation,
not a new execution of the complete text crate with real fonts.

The baseline registry contained 48 patch files. All 47 retained patches were
checked against their unchanged selected application or exact vendor/toolchain
sources and apply with zero fuzz, including sequential Launcher changes.
Their existing reviewed reasons and removal conditions remain applicable at
those revisions. The source revision and empty patch inventory for VectorCraft
are updated in the lifecycle registry. No other patch was removed or weakened.
In particular, the verified LightCraft contact-sheet fixture repair is still
newer than its latest stable release; this update does not move LightCraft to
main or add that experimental hunk to its package recipe. GCC and other
platform-specific build repairs remain independent of application releases.

The updated VectorCraft source and complete Cargo vendor directory were fetched
and verified successfully through Nix. The build plan contained only source,
Git-package extraction and vendor-directory derivations. No application or
compiler target was built. Release freshness, immutable source and lockfile
identity, dependency hashes, lifecycle decisions and focused helper checks
cover this update; application compilation and a new runtime/platform matrix
remain unverified. Existing build receipts retain their original revisions.

`just check` passed for x86_64-linux, aarch64-linux and aarch64-darwin with
`eval-cores = 1`. The initial configured parallel evaluation was terminated
with exit 137; the successful retry limits evaluator threads for that command
only and changes no daemon or platform policy. The source-pin check validated
164 source/dependency hashes across 63 source files and all 47 lifecycle
entries. All 27 package Python test suites passed, including the three new
VectorCraft notice-installation regressions. Formatting, type, shell, Markdown,
relative-link, whitespace and publication checks cover the changed files.

## Remaining 47 patches: upstream status (2026-10-16)

This review accounts for every current patch file and checks its SHA256 and
selected source revision against the [lifecycle registry](../artcraft-patch-lifecycle.json).
Official proposal state, relevant conversation/review comments, source coverage
and accepted-commit ancestry were checked on 2026-10-16. The earlier release
refresh supplies exact-source, zero-fuzz applicability evidence; this review
adds no application compilation or new runtime-test result.

| Primary retirement path | Files | Current action |
| --- | --- | --- |
| Merged, awaiting a containing release | 8 | Keep backports until a selected release includes equivalent behavior and affected checks pass. |
| Already covered by open PRs | 17 | Continue those proposals and their review/rebase work; no duplicate PR. |
| Distribution-specific policy | 10 | Keep local while the chosen inputs, branding and integration policy remain. |
| Mixed upstream/local components | 10 | Adopt and retire individual covered hunks; preserve or separately handle the remaining policy/tests. |
| Toolchain workarounds | 2 | Follow GCC or Nixpkgs/Rust/LLVM resolution and validate the actual selected toolchain. |
| Required new ArtCraft application PRs | 0 | No uncovered portable product fix justifies another proposal now. |

Each of the 47 files appears exactly once below. Mixed files can contain a
merged fix as well as open work or local policy, so the eight-file merged count
is not a count of all accepted upstream components. An open PR's provisional
GitHub merge SHA is not evidence of acceptance. Upstream state alone does not
justify removing a fix from an older selected release.

### Merged fixes awaiting release

| Package | Patch | Upstream coverage and next step |
| --- | --- | --- |
| craft-launcher | [preserve-update-backups-upstream-a2e490.patch](../../pkgs/by-name/cr/craft-launcher/preserve-update-backups-upstream-a2e490.patch) | [craft-launcher #332](https://github.com/storytold/craft-launcher/pull/332) merged; adopt a containing release and verify recovery preserves existing backups. |
| deckcraft | [appstream-screenshot.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/de/deckcraft/appstream-screenshot.patch) | [deckcraft #746](https://github.com/storytold/deckcraft/pull/746) merged; validate the released screenshot, attribution and AppStream metadata. |
| designcraft | [appstream-screenshot.patch](../../pkgs/by-name/de/designcraft/appstream-screenshot.patch) | [designcraft #957](https://github.com/storytold/designcraft/pull/957) merged; accept equivalent valid image metadata, then validate the packaged result. |
| effectcraft | [appstream-screenshot.patch](../../pkgs/by-name/ef/effectcraft/appstream-screenshot.patch) | [effectcraft #1480](https://github.com/storytold/effectcraft/pull/1480) merged; validate released AppStream metadata before dropping the backport. |
| effectcraft | [relative-footage-path-order.patch](../../pkgs/by-name/ef/effectcraft/relative-footage-path-order.patch) | [effectcraft #1391](https://github.com/storytold/effectcraft/pull/1391) merged; adopt the repaired relative-path fixture and run its affected regression. |
| figcraft | [native-window-app-id.patch](../../pkgs/by-name/fi/figcraft/native-window-app-id.patch) | [figcraft #346](https://github.com/storytold/figcraft/pull/346) merged; verify the packaged native window identity without the backport. |
| lightcraft | [appstream-screenshot.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/li/lightcraft/appstream-screenshot.patch) | [lightcraft #1795](https://github.com/storytold/lightcraft/pull/1795) merged; validate equivalent released screenshot metadata, including asset availability. |
| lightcraft | [heif-mime-types.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/li/lightcraft/heif-mime-types.patch) | [lightcraft #1795](https://github.com/storytold/lightcraft/pull/1795) merged; verify released HEIF desktop declarations with the enabled codec features. |

### Existing open proposals

| Package | Patch | Upstream coverage and next step |
| --- | --- | --- |
| craft-launcher | [atomic-state-upstream-314.patch](../../pkgs/by-name/cr/craft-launcher/atomic-state-upstream-314.patch) | [craft-launcher #314](https://github.com/storytold/craft-launcher/pull/314) is open and needs rebase/conflict work; continue recovery/settings validation there. |
| craft-launcher | [autostart-exec-quoting.patch](../../pkgs/by-name/cr/craft-launcher/autostart-exec-quoting.patch) | [craft-launcher #420](https://github.com/storytold/craft-launcher/pull/420) is open; retain until released executable-path quoting passes the native regression. |
| craft-launcher | [macos-quit-handshake.patch](../../pkgs/by-name/cr/craft-launcher/macos-quit-handshake.patch) | [craft-launcher #335](https://github.com/storytold/craft-launcher/pull/335) is open; validate the launcher's own AppKit close acknowledgement, close-to-tray and packaged dependency. |
| craft-launcher | [nix-linux-process-locale.patch](../../pkgs/by-name/cr/craft-launcher/nix-linux-process-locale.patch) | [craft-launcher #482](https://github.com/storytold/craft-launcher/pull/482) is open and rebased onto current main; compare its Unicode process lookup under the affected locale before retiring this fallback. |
| craft-launcher | [unix-restart-test-path-helpers.patch](../../pkgs/by-name/cr/craft-launcher/unix-restart-test-path-helpers.patch) | [craft-launcher #424](https://github.com/storytold/craft-launcher/pull/424) is open; preserve the portable executable/path regression when adopting it. |
| designcraft | [register-all-craft-fonts.patch](../../pkgs/by-name/de/designcraft/register-all-craft-fonts.patch) | [designcraft #987](https://github.com/storytold/designcraft/pull/987) is open; retain explicit optional input, script priority and all-supplied-family coverage. |
| effectcraft | [system-font-fixture.patch](../../pkgs/by-name/ef/effectcraft/system-font-fixture.patch) | [effectcraft #1591](https://github.com/storytold/effectcraft/pull/1591) is open; coordinate with [effectcraft #1298](https://github.com/storytold/effectcraft/pull/1298) and retain native font coverage without brittle counts. |
| filmcraft | [japanese-font-test-system-fallbacks.patch](../../pkgs/by-name/fi/filmcraft/japanese-font-test-system-fallbacks.patch) | [filmcraft #1944](https://github.com/storytold/filmcraft/pull/1944) is open; check supplied, absent and system-fallback Japanese font cases after adoption. |
| filmcraft | [system-font-fixture.patch](../../pkgs/by-name/fi/filmcraft/system-font-fixture.patch) | [filmcraft #2072](https://github.com/storytold/filmcraft/pull/2072) is open; validate the portable font fixture while keeping native coverage. |
| gridcraft | [appstream-screenshot.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/gr/gridcraft/appstream-screenshot.patch) | [gridcraft #1361](https://github.com/storytold/gridcraft/pull/1361) is open; retain until a release supplies equivalent valid screenshot metadata. |
| lightcraft | [candle-metal-device-bounds.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/li/lightcraft/candle-metal-device-bounds.patch) | Existing [Candle #3413](https://github.com/huggingface/candle/pull/3413) and [#3645](https://github.com/huggingface/candle/pull/3645) are open. Adoption needs a compatible fixed Candle lock and no-visible-Metal-device regression; a LightCraft release alone is insufficient. |
| pdfcraft | [native-wayland-clipboard-fixture.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/pd/pdfcraft/native-wayland-clipboard-fixture.patch) | [pdfcraft #2622](https://github.com/storytold/pdfcraft/pull/2622) is open; validate its isolated native fixture and adapt the package runner when adopted. |
| pdfcraft | [native-wayland-clipboard.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/pd/pdfcraft/native-wayland-clipboard.patch) | [pdfcraft #2261](https://github.com/storytold/pdfcraft/pull/2261) is open; this is the production Wayland backend feature, separate from the test fixture. |
| photocraft | [headless-shortcut-test.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/ph/photocraft/headless-shortcut-test.patch) | [photocraft #6227](https://github.com/storytold/photocraft/pull/6227) is open; retain GPU-independent assertions and separately checked native snapshots. |
| photocraft | [statm-rss-sampling.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/ph/photocraft/statm-rss-sampling.patch) | [photocraft #5399](https://github.com/storytold/photocraft/pull/5399) is open; retain feature selection until a containing source passes the affected memory-sampling tests. |
| soundcraft | [appstream-screenshot.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/so/soundcraft/appstream-screenshot.patch) | [soundcraft #583](https://github.com/storytold/soundcraft/pull/583) is open; keep the local metadata until released equivalent coverage validates. |
| wordcraft | [optional-thai-cache-miss-fixture.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/wo/wordcraft/optional-thai-cache-miss-fixture.patch) | [wordcraft #1981](https://github.com/storytold/wordcraft/pull/1981) is open; keep cache insertion/reuse/invalidation assertions with and without supplied Thai input. |

### Keep as distribution policy

| Package | Patch | Upstream coverage and next step |
| --- | --- | --- |
| craft-launcher | [nix-bundle-integration.patch](../../pkgs/by-name/cr/craft-launcher/nix-bundle-integration.patch) | Keep Nix wrappers, desktop identity, icons and explicit runtime integration. Reduce only proven overlap with future upstream runtime/ownership support. |
| craft-launcher | [nix-cjk-fonts.patch](../../pkgs/by-name/cr/craft-launcher/nix-cjk-fonts.patch) | Keep chosen pinned font inputs and their package regression. Generic Fontconfig discovery is an optional design opportunity, not a replacement for input policy. |
| craft-launcher | [nix-discovery-priority.patch](../../pkgs/by-name/cr/craft-launcher/nix-discovery-priority.patch) | Keep distribution-specific precedence. [craft-launcher #373](https://github.com/storytold/craft-launcher/pull/373) is a Windows interface, not an agreed portable Nix discovery contract. |
| craft-launcher | [remove-restricted-marks.patch](../../pkgs/by-name/cr/craft-launcher/remove-restricted-marks.patch) | Keep derivative-package branding/asset policy under the selected source terms; upstream retains its own branding. |
| designcraft | [remove-restricted-marks.patch](../../pkgs/by-name/de/designcraft/remove-restricted-marks.patch) | Keep derivative-package branding/asset policy under the selected source terms; upstream retains its own branding. |
| effectcraft | [remove-restricted-marks.patch](../../pkgs/by-name/ef/effectcraft/remove-restricted-marks.patch) | Keep derivative-package branding/asset policy under the selected source terms; upstream retains its own branding. |
| filmcraft | [remove-restricted-marks.patch](../../pkgs/by-name/fi/filmcraft/remove-restricted-marks.patch) | Keep derivative-package branding/asset policy under the selected source terms; upstream retains its own branding. |
| pdfcraft | [font-input-attribution.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/pd/pdfcraft/font-input-attribution.patch) | Keep attribution matched to the actual curated font revision. [pdfcraft #1484](https://github.com/storytold/pdfcraft/pull/1484) uses a different input and needs deliberate adaptation. |
| pdfcraft | [remove-restricted-marks.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/pd/pdfcraft/remove-restricted-marks.patch) | Keep derivative-package branding/asset policy under the selected source terms; upstream retains its own branding. |
| soundcraft | [packaged-symbol-fonts.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/so/soundcraft/packaged-symbol-fonts.patch) | Keep packaged DejaVu input and the Linux glyph regression. Upstream discussion in [soundcraft #141](https://github.com/storytold/soundcraft/pull/141) requests runtime fallback rather than a compiled font bundle. |

### Mixed files: retire by component

| Package | Patch | Upstream coverage and next step |
| --- | --- | --- |
| craft-launcher | [appimage-runtime-and-safe-refresh.patch](../../pkgs/by-name/cr/craft-launcher/appimage-runtime-and-safe-refresh.patch) | [craft-launcher #328](https://github.com/storytold/craft-launcher/pull/328) is open; pinned runtime/environment and legacy policy remain local. Offer conservative custom-entry protection on that proposal; [craft-launcher #355](https://github.com/storytold/craft-launcher/pull/355) has changes requested and is not equivalent. |
| craft-launcher | [nix-managed-applications.patch](../../pkgs/by-name/cr/craft-launcher/nix-managed-applications.patch) | [craft-launcher #459](https://github.com/storytold/craft-launcher/pull/459) and [craft-launcher #328](https://github.com/storytold/craft-launcher/pull/328) cover portable subsets; the former has been rebased onto current main. Preserve remaining store/identity/version/discovery policy and retire only covered hunks. |
| deckcraft | [approved-ui-fonts.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/de/deckcraft/approved-ui-fonts.patch) | [deckcraft #42](https://github.com/storytold/deckcraft/pull/42) owns asset compliance. Keep supplied-face/hinting compatibility; coordinate a dedicated-monospace regression on that PR after confirming its behavior. |
| effectcraft | [fontconfig-discovery.patch](../../pkgs/by-name/ef/effectcraft/fontconfig-discovery.patch) | Open [effectcraft #1540](https://github.com/storytold/effectcraft/pull/1540) repairs configuration scanning; [effectcraft #1592](https://github.com/storytold/effectcraft/pull/1592) repairs directory traversal. Compare configured font-file coverage before retiring the package's fc-list hook. |
| figcraft | [nix-fontconfig-discovery.patch](../../pkgs/by-name/fi/figcraft/nix-fontconfig-discovery.patch) | [figcraft #582](https://github.com/storytold/figcraft/pull/582) is open and held for owner policy review. Merged [figcraft #474](https://github.com/storytold/figcraft/pull/474) and [figcraft #568](https://github.com/storytold/figcraft/pull/568) are complementary; the fixed 57-face input regression remains local. |
| figcraft | [portable-ui-regressions.patch](../../pkgs/by-name/fi/figcraft/portable-ui-regressions.patch) | Rename repair [figcraft #472](https://github.com/storytold/figcraft/pull/472) is merged; revised credits [figcraft #347](https://github.com/storytold/figcraft/pull/347) remains open. Reduce those test hunks independently after adoption. |
| pdfcraft | [native-script-fonts.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/pd/pdfcraft/native-script-fonts.patch) | Open [pdfcraft #1484](https://github.com/storytold/pdfcraft/pull/1484) covers portable script-stack behavior, including Droid Chinese preference. Curated font revision and input-specific assertions still require local adaptation. |
| pdfcraft | [ocr-fixture-resolution.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/pd/pdfcraft/ocr-fixture-resolution.patch) | Fixture repair [pdfcraft #1197](https://github.com/storytold/pdfcraft/pull/1197) is merged; physical-size follow-up [pdfcraft #2399](https://github.com/storytold/pdfcraft/pull/2399) is open. Adopt both before retiring the whole file; separate production downsampling is not equivalent. |
| photocraft | [register-all-craft-fonts.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/ph/photocraft/register-all-craft-fonts.patch) | Open [photocraft #2169](https://github.com/storytold/photocraft/pull/2169) proposes portable Arabic registration with input budgets. The broader all-selected-input policy remains local; avoid a competing blanket font-bundling PR. |
| wordcraft | [register-all-craft-fonts.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/wo/wordcraft/register-all-craft-fonts.patch) | Core registration [wordcraft #1668](https://github.com/storytold/wordcraft/pull/1668) is merged. Chinese priority is local; the stronger all-supplied-family assertion is an optional generic test follow-up. Split these components on adoption. |

### Separate toolchain work

| Package | Patch | Upstream coverage and next step |
| --- | --- | --- |
| craft-launcher | [gcc-libgomp-device-uid-buffer.patch](../../pkgs/by-name/cr/craft-launcher/gcc-libgomp-device-uid-buffer.patch) | Temporary GCC/libgomp build repair. The reviewed packet still needs human action through the [GCC contribution process](https://gcc.gnu.org/contribute.html); retain until the actual unpatched hardened compiler/runtime configuration validates. |
| pdfcraft | [rten-vnni-intrinsic.patch](https://github.com/nix-forge/nixpkgs-personal/blob/d199632c9727bd2ed2ff8782c2ac7fcd69d27254/pkgs/by-name/pd/pdfcraft/rten-vnni-intrinsic.patch) | Temporary selected Rust/LLVM pairing repair. Follow [Nixpkgs #524570](https://github.com/NixOS/nixpkgs/pull/524570); [#544495](https://github.com/NixOS/nixpkgs/pull/544495) was closed without merge. Validate the selected compiler and unpatched RTen before removal; no competing app or RTen assembly PR. |

### Work still worth doing

Continue existing proposals rather than starting another blanket PR round.
Launcher #459 and #482 have been rebased and GitHub reports them mergeable.
Launcher #314 still reports conflicts and has explicit rebase feedback; a reviewed
resolution is prepared, but updating its third-party branch requires its owner
or an upstream maintainer. Preserve conservative handling of customized desktop entries
when improving #328, and respect the outstanding changes requested on #355.
FigCraft #582 needs an owner decision on subprocess Fontconfig discovery and
its additional dependency; a duplicate proposal would not resolve that policy.

The optional WordCraft follow-up is a small regression asserting that every
explicitly supplied font family can be resolved. Current main has the accepted
registration behavior and Arabic/CJK coverage, while the stronger local
all-family assertion remains absent. This is additional generic test coverage,
not a missing product repair or a reason to retain the whole runtime patch.
DeckCraft's dedicated-monospace/advance check can instead improve existing #42
after coordination and confirming its actual behavior. Broader Fontconfig or
external-package interfaces first need an agreed upstream contract.

The GCC repair remains an outstanding human GCC-channel submission. It is
neither a missing ArtCraft GitHub PR nor permanent Nix policy. The RTen case
already has an owning LLVM-upgrade proposal; retain the bounded workaround
until the selected compiler and unpatched library validate.

On future source updates, remove the eight accepted backports only after checking
the actual containing release and affected regressions. Apply the same process
to accepted portions of mixed files, including FigCraft's rename regression,
PdfCraft's first OCR fixture repair and WordCraft registration. FigCraft's
merged XDG/special-file fixes are complementary source-adoption work; they do
not replace the local fc-list hunk. The remaining local portions need their
own decisions instead of wholesale file deletion. No patch is removed by this
status review.

The lifecycle description for Launcher's macOS close patch is corrected to its
actual own-close/close-to-tray scope, with native quit, tray and packaged
`craft-quit` validation required before retirement. Patch bytes and source pins
are unchanged. No new PR, comment or external submission was made.

## Conflict resolution and mixed-hunk cleanup (2026-10-16)

[Launcher #459](https://github.com/storytold/craft-launcher/pull/459) and
[#482](https://github.com/storytold/craft-launcher/pull/482) were rebased onto
main `307efcf45a080af9643e750d43034eb25540cef8`. Independent review passed and
GitHub reports both updated heads mergeable. The ownership guard in #459 now
runs inside the shared `install_at` entry point before destination handling
or download work. Its regression covers both public install entry points.
The #482 resolution preserves upstream catalog additions, retains the scanner
implementation and supplies the new backend job fields in its regression.
Formatting, offline manifest metadata and whitespace checks passed; these
rebases do not add native-crate or application runtime evidence.

A reviewed merge resolution for
[Launcher #314](https://github.com/storytold/craft-launcher/pull/314) preserves
the original author's two Rust changes and current main's manifest and lockfile,
including Windows ZIP support and the regular `tempfile` dependency. The
existing PR is owned by another contributor; this account cannot update its
branch or the upstream repository. A verified Git bundle retains the original
author's commit and the resolution for an owner or maintainer handoff. No
competing PR or unsolicited maintainer message was created.

All ten mixed patch files were reviewed against their exact selected source
commits and declared patch order. Two intermediate Launcher hunks were removed:
`nix-managed-applications.patch` added a six-line AppImage dispatch guard that
`appimage-runtime-and-safe-refresh.patch` later deleted. Removing both opposing
hunks, and correcting subsequent patch coordinates, leaves the final source
byte-for-byte identical across all 37 files touched by Launcher's 12 source
patches. Both patch stacks apply with zero fuzz. The final AppImage dispatch,
safe desktop refresh and ownership behavior remain in place. Only the two
matching lifecycle SHA256 entries change.

No other mixed hunk is safely removable from the current selected releases.
DeckCraft's approved font stack, EffectCraft and FigCraft Fontconfig discovery,
FigCraft's UI regressions, PdfCraft's script fonts and OCR fixtures, PhotoCraft's
explicit font registration, and WordCraft's registration and family assertion
still supply behavior or coverage absent from their selected commits. In
WordCraft, Chinese priority is preserved by the existing chain rather than a
separate added hunk that could be deleted. Merged fixes on newer development
main do not make those selected-source backports redundant.

The count remains 47 patch files. This cleanup removes intermediate patch
churn; it does not remove an entire patch or advance any application source pin.
No full application build was run.
