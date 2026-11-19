# Native and cross Linux builds

Ordinary flake outputs are native: `packages.aarch64-linux` builds on ARM Linux,
and `packages.x86_64-linux` builds on x86-64 Linux. Matching architectures require
neither cross-compilation nor CPU emulation. Darwin outputs also remain native.

Every project repository exports `lib.packagesFor { buildSystem; hostSystem; }`.
When the platforms match it returns native packages. For different Linux
architectures it imports Nixpkgs with a native `localSystem` and a target
`crossSystem`. Both x86-64 to ARM and ARM to x86-64 are supported by the policy.
Repositories that only export documentation build those architecture-independent
artifacts natively on the selected worker.

Use the workstation's automatic selector:

```sh
just linux-build aarch64-linux wordcraft pkgs
just linux-build x86_64-linux default nix-seal
just arm-build cadcraft
```

The platform factory is available in the root project, package repository,
configuration framework, nix-seal and nix-homelab. NixOS and Home Manager targets
remain native by default; the framework accepts an explicit host `buildSystem`
for cross builds. The root also exports `lib.nixosConfigurationFor` to extend a
configuration with a selected build platform. Pi deployment chooses the desktop's
architecture and only cross-compiles when it differs from the Pi.

Native CI outputs run on matching native workers. QEMU/binfmt is separate from
cross-compilation and is only needed when a build executes foreign-architecture
programs. The desktop registers the opposite CPU architecture, not its own, and
its recorded Nix policy does not advertise an emulated compiler worker. Changes
to that host registration policy require the next NixOS activation.

There are no per-package compiler whitelists or pilot command families. Existing
checks remain callable explicitly. Upstream packages without cross support need
recipe fixes, and externally supplied derivations retain their owner's platform
choices. No new validation or build jobs accompanied this policy correction.
See [Nix cross-compilation concepts](https://nix.dev/tutorials/cross-compilation.html).
