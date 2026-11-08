# Scrypted HomeKit release source

Reviewed: 2026-10-01. Scope: `@scrypted/homekit` 1.2.65 through 1.2.69 and
the public `koush/scrypted` repository at
[`6f4bea407311b26f558315f6a217fee26e192ec2`](https://github.com/koush/scrypted/commit/6f4bea407311b26f558315f6a217fee26e192ec2).

## Answer

The npm releases are ahead of the public HomeKit source. The public repository
contains the plugin, but its currently published refs do not identify the
source used for 1.2.69. The other two public branches of `koush/scrypted`
predate the September 2026 releases. The exact publishing workflow is unknown.
Publishing from local uncommitted changes or an unpublished Git history would
fit the evidence, but neither is proven.

Do not label a build from public `main` as 1.2.69. It would omit code and
behavior present in that release. A separate package could build the public Git
revision under an honest revision-based version after its dependencies and
HomeKit behavior have been tested. The existing 1.2.69 package must keep its
non-source provenance unless matching source becomes available.

## Findings and sources

- [npm's package registry](https://registry.npmjs.org/@scrypted%2Fhomekit)
  records 1.2.65 on 2025-04-03, then 1.2.66 and 1.2.67 on 2026-09-17 and
  1.2.69 on 2026-09-18. The [public HomeKit manifest](https://github.com/koush/scrypted/blob/6f4bea407311b26f558315f6a217fee26e192ec2/plugins/homekit/package.json)
  still declares 1.2.65. Public HomeKit code did change after 1.2.65, including
  a [HAP dependency update](https://github.com/koush/scrypted/commit/3e94bdeb9a505b4795dc2f271874fa4574ed219a)
  in June 2026. The stale version alone does not prove that all of the code is
  stale.
- Registry metadata gives Git heads for
  [1.2.65](https://registry.npmjs.org/@scrypted%2Fhomekit/1.2.65),
  [1.2.66](https://registry.npmjs.org/@scrypted%2Fhomekit/1.2.66),
  [1.2.67](https://registry.npmjs.org/@scrypted%2Fhomekit/1.2.67), and
  [1.2.69](https://registry.npmjs.org/@scrypted%2Fhomekit/1.2.69). The
  1.2.65 head,
  [`1c52297`](https://github.com/koush/scrypted/commit/1c52297e744d63464adc8e61ebdc8066a995b75a),
  is public, yet its
  [HomeKit manifest](https://github.com/koush/scrypted/blob/1c52297e744d63464adc8e61ebdc8066a995b75a/plugins/homekit/package.json)
  says 1.2.64. The npm `gitHead` therefore does not identify the exact published
  package tree. The plugin's `prepublishOnly` script runs `scrypted-changelog`
  and `scrypted-webpack`; [npm runs that script before packing a published
  package](https://docs.npmjs.com/cli/v11/using-npm/scripts#prepublishonly).
- The three later npm Git heads are `65fa6984142d3a452f5e45ec540fb2c9d4af1bc1`,
  `0222876174d5a4adfdffc04cbb1165986308e554`, and
  `f37f1bdbba8c3d3fb40c206dec648e66369129c8`. GitHub cannot resolve any
  of them in `koush/scrypted`. Its
  [public refs](https://api.github.com/repos/koush/scrypted/git/matching-refs/)
  contain three branches (`main`, `libav`, `unifi`) and tags, with no HomeKit
  release ref for these versions. The `libav` and `unifi`
  [branch heads](https://api.github.com/repos/koush/scrypted/branches?per_page=100)
  date to 2025 and 2024. GitHub's
  [commit search](https://github.com/search?q=f37f1bdbba8c3d3fb40c206dec648e66369129c8&type=commits)
  also found no public copy of the 1.2.69 head. This rules out the public refs
  checked on 2026-10-01, not an unpublished repository or deleted history.
- [`scryptedapp/scrypted`](https://github.com/scryptedapp/scrypted) is a public
  fork of `koush/scrypted`. Its sole
  [public branch](https://api.github.com/repos/scryptedapp/scrypted/branches?per_page=100)
  predates the 2026 releases and GitHub cannot resolve the three later npm
  heads there either.
- The [1.2.69 npm tarball](https://registry.npmjs.org/@scrypted/homekit/-/homekit-1.2.69.tgz)
  includes `dist/plugin.zip` with a JavaScript source map. It embeds the text
  of 47 HomeKit `src/` files. Comparing that text byte for byte with public
  `main` at `6f4bea4` gives 39 matches, five changed files, and three absent
  files: `camera-multitier-rtp.ts`, `camera-webrtc.ts`, and
  `camera-secure-video.ts`. The tarball's `CHANGELOG.md` names stream stutter
  fixes, HKSV3 aspect ratio cleanup, alternate codec support, and HomeKit WebRTC
  two-way audio. Those are material differences for a HomeKit deployment.
  A source map is evidence about the release, but it is not a pinned upstream
  source tree or a complete dependency lock.
- The 1.2.69
  [published manifest](https://registry.npmjs.org/@scrypted%2Fhomekit/1.2.69)
  points `@homebridge/hap-nodejs` at
  `../../homekit-scratchpad/HAP-NodeJS`. Public
  [`main` instead uses `^2.1.3`](https://github.com/koush/scrypted/blob/6f4bea407311b26f558315f6a217fee26e192ec2/plugins/homekit/package.json).
  The local scratchpad dependency is not in the public repository's
  [tracked tree](https://api.github.com/repos/koush/scrypted/git/trees/6f4bea407311b26f558315f6a217fee26e192ec2?recursive=1).

## Validation and limits

Read-only checks on 2026-10-01 used the npm registry, release tarball, GitHub
repository and ref APIs, and GitHub raw files. The source-map comparison covers
the plugin's 47 mapped `src/` files against the named public commit. It does
not reproduce the webpack build, validate every transitive dependency, or test
pairing and streaming on an Apple Home deployment. GitHub's public API cannot
tell whether the publisher used an unpublished branch, a separate private
repository, a dirty working tree, or later-deleted commits. No maintainer
statement explaining the publication gap was found.

## Implication for this repository

Keep the current [HomeKit package](../pkgs/by-name/sc/scrypted-plugin-homekit/package.nix)
at 1.2.69 with accurate non-source provenance. Revisit a source build when a
matching upstream revision and all local dependencies are published, or after
testing a separately versioned build of public source against the intended
Scrypted deployment.
