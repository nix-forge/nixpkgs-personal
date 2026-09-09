# NUR submission packet

Prepared 2026-09-08 for `nix-forge/nixpkgs-personal`. Registration has not been
submitted. The direct flake remains the primary interface.

## Verified checkout

Validation used the working tree based on package commit
`5d62685c585aab9982b9b2ffbfe57b6abc3b587b`, including the pending licensing and
NUR preparation changes. Reports explicitly record `repository_dirty = true`.
These results do not describe the unchanged public commit.

| Check | Result |
| --- | --- |
| Restricted index, [locked Nixpkgs](https://github.com/NixOS/nixpkgs/tree/801bef6abd86b91e51083066b83fb354a11fc640) | 12 entries, passed |
| Restricted index, [unstable Nixpkgs](https://github.com/NixOS/nixpkgs/tree/dc5d91f840324650bac8c379428c7037a416959a) | 12 entries, passed |
| Supported-platform evaluation, both Nixpkgs revisions | 86 derivations across all 39 packages, passed |
| Native Linux x64, locked Nixpkgs | All 27 outputs built or reused successfully |
| Native macOS ARM64, locked Nixpkgs | All 34 outputs built or reused successfully |
| PersonalMonitor | Native compilation, bundle checks, helper self-test and strict macOS signature verification passed |
| Package independence, policy and Python suites | Passed, including the NUR registration regression tests |
| Formatting, lint, type checks, hooks and secret scanning | Passed |
| NUR manifest | Exactly one new entry; upstream formatter passed; lock file unchanged |

The macOS build used a separate source snapshot without activating a system or
launching applications. Every resulting derivation path was compared with the
current checkout's macOS package set and matched. There was no usable ARM Linux
builder in the available configuration, so its 25 supported packages were
evaluated but not built. Native builds used the locked Nixpkgs revision; current
unstable was evaluated separately. GUI behavior, permissions and service logins
were not tested. The original upstream licensing evidence limitations remain.

## Manifest

The [registration entry](nur-registration.json) supplies the repository URL and
public GitHub contact. The [four-line patch](nur-registration.patch) adds only
that entry to `repos.json`, based on NUR commit
`c9d28a9dc181899c9df1390804837b28cff3b0ae`. It leaves `repos.json.lock` untouched.
NUR's own manifest formatter accepted the change. It was invoked through Python
with `aiohttp` from pinned Nixpkgs because the direct nix-shell shebang failed in
the local Nix installation. Both invoke the same `bin/nur` formatter.

The `nix-forge` name was available at that revision. Recheck availability and
regenerate or rebase the patch before submitting against a later NUR revision.
Apply it in a NUR checkout, not in this package repository:

```sh
git apply --check /path/to/nixpkgs-personal/docs/nur-registration.patch
git apply /path/to/nixpkgs-personal/docs/nur-registration.patch
./bin/nur format-manifest
git diff --check
git diff -- repos.json
```

## Publication gates

- Publish the reviewed package changes before proposing the NUR manifest entry.
  A public `default.nix` alone does not publish local metadata and license fixes.
- Run the existing CI pipeline on that exact published commit. Its NUR matrix
  covers locked and current unstable Nixpkgs; native package builds are separate.
- Review the complete committed tree against NUR's MIT declaration. The reviewed
  notices are the root `LICENSE`, the OCR Capture, Finder Favorites and Steam CEF
  helper MIT licenses, and Noctalia's `UPSTREAM-LICENSE`. The package sources and
  vendor payloads fetched during builds are distinct from these committed files.
- Keep the existing hosted-build exclusions and disabled package-cache publishing.
  NUR membership does not supply missing upstream permissions.
- Confirm the namespace remains available, then submit only `repos.json` to NUR.

## Draft pull request

Title: `add nix-forge repository`

```markdown
Add https://github.com/nix-forge/nixpkgs-personal as `nur.repos.nix-forge`.

The repository provides 39 standalone package recipes for Linux and macOS,
including personal variants, fonts, agent skills and native utilities. Its
`default.nix` accepts NUR's `pkgs` and preserves the consumer's unfree policy.
The direct flake remains available independently of NUR.

The repository has restricted NUR evaluation checks against locked and current
unstable Nixpkgs, metadata and provenance checks on supported platforms, and
separate native build jobs. Hosted-build exclusions and license limitations are
documented in `docs/package-licensing.md`.

- [ ] I ran `./bin/nur format-manifest` after updating `repos.json`.
- [ ] By including this repository in NUR, I confirm that any copyrightable
      content in the repository, other than built derivations or patches if
      applicable, is licensed under the MIT license.
- [ ] I confirm that `meta.license` and `meta.sourceProvenance` have been set
      correctly for unfree packages and packages not built from source.
- [ ] Applicable metadata fields have been filled out. `meta.mainProgram` is
      supplied for command entrypoints and omitted for data-only packages.
```

The draft checkboxes remain unchecked until the final published tree and current
upstream checklist have been reviewed. This preparation does not claim that NUR
has accepted the repository or that its current public revision includes local
changes.
