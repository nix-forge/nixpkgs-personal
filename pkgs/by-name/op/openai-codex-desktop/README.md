# openai-codex-desktop

Build the package on a platform listed in `package.nix`:

```sh
nix build .#openai-codex-desktop
```

This directory can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`. Dependencies come from upstream
Nixpkgs; the package does not require another personal package.

`package.nix` owns source selection, shared metadata, and platform dispatch.
`linux.nix` supplies Linux dependencies, ELF patching, and native launchers.
`darwin.nix` installs the signed application bundle without modifying it.
Keep all three files together when copying the package directory.

## Updates

Run `python3 pkgs/by-name/op/openai-codex-desktop/update.py --dry-run` from the repository root
to preview a source update. The updater also works from a copied package
directory and locates its metadata relative to itself.

The package expression records platform support, licensing, and build checks.
Repository CI evaluates every supported platform and builds affected packages
on a matching runner. GUI interaction requires a separate native smoke test.

## Linux command sandbox

The Linux package adds bubblewrap to the fallback PATH of both the desktop
launcher and the bundled Codex CLI. Direct CLI launches and security-scan
workers therefore receive it without a user-profile installation. Codex's
`codex-resources/bwrap` location is reserved for its upstream hash-pinned binary;
putting Nixpkgs' patched bubblewrap there fails integrity verification. The
signed macOS application is unchanged.

Bubblewrap and desktop integration helpers are package runtime dependencies.
Optional task tools are not. Add them explicitly without replacing an earlier
command on the user's PATH:

```nix
pkgs.openai-codex-desktop.override {
  extraPackages = [ pkgs.jq pkgs.ripgrep ];
}
```

This hook applies to Linux. It does not modify the signed macOS bundle.

Run the native sandbox probe outside a Nix build sandbox:

```sh
python3 pkgs/by-name/op/openai-codex-desktop/check-sandbox.py /path/to/built/package
```

The probe creates disposable files in the user's home, allows a workspace
write, rejects a write outside that workspace, and checks read-only execution.
It clears the child environment and supplies only coreutils on PATH, so a
user-installed bubblewrap cannot hide a missing package dependency. It needs
Linux user namespaces and does not start the GUI or contact a model.

Managed scan workers require a restricted permission profile. Select
`default_permissions = ":workspace"` in Codex's writable `config.toml` and
remove legacy `sandbox_mode` settings, which override permission profiles.
Existing tasks may retain their prior profile until resumed with updated
permissions. Keep this file writable for the app's native settings and plugin
management. See the [permission documentation](https://learn.chatgpt.com/docs/permissions).

## Downloaded Linux runtimes

The application itself uses `autoPatchelfHook` and does not require nix-ld.
Later Node, Python, and native-tool downloads cannot be patched at package
build time. Those downloads still need host compatibility such as nix-ld on
NixOS. Installing a Nix-native Node on PATH does not replace an absolute path
to the application's downloaded Node.

The launcher deliberately stays in the native host environment. A full
`buildFHSEnv` wrapper would preserve access to Nix packages but change default
filesystem and compiler settings. Even a smaller bubblewrap loader wrapper
sets `no_new_privs`, preventing privileged subprocesses from elevating. That
is unsuitable as a transparent default for agents using a configured host.
Codex still applies bubblewrap to individual sandboxed commands as intended.
See [Nix's executable compatibility guidance](https://nix.dev/guides/faq#how-to-run-non-nix-executables)
and [bubblewrap's implementation](https://github.com/containers/bubblewrap/blob/main/bubblewrap.c).

The package does not replace vendor runtime versions, set a global library
path, or require disabling either application sandbox. On Linux, the launcher
checks the versioned browser-plugin cache before starting the application. If
the matching service is absent or incomplete, it atomically copies the browser
plugin shipped with that application version into Codex's writable cache. It
does not remove caches for earlier versions. This avoids a desktop update
leaving the trusted browser worker configured for a file that was never
materialized.

Fully removing nix-ld for downloaded runtimes needs a separately maintained,
Nix-packaged runtime or a supported upstream runtime-execution hook.
