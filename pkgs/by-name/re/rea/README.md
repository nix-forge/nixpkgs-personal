# REA

REA provides the `rea` and `rea-agents` commands and a stdio MCP server. This
recipe builds the public stable TypeScript release and its matching native PTY
addon from source with the upstream npm lockfile. The recipe requires the
unmodified Nixpkgs Node 24 package at version 24.22.2 or newer and Brotli 1.2.1
or newer on both Linux and Darwin. Older package sets fail evaluation rather
than selecting a private Node/Brotli source fallback. Native builds use the
selected Node for build tools and the installed runtime; cross builds use a
separate executable build-platform Node with the same minimums. Supply Node
and Brotli from the same package set when overriding the recipe.

On Darwin the recipe also compiles the process-ownership and native UI Swift
helpers. A local patch selects those packaged helpers while preserving
upstream's process validation and the source checkout's runtime compilation
fallback. Earlier native Node memory, network, CLI, MCP and PTY check results
are historical evidence; their retired package install checks no longer run.

The locked EVMole npm dependency includes WASM bytecode. The package preserves
upstream's engine and notice, and records that bytecode in `sourceProvenance`.

## Agent integration

The runtime includes the generated `reverse-engineer-anything` skill because
upstream's user-invoked `rea setup` reads it relative to the installed
application. The `skills` output contains the same generated bundle under
`share/agent-skills/reverse-engineer-anything`, including all reference files
and the MIT license. This output has no runtime dependency on Node or REA. It
shares the application's release pin and updater; its skill revision, tool
count, and fallback command version come from upstream's generator.

For example, Home Manager can install the instructions declaratively:

```nix
{
  home.packages = [ pkgs.rea ];
  home.file.".agents/skills/reverse-engineer-anything".source =
    "${pkgs.rea.skills}/share/agent-skills/reverse-engineer-anything";
}
```

Configure an MCP client with command `${pkgs.rea}/bin/rea` and argument `mcp`.
In Codex's TOML configuration the equivalent uses the resolved store path:

```toml
[mcp_servers.rea]
command = "/nix/store/<resolved-rea-output>/bin/rea"
args = ["mcp"]
```

Installing either output does not register a server or modify agent
configuration. The skill output supplies instructions; use the runtime package
for analysis. `rea setup --client codex --dry-run --json` previews upstream's
managed setup. Keep declarative client configuration in its owning configuration
module.

## Optional tools

Static JavaScript, managed-code, and package inspection work without a native
analysis engine. Native decompilation and other workflows use caller-selected
tools such as Ghidra, Hopper, IDA, a browser, Android tools, or firmware tools.
The package does not install every optional provider. Upstream's
[target requirements](https://github.com/morluto/rea#what-you-can-analyze)
describe the supported platform and version profiles for these tools.

The optional Frida 17.23.2 provider is not included in the installed runtime.
Its package supplies types during compilation, then only `frida` is removed
after compilation and domain tests. REA reports the Frida capability as
unavailable; other providers and the native PTY remain usable. Packaging Frida's
native component requires a separate review. Lifecycle scripts stay disabled and
optional dependencies are not globally omitted.

## Updates and checks

`source.nix` pins the release commit, recursive source hash, npm dependency
cache, matching PTY fork source and locked Node-API headers. Node and Brotli
come from the caller's Nixpkgs; the updater no longer writes private runtime or
Brotli source pins. The native `update.nix` command supports `--check` for a
no-write preview and `--version` for an explicit stable release.
`python3 update.py --help` also works without network access. Use the native
updater to provide Python's `sigstore` dependency along with `nix`, `git`, and
`prefetch-npm-deps`. It uses `GH_TOKEN` or `GITHUB_TOKEN` when provided for
GitHub API requests. The updater requires agreement between the npm release and
public GitHub release commit, keeps upstream lockfiles, and prepares all hashes
before publishing one source file with rollback on ordinary write failures. A
present mismatching npm `gitHead` is rejected. When `gitHead` is absent, the
updater requires a Sigstore verified SLSA provenance statement: its certificate
must identify the reviewed GitHub Actions release workflow, repository, issuer,
and release commit, and its authenticated payload must bind that source commit
to the exact npm name, version, and SHA512 integrity digest. Missing,
conflicting, or unverified provenance stops the update.

It verifies the local Darwin patch and stops for changed licensing, command
names, EVM provenance, optional runtime dependencies other than the exact
reviewed Frida pin, incompatible or unfamiliar Node engine ranges, or ambiguous
native header versions. A changed Node security minimum requires reviewing
`package.nix` and the updater's `NODE_VERSION` engine-compatibility baseline
together. The Brotli minimum belongs to `package.nix`; neither minimum introduces
a separate source pin.

Upstream's npm self-update command does not manage Nix installations. Refresh
these pins and rebuild the consuming configuration instead.

The native build runs upstream domain tests and validates generated skill
metadata. Cross builds skip executable checks. The former package-owned CLI,
MCP, PTY, setup-preview and memory install checks are retired; no
`scripts/check-install.mts` command is supplied. Optional engines, process
visibility and interactive GUI behavior require their own upstream verification
profiles and manual native acceptance. A package build does not establish those
runtime capabilities.

The native addon is also exposed as `rea.nativeAddon` for focused cross-build
coverage without compiling the entire target Node runtime. Native ARM executable
checks need an ARM worker. See the
[packaging research](../../../../docs/rea-packaging-research.md).
