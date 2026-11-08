# chatgpt-latest

The upstream Nixpkgs `chatgpt` recipe with independently updated stable vendor
releases for x86-64 Linux, ARM64 Linux and Apple Silicon macOS. Build phases,
Linux resource handling and backend selection remain upstream. Generic Darwin
fixup is disabled to preserve the signed vendor bundle.
Darwin's install-time version check reads the actual bundle metadata without
executing the GUI app, so macOS does not protect it before Nix finalizes the output.

```sh
nix build .#chatgpt-latest
python3 pkgs/by-name/ch/chatgpt-latest/update.py --dry-run
```

The updater selects each platform's newest stable release independently from
OpenAI's Sparkle appcast and Debian package indexes. It rejects duplicate fields,
conflicting latest records, unexpected download paths and downgrades. Downloads
must match the declared size and, on Linux, the publisher's SHA-256 checksum.
Darwin's TLS-delivered full ZIP is pinned by its downloaded SHA-256 checksum.
XML parsing disables entities and external references; compressed and expanded
metadata have size limits. Requests have time limits and metadata redirects must
remain on the same HTTPS origin. Unchanged versions reuse their existing pins.

`--dry-run` prepares and verifies changed downloads but leaves `source.nix`
untouched. Publication preserves file modes and uses the package-local rollback
helper. Concurrent edits detected before publication stop the update. Direct
Python invocation needs Nix, nixfmt and defusedxml. The packaged updater declares
these dependencies and accepts `--package-dir` for an editable standalone copy.

The repository's daily update workflow discovers this updater automatically and
opens a package update PR. Releases become installed after the PR passes checks,
merges, and the consuming configuration updates. Failed feeds or checks leave the
existing pins in place; no updater can guarantee immediate release adoption.

The recipe accepts the upstream `codex` dependency. Consumers can inject their
chosen CLI without adding a dependency on another personal package directory:

```nix
pkgs.chatgpt-latest.override { codex = pkgs.codex-latest; }
```

Upstream uses it for Linux's launcher, `codex` and `codex-code-mode-host`
resources. The signed macOS bundle retains its vendor backend. Installing a new
CLI does not establish frontend/backend protocol compatibility; validate local
and remote tasks after upgrades.

Sources: [Nixpkgs recipe](https://github.com/NixOS/nixpkgs/tree/nixos-unstable/pkgs/by-name/ch/chatgpt),
[Darwin appcast](https://persistent.oaistatic.com/codex-app-prod/appcast.xml),
[Linux amd64 feed](https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages.gz),
[Linux ARM64 feed](https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-arm64/Packages.gz).
