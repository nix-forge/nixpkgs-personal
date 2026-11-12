# Wardrowbe packages

`wardrowbe-backend` and `wardrowbe-frontend` package the [Wardrowbe v1.12.0 release](https://github.com/Anyesh/wardrowbe/releases/tag/wardrowbe-v1.12.0) as native Nix applications. Both derive from the same pinned source tag. The backend installs API, AI worker, image worker and Alembic migration commands. The frontend installs the Next.js standalone server and its static files.

The backend follows the caller's default `python3` and reuses nixpkgs' FastAPI,
rembg and Python ONNX Runtime packages without disabling their upstream tests.
It includes Uvicorn's standard extras and SQLAlchemy's asyncio extra, including
Greenlet. If nixpkgs has no ARQ package, local ARQ and compatible Redis Python
source recipes supply the job queue. [ARQ requires Redis below version 6](https://github.com/python-arq/arq/blob/v0.28.0/pyproject.toml);
the current nixpkgs client is version 8. Both fallback recipes retire automatically
when the incoming Python package set provides ARQ. Their import checks remain
enabled. Wardrowbe 1.12 validates Unix socket URLs and supplies ARQ's socket path
natively, so the former Unix socket compatibility patch has been retired.

The frontend takes Inter's variable TTF from nixpkgs' `inter` package and installs
its OFL notice. Upstream `next/font/google` fetches the font during the build;
the local asset keeps Nix builds offline and avoids a browser request to Google.
`npmDepsHash` pins the JavaScript dependency tree. See the
[dependency packaging research](../../../../docs/wardrowbe-packaging-research.md)
for the reuse policy and official sources.

The [OIDC patch](../wardrowbe-frontend/oidc-token-auth-method.patch) lets the caller select HTTP Basic or form body client authentication at runtime. The default remains NextAuth's Basic method. Providers such as Pocket ID that require form body credentials can select `client_secret_post` without a provider-specific package. It also keeps the ID token in NextAuth's encrypted server session cookie so logout can send an `id_token_hint` to a configured provider end-session endpoint.

Build both on Linux with `nix build --no-link .#wardrowbe-backend .#wardrowbe-frontend`. The backend install check imports every entry point and the Unix socket parser,
and checks rembg and ONNX CPU provider availability on x86_64 Linux. Upstream
ONNX cannot import in the aarch64 Linux sandbox without CPU information, so that
ML import check follows the same platform exception as nixpkgs. A local Valkey
instance also verifies ARQ can enqueue and execute a job through a Unix socket.
ARM runtime
inference still requires verification on an ARM host. The install check also authenticates the browser OpenAI management routes,
checks private socket forwarding, and sends fixture text and image requests through
the selected user models. It verifies upstream runtime requirement constraints against installed libraries,
so unavailable or incompatible new dependencies fail the release build. The frontend install check verifies the standalone server, build ID and translation messages. Neither package embeds application secrets or host policy.

## Automated updates

The existing weekly package update workflow discovers both `update.py` entry
points. Either script updates both package manifests together in this checkout;
the second invocation sees the same pins and exits without rewriting them.
Each package also exposes a Nixpkgs-compatible `passthru.updateScript` with its
required tools. Copied package directories can update independently.

The updater selects stable `wardrowbe-vX.Y.Z` releases, resolves the exact Git
commit, refreshes its source hash and npm lockfile cache with `prefetch-npm-deps`,
and checks source layout and patch applicability. It also selects stable ARQ
and a non-yanked Redis source release satisfying ARQ's declared dependency range.
New fallback dependencies or Python requirements that the recipes cannot supply
stop the proposal for review. No npm install or upstream lifecycle scripts run
in the update job. Downloads and validation finish before either manifest changes;
failed writes roll back the pair. Application downgrades are rejected.

The weekly workflow proposes changes through a PR and dispatches separate,
read-only builds and checks. This does not automatically migrate a running
service or exercise browser login. Database migrations and deployments follow
the consuming homelab's release process.

To preview or run a refresh from the package repository:

```sh
nix develop --command python pkgs/by-name/wa/wardrowbe-frontend/update.py --paired --dry-run
nix develop --command python scripts/update_packages.py --package wardrowbe-frontend
```

Direct package updaters refresh their own folder by default, so upstream can
run them independently or in parallel. Use `--paired` to refresh both folders;
the repository dispatcher supplies it automatically.

Use `--refresh` to regenerate current hashes and `--version wardrowbe-vX.Y.Z`
to select a specific stable release. Ordinary scheduled runs need neither flag.

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

## Stable outfit pagination

Upstream 1.11 sorts filtered outfit lists by descending creation time and then
ascending outfit ID. Its unique tie-breaker replaces the local pagination patch.
The unique tie-breaker prevents duplicate and omitted records when timestamps
match. The install check exercises chronological order, unique page boundaries
and owner isolation against its disposable PostgreSQL database. No schema
change or deployment migration is required for this correction.

The 1.11 release requires SQLAlchemy 2.1. When the incoming Python set is older,
the package uses a scoped stable source pin while preserving Nixpkgs' compiler,
dependencies and tests. The paired updater refreshes that pin and the runtime
requirement check verifies the installed version. The override retires itself
when Nixpkgs provides the pinned version or newer.

The scoped compiler drops only Nixpkgs' Cython 3.3.0 backport of
[PR 7970](https://github.com/cython/cython/pull/7970) when selecting 3.3.1 or
newer. That release already guards unknown annotations and includes the
[original pure-Python/.pxd regression](https://github.com/cython/cython/blob/3.3.1/tests/run/pure_pxd.srctree).
Its native install check compiles and runs that upstream compiler-source
fixture. SQLAlchemy then builds with the installed compiler. Other inherited
compiler patches and SQLAlchemy's upstream tests remain enabled.

Wardrowbe 1.12 also requires certifi 2026.10.19 or newer. A scoped source pin
supplies the newer Mozilla bundle until the incoming Python set catches up.
The application environment replaces the flattened certificate module and its
distribution metadata once, so HTTP clients share the selected bundle while
unchanged dependency builds remain reusable. The source package preserves the
explicit host CA-file support and upstream tests;
it retains the release bundle instead of replacing it with an older NSS bundle.
The runtime check verifies that the removed emSign ECC Root CA-G3 is absent
and a retained trust root remains. See the
[certifi advisory](https://github.com/certifi/python-certifi/security/advisories/GHSA-6q48-6c7w-9gw2).
The paired updater refreshes this source pin with its other Python dependencies.
