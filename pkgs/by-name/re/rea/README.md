# REA

REA provides the `rea` and `rea-agents` commands and a stdio MCP server. This
recipe builds the public stable TypeScript release and its matching native PTY
addon from source with the upstream npm lockfile and Node 24.22.1. This package
pins the actual Node source for both build tools and target runtime while
keeping the rest of the collection's Nixpkgs input unchanged. Brotli 1.2.1 is
scoped to this runtime because Node exposes its new decoder error. Linux Node
builds use Clang to keep eight compiler workers within the reviewed working set.
On Darwin it also compiles the process-ownership and native UI Swift helpers. A
local patch selects those packaged helpers while preserving upstream's process
validation and the source checkout's runtime compilation fallback.

Darwin's scoped Node runtime retains the resident-size reporting contract of
Node 24's bundled libuv. The compatibility adapter covers Node's memory-usage
APIs and diagnostic reports; shared libuv 1.53 and its physical-footprint
regression tests remain unchanged. The original worker-memory assertion and
threshold remain in place. The Node check runner uses its allocated compiler
count. Its blocked-address fixture uses a permitted loopback address for the
successful reuse case, keeping both the block rejection and peer-address
assertions. No additional tests are excluded. On hosts with an application
firewall, allow the exact build executable while running the native network
checks, then remove that temporary exception. The original inspector and scoped
IPv6 echo assertions remain unchanged.

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
cache, matching PTY fork source, locked Node-API headers, and the scoped Node
source. The native `update.nix` command supports `--check` for a no-write
preview and `--version` for an explicit stable release.
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
native header versions. A changed Node security minimum requires reviewing and
updating the scoped Node source pin in both `source.nix` and `update.py`. Review
and retain the scoped Brotli version and hash in both files as part of that
runtime update.

Upstream's npm self-update command does not manage Nix installations. Refresh
these pins and rebuild the consuming configuration instead.

The build runs upstream domain tests and validates generated skill metadata.
Install checks exercise both CLI names, static JavaScript analysis, a real PTY,
the deliberately unavailable Frida provider, MCP initialization and tool
enumeration, skill references, and setup preview in an isolated temporary home.
Cross builds skip executable checks. Optional engines and interactive GUI
behavior require their own upstream verification profiles. Darwin's Nix sandbox
restricts the process visibility needed for static analysis workers, so its
install check omits that operation. Run the complete installed check outside the
sandbox on Darwin:

```sh
<rea-node-output>/bin/node scripts/check-install.mts <rea-output> <skills-output> <version> /bin/bash
```

Use the package's pinned Node runtime for that command.

The native addon is also exposed as `rea.nativeAddon` for focused cross-build
coverage without compiling the entire target Node runtime. Native ARM executable
checks need an ARM worker. See the
[packaging research](../../../../docs/rea-packaging-research.md).
