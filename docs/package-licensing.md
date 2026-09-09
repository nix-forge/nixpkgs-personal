# Recipe publication and package licensing

Reviewed 2026-09-08 against the pinned sources. This repository publishes Nix
recipes. Building, using, modifying, and distributing their outputs are separate
activities, with conditions that depend on the actual upstream grant.
An unfree classification is not a finding that publishing a recipe is illegal.
The [AUR FAQ](https://wiki.archlinux.org/title/Arch_User_Repository#What_kind_of_packages_are_permitted_on_the_AUR?)
and [Gentoo licensing guidance](https://devmanual.gentoo.org/general-concepts/licenses/index.html)
make similar distinctions. Package-manager acceptance is not legal clearance.

## Implemented packaging changes

- Noctalia installs notices for compiled fzy, Luau/Lua, Material Color Utilities,
  and Wuffs. Its metadata includes MIT and Apache-2.0. The existing Tabler font
  notice remains installed by upstream's asset installation.
- Bibata includes the full GPLv3 text, and Firefox Emoji includes the full
  Apache-2.0 text alongside their upstream notices. EmojiOne retains its pinned
  artwork terms and the matching Adobe MIT notice and credits.
- The OpenAI desktop compatibility patch records its modification in the
  Apache-licensed detect-libc file. Free skill renaming also records a notice.
  These support the output obligations in [Apache section 4](https://www.apache.org/licenses/LICENSE-2.0).
- Anthropic and OpenAI catalogs have reviewed per-skill inventories and explicit
  selection. License metadata reflects installed components. Restricted contents
  remain unchanged. See their package READMEs for defaults and supported uses.
- Apple emoji offers an unchanged download via `repairArtwork = false`, while
  retaining repaired behavior by default. The repaired output records its Noto
  additions and notices. [OFL condition 5](https://github.com/googlefonts/noto-emoji/blob/v2.051/fonts/LICENSE)
  concerns distribution; private repair alone is not a redistribution finding.
- Apple font packages preserve terms and explain their limited grants.
  `apple-fonts` records source evidence separately from hashes and technical
  compatibility. Unreviewed foundry rights remain visible instead of receiving
  invented permission declarations.
- The `vorssaint` recipe builds PersonalMonitor with independent branding and
  identifiers. Its updater cannot replace the package with upstream binaries.
  Ad-hoc signing does not satisfy upstream's privileged-helper identity, so that
  feature is explicitly unavailable with authentication kept closed.

## Hosted builds

CI evaluates all 39 recipes and their supported derivations. The affected-package
build selector reads [.github/ci-policy.json](../.github/ci-policy.json) before
running a package build. The selector stops before building if the policy is
missing or malformed, a reason is blank, or an exclusion names no package in the
repository. Packages supported only on another platform remain valid exclusions.
Every excluded target has a specific reason. Current
exclusions cover Apple fonts and emoji, Windows evaluation font extraction, and
Spotify modification. They are conservative project policy for unresolved hosted
activities, not legal conclusions about local use or recipe publication.

Ordinary proprietary application installation recipes are not excluded merely
because they are unfree. The Anthropic default contains reviewed examples; custom
restricted skill selections are outside the default CI build set. OpenAI's
default catalog remains tested as an integration-resource packaging workflow.
Neither workflow logs into or exercises the vendors' services.

The workflows set `cache: 'false'`, and the pinned setup action only enables its
store-cache step when that input is true. There is no package-output publishing
step. Preserve this policy when changing CI. `allowSubstitutes = false` and
`preferLocalBuild = true` control fetching and scheduling, not upload permission.
Setting `meta.hydraPlatforms` alone would not govern this GitHub build selector.

## Further distribution

Before adding a public binary cache or release artifacts, review the actual
outputs and their sources, license copies, notices, modifications, and branding.
Keep a usable corresponding-source route where the applicable license requires
one. A recipe URL by itself does not establish every binary-distribution duty.
Those duties are conditional on distribution; they are not automatically
triggered by users privately building from this repository.

License inventories do not replace review of vendored code, artwork ancestry,
service agreements, or changed upstream terms. The earlier unresolved icon
ancestry and full vendor-bundle notice inventories remain evidence limitations.

## Remaining permission reviews

The following questions remain open after the packaging fixes. Correct metadata,
successful builds, and NUR acceptance do not answer them:

- [Apple's Font8 collection](../pkgs/by-name/ap/apple-fonts/README.md) needs
  foundry-specific permission evidence. Developer-font grants are scoped to
  particular design uses, not a general font-use permission.
- [Windows evaluation fonts](../pkgs/by-name/tt/ttf-ms-win11-auto/README.md) need
  a grant covering the intended standalone extraction and use.
- [Apple emoji](../pkgs/by-name/ap/apple-color-emoji/README.md) retains unresolved
  Apple artwork permissions. Installing an unchanged variant avoids the repair
  operation but does not establish rights to distribute the font.
- [Spotify modifications](../pkgs/by-name/sp/spotify-spotx/README.md) require
  review of the applicable modification and ad-blocking terms.
- Restricted [Anthropic](../pkgs/by-name/an/anthropic-skills/README.md) and
  [OpenAI](../pkgs/by-name/op/openai-skills/README.md) skill selections require
  review of their specific grants and intended use. Anthropic's pinned
  `doc-coauthoring` has no explicit license. Free selections still fetch the full
  upstream source archives.
- Third-party icon ancestry and complete vendor-bundle notice inventories need
  further evidence beyond the notices already preserved by these recipes.

Resolve each question with the applicable upstream grant or a qualified review
of the specific activity before describing that activity as permitted. An end
user's restriction is not, by itself, a finding of liability for the recipe
publisher. These review gaps do not establish that recipe publication is unlawful.

The root [MIT license](../LICENSE) includes warranty and liability disclaimers
for the repository's software. It does not grant third-party rights or guarantee
that a claim cannot be brought. This audit records packaging evidence and its
limits; it is not a legal opinion or a promise of immunity for maintainers or users.

## Verification

All 39 recipes evaluate on their declared supported systems, and all 27 Linux
x64 outputs build or reuse successfully. Selection variants, content-preservation
checks, package independence, policy tests, CI selection, linting, formatting,
and repository secret scanning pass. See the [audit](package-audit.md#validation-and-limits)
for details. [NUR preparation](nur-submission.md#verified-checkout) subsequently
verified all 34 native macOS outputs and PersonalMonitor's signature. Linux ARM64
builds and GUI behavior remain untested.
