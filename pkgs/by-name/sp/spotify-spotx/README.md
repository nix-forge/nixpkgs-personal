# spotify-spotx

This recipe downloads Spotify and applies SpotX-Bash modifications locally.
It is an independent package variant, without Spotify endorsement.

## Upstream terms

Spotify's [User Guidelines](https://www.spotify.com/us/legal/user-guidelines/)
restrict client modification, subject to applicable-law exceptions, and prohibit
ad blocking and creating or distributing tools designed to block advertisements.
Its [Terms of Use](https://www.spotify.com/us/legal/end-user-agreement/) also
restrict redistribution of the application. Review the terms applicable to your
use; a Premium subscription or `allowUnfree` setting does not itself grant
permission to modify the client.

Publishing this recipe is distinct from distributing Spotify binaries. That
distinction does not resolve the applicability or enforceability of the terms
for a particular activity. Repository CI evaluates this package but excludes its
build from hosted runners. The repository does not publish its patched output.
For an unmodified client, use Spotify's official distribution or upstream
Nixpkgs' `spotify` package where supported, subject to Spotify's terms.

## Build

Build the package on a platform listed in `package.nix`:

```sh
nix build .#spotify-spotx
```

This directory can be copied and instantiated with upstream Nixpkgs using
`pkgs.callPackage ./package.nix { }`. Dependencies come from upstream
Nixpkgs; the package does not require another personal package.

## Updates

Run `python3 pkgs/by-name/sp/spotify-spotx/update.py --dry-run` from the repository root
to preview a source update. The updater also works from a copied package
directory and locates its metadata relative to itself.

The package expression records platform support, licensing, and build checks.
Repository CI evaluates every supported platform; this package has an explicit
hosted-build exclusion. GUI interaction requires a separate native smoke test.
