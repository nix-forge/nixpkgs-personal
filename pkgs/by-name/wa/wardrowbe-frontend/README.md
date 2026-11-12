# Wardrowbe frontend

This package builds Wardrowbe 1.12.0's Next.js frontend from a pinned source
release. Its npm dependency graph is hashed and its Inter font comes from the
caller's nixpkgs `inter` package. The build does not fetch resources during
ordinary build phases. The output includes the font's OFL license notice. The resulting standalone
server is available as `wardrowbe-frontend`.

The package adds browser OpenAI account setup and saved model selection to Settings.
Focused React tests run before the Next.js build, including asynchronous preference
loading, device-code controls and unavailable saved models. Authentication still
requires the paired backend and optional Codex adapter at runtime.

The package patches the OIDC token authentication method for the paired
Wardrowbe backend. Review that patch, the npm dependency hash, and the runtime
API contract together when updating the source tag. The install check verifies
the standalone server, build ID, and translation resources; it does not test
browser login or a deployed backend.
The package-local `update.py` and `passthru.updateScript` integrate with the
repository's weekly update PR workflow. They refresh both package manifests
from one immutable release commit and regenerate the npm cache hash. See the
[paired update instructions](../wardrowbe-backend/README.md#automated-updates)
for preview commands, compatibility gates and deployment limits.

## Garment review and purchase planning

The [planning patch](planning.patch) adds confirmed garment reviews and history,
explicit availability, repair and replacement decisions, personalized coverage
requirements, and exact product comparisons. Basic reports use recorded facts
and declared needs without AI. Optional drafts use the owner's text observations
and selected provider; they remain separate from confirmed reviews.

The extension owns an independent migration ledger in the same database.
`wardrowbe-migrate` runs upstream migrations and then the planning migrations.
This avoids changing the upstream migration graph when automatic updates bring
a new release. Backend install checks exercise the API against disposable
PostgreSQL; frontend interactive tests run before the production build.

The updater validates the explicit patch list in recipe order, applying each
patch to a disposable writable copy. Conflicts stop the update before either
manifest changes. Release builds validate migrations and application behavior.

## Complete outfit browsing

The outfit list uses explicit, URL-backed pagination with Previous, Next and
page-jump controls. Page changes preserve the last successful results while
loading or retrying a failed request. Filter and search changes reset the page.
Cards display every garment with uncropped original images and thumbnail
fallbacks. Tests cover all pages, delayed and failed requests, filter resets,
return navigation, image fallback and selection. The paired backend orders tied
creation timestamps by outfit ID so page boundaries cannot repeat or omit a
record in an unchanged wardrobe.
