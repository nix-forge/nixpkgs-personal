# AudioMuse-AI packaging and maintenance research

Reviewed: 2026-09-15. Scope: `audiomuse-ai` in this repository, at AudioMuse-AI 3.6.0 and the pinned Nixpkgs revision `8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe` from 2026-09-10.

## Answer

Keep AudioMuse-AI as `python313Packages.buildPythonApplication`, with `format = "other"`, a manual install phase, and explicit wrappers. It is an application, not a reusable Python library, and upstream 3.6.0 has `requirements/` files but no `pyproject.toml`, `setup.py`, or wheel metadata. `format = "other"` is the documented builder mode for a derivation that supplies its own build and install phases. The builder still provides Python-specific dependency checks and application semantics. [Nixpkgs Python builder source](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/development/interpreters/python/mk-python-derivation.nix#L91-L110) [Nixpkgs Python packaging manual](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/doc/languages-frameworks/python.section.md#buildpythonapplication-function) [AudioMuse-AI 3.6.0 source tree](https://github.com/NeptuneHub/AudioMuse-AI/tree/31239fa986afb91a15e039e1a9a64ed5a2d6fa12)

Use one updater-owned source manifest for all immutable AudioMuse release inputs. The updater may refresh the API-sensitive Python sources when a new AudioMuse release changes their exact requirements, because it resolves each dependency tag, records its full commit and NAR hash, and lets the lightweight Python closure check validate the resulting environment. Model-release assets and packages supplied by Nixpkgs remain separate review boundaries. A changed `tokenizers`, ONNX Runtime, Python, or model-release requirement stops with a report rather than silently outrunning the selected Nixpkgs compatibility contract.

For Transformers, keep a narrowly scoped local compatibility patch, applied to the authoritative `_deps` list and followed by upstream's dependency-table generator. Pin the Transformers source independently, record why it diverges from Nixpkgs, and test the generated runtime table and installed package versions. `pythonRelaxDeps` alone cannot solve this case because it edits wheel `METADATA` after the build, while Transformers imports its generated table and checks it at import time.

## Facts and sources

### Upstream release and source shape

Facts retrieved 2026-09-15:

- AudioMuse-AI release `v3.6.0` was published on 2026-09-11 and its tag resolves to commit `31239fa986afb91a15e039e1a9a64ed5a2d6fa12`. The release publishes native package artifacts for Linux, macOS, and Windows. The Nix expression instead fetches source. [Release metadata](https://github.com/NeptuneHub/AudioMuse-AI/releases/tag/v3.6.0) [tagged commit](https://github.com/NeptuneHub/AudioMuse-AI/commit/31239fa986afb91a15e039e1a9a64ed5a2d6fa12)
- The tagged tree has requirement files including [`requirements/common.txt`](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/requirements/common.txt), [`requirements/cpu.txt`](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/requirements/cpu.txt), and [`requirements/linux.txt`](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/requirements/linux.txt). It has no `pyproject.toml` or `setup.py`. This is an observation from the complete tagged tree, not an assertion about later releases. [Tagged tree](https://github.com/NeptuneHub/AudioMuse-AI/tree/31239fa986afb91a15e039e1a9a64ed5a2d6fa12)
- `requirements/common.txt` exactly pins `google-genai==1.57.0`, `transformers==4.57.6`, `huggingface-hub==0.36.2`, `mistralai==1.12.4`, and `tokenizers==0.22.2`; `requirements/linux.txt` adds `onnxruntime==1.28.0`. [Common requirements](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/requirements/common.txt) [Linux requirements](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/requirements/linux.txt)
- Upstream has an alignment test that requires duplicated exact pins in its test requirements to agree with `requirements/common.txt`. That demonstrates that its requirement versions are an intentional release contract, although it does not establish Nixpkgs compatibility. [Upstream alignment test](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/test/unit/test_requirements_alignment.py)
- This package currently obtains the application version, tag, fixed-output hash, model release names, and API-sensitive Python source pins from [`source.nix`](../pkgs/by-name/au/audiomuse-ai/source.nix). Its application recipe builds an explicitly composed `python313.withPackages` environment and wraps upstream role launchers. [Current package recipe](../pkgs/by-name/au/audiomuse-ai/package.nix) [Current source metadata](../pkgs/by-name/au/audiomuse-ai/source.nix) [Model recipe](../pkgs/by-name/au/audiomuse-ai/models.nix)

### Nixpkgs builder and dependency rules

Facts from the Nixpkgs Python manual and the pinned builder source:

- Nixpkgs says Python applications live outside the Python package set and use `buildPythonApplication`; `buildPythonApplication` differs from `buildPythonPackage` chiefly because applications expose executables rather than importable modules and omit the interpreter-version name prefix. [Manual: application builder](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/doc/languages-frameworks/python.section.md#buildpythonapplication-function) [Manual: contributing guidance](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/doc/languages-frameworks/python.section.md#how-to-contribute-a-python-package-to-nixpkgs)
- The builder recognizes `format = "other"` as the mode in which the package supplies its own build and install phases. The pinned source automatically adds `pythonRelaxDepsHook` only when `pythonRelaxDeps` or `pythonRemoveDeps` is set. [Builder source](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/development/interpreters/python/mk-python-derivation.nix#L91-L110) [Hook selection](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/development/interpreters/python/mk-python-derivation.nix#L182-L217)
- `dependencies` are Python runtime dependencies, `build-system` contains Python build requirements, `buildInputs` contains non-Python build inputs, and `nativeCheckInputs` contains test-only inputs. A package should use a single interpreter's unversioned Python package attributes to avoid colliding modules on `PYTHONPATH`. [Nixpkgs dependency guidance](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/doc/languages-frameworks/python.section.md#handling-dependencies) [Single-version restriction](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/doc/languages-frameworks/python.section.md#contributing-guidelines)
- `pythonRelaxDeps` removes version constraints from wheel `METADATA` in a post-build hook. Nixpkgs recommends relaxing rather than removing dependencies, and says it does not affect build requirements. [Manual: `pythonRelaxDepsHook`](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/doc/languages-frameworks/python.section.md#using-pythonrelaxdepshook) [Hook source](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/development/interpreters/python/hooks/python-relax-deps-hook.sh)
- `pythonImportsCheck` imports nominated modules in the install check. Nixpkgs still recommends it as a smoke test even when a test suite runs. [Manual: import checks](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/doc/languages-frameworks/python.section.md#using-pythonimportscheck) [Import-hook source](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/development/interpreters/python/hooks/python-imports-check-hook.sh)

### Nixpkgs update model

Facts from Nixpkgs:

- `passthru.updateScript` tells `nixpkgs-update` the explicit update procedure. Nixpkgs supports an executable, an argument list, or an attribute set with a command and optional capabilities. [Automatic-update documentation](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/README.md#automatic-package-updates)
- `nix-update-script` is appropriate for ordinary sources. `gitUpdater` updates source attributes from Git tags. Update scripts must not assume their current directory, are normally run from the repository root, and may run in parallel. [General updaters](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/README.md#general-purpose-update-scripts) [Invocation rules](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/README.md#how-are-update-scripts-executed)
- Nixpkgs requires a full commit hash when a GitHub fetcher uses a commit revision. [Nixpkgs contribution source guidance](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/README.md#L620-L625)

### Why the current Transformers patch is fragile

Facts:

- Before this change, the local override replaced Transformers with upstream `v4.57.6`, patched only `src/transformers/dependency_versions_table.py`, and relaxed the wheel's `tokenizers` dependency. The implementation now patches the authoritative declaration and regenerates that table. [Transformers recipe](../pkgs/by-name/au/audiomuse-ai/transformers.nix)
- Transformers `v4.57.6` declares `tokenizers>=0.22.0,<=0.23.0` in `_deps` in [`setup.py`](https://github.com/huggingface/transformers/blob/v4.57.6/setup.py#L91-L190). That same source labels [`dependency_versions_table.py`](https://github.com/huggingface/transformers/blob/v4.57.6/src/transformers/dependency_versions_table.py) generated and directs maintainers to edit `_deps` and run `make deps_table_update`.
- At import time, Transformers imports the generated table and calls `require_version_core` for `tokenizers` when it is installed. [Runtime dependency check](https://github.com/huggingface/transformers/blob/v4.57.6/src/transformers/dependency_versions_check.py#L31-L64)

Inference: a patch that matches one generated table string is intentionally tied to a single Transformers release. A generic application updater that changes the Transformer source while retaining that patch has no reliable reason to succeed. More subtly, relaxing the wheel metadata cannot change the generated table used by the import-time check. The current failure mode is therefore expected, not a reason to weaken `--replace-fail`.

## Recommended maintenance model

### Separate source ownership

Inference: retain `source.nix` as the machine-owned manifest, but make the ownership visible in its shape. The manifest now has separate records for:

- `app`: `version`, release tag for links, resolved 40-character `rev`, and NAR hash.
- `models`: the AudioMuse model release and the DCLAP/SAE release names and hashes. These are binary model inputs, not implied by an application tag.
- `python`: the exact versions, release tags, resolved revisions, and NAR hashes for the API-sensitive `google-genai`, `huggingface-hub`, `mistralai`, and `transformers` sources. Transformers also records both its upstream tokenizers requirement and the reviewed local requirement used by the generated runtime table.
- `compatibility`: the AudioMuse-required `tokenizers` and ONNX Runtime pins supplied by Nixpkgs, with the source requirement file that establishes each value.

Use the resolved commit for `fetchFromGitHub.rev`; derive changelog and release URLs from `version` or a dedicated tag field, not the commit. That avoids using a tag where the fetcher contract needs an immutable revision. Keep model asset hashes in `models.nix` because they are an inventory, but put the release selectors in the manifest.

Do not put the Nixpkgs revision in this file. It already belongs to the flake lock. Its moving package set is a compatibility input to review, not an AudioMuse upstream release source.

### Update script

Inference: add a local `update.py`, exposed as an editable-root command such as:

```nix
passthru.updateScript = [
  "python3"
  "pkgs/by-name/au/audiomuse-ai/update.py"
];
```

This matches the repository's existing updater convention. The script should locate its own directory, provide `--help` without network access, support `--dry-run`, write atomically, and only edit `source.nix`. Its normal operation should:

1. Query the official AudioMuse-AI releases endpoint, choose the latest non-draft, non-prerelease tag matching the accepted stable version pattern, and resolve it to a 40-character commit.
2. Fetch and parse the candidate's `requirements/common.txt`, `requirements/linux.txt`, and the repository tree. Refuse an unrecognised source layout or missing files.
3. Compare the candidate's Nixpkgs-backed pins with `compatibility`: Tokenizers and ONNX Runtime. If either differs, report the old and new values and exit without writing. Resolve changed API-sensitive Python requirements to their tagged source commits and NAR hashes. A changed Transformers release must also expose the expected setup metadata and remain compatible with the selected Nixpkgs Tokenizers version.
4. Prefetch the application source, then update the `app` and API-sensitive `python` records only after all validation passes. The write is atomic and model selectors remain untouched.

The implemented updater updates the application and API-sensitive Python source metadata together. Model refreshes remain separate because their large binary artifacts are not implied by the application tag. `--refresh` explicitly revalidates the application and API-sensitive Python hashes. A changed Nixpkgs-backed requirement remains review-gated.

`nix-update-script` is too broad for the default here: it can update the Git source, but it cannot establish that the new AudioMuse tag keeps the separately fetched models and the custom runtime override compatible. It remains reasonable for a future standalone Transformers derivation if that derivation stops needing the special patch.

### Dependencies and overrides

Inference: retain upstream Nixpkgs packages where their version passes the selected release's import and targeted runtime checks. Do not source-pin all 40-plus entries from `requirements/common.txt`. That would duplicate the Python package set and invite `PYTHONPATH` collisions, which Nixpkgs explicitly warns against.

Use a small `python313Packages.overrideScope` for the coupled overrides. Refer to `final` members inside the scope, so `tokenizers`, `huggingface-hub`, Transformers, and the scikit-learn chain all come from the same Python fixed point. Keep each override only when an observed incompatibility requires it, include the upstream pin and removal condition in its comment, and avoid blanket `doCheck = false` changes. The current individually composed environment works, but a single local scope makes transitive dependency choices auditable and prevents one override from accidentally retaining a pre-override dependency.

The local Transformers source pin is justified only while the pinned Nixpkgs Transformers cannot satisfy the AudioMuse release contract. The update report should state whether the pinned Nixpkgs version already works, then remove the override rather than carry it forward. Treat `pythonRelaxDeps = [ "tokenizers" ]` as a metadata compatibility change, never as evidence that the application is compatible.

### Generated dependency table and patch

Inference: change the Transformers override so its source patch is release-specific and self-consistent:

1. Patch the canonical `_deps` entry in `setup.py` with `substituteInPlace --replace-fail` or a committed patch file whose name explains the Nixpkgs Tokenizers compatibility reason.
2. Run the upstream table generator named by that release, currently `python setup.py deps_table_update` or its `make deps_table_update` wrapper.
3. Assert the intended Tokenizers constraint appears in both `setup.py` and the regenerated `dependency_versions_table.py`.
4. In the Transformers install check, import Transformers and assert the installed Tokenizers distribution version satisfies the runtime table. Keep an import check for the final application environment too.

If a candidate release changes the generator, table path, constraint syntax, or runtime checker, the `--replace-fail` or assertion must fail. Update the patch and its test as a reviewed compatibility change. Do not replace it with a permissive `--replace` or an ignored failure.

## Checks that would catch update breakage

Inference: make these checks part of the package's normal evaluation and build path where feasible.

- Keep the updater fixture test with saved official release/tag JSON and requirement-file text. It covers stable-tag selection, prerelease rejection, no-write dry run, full-revision validation, required-file validation, managed Python source refreshes, and refusal when a Nixpkgs-backed compatibility pin changes. The test does not need the network.
- Keep the existing source-tree compile check and wrapper-shape checks. Add explicit assertions that all copied paths exist in the tagged source before copying. This turns upstream rearrangements into an early, legible failure.
- Add a Python contract check in the final composed environment. Import `transformers`, `tokenizers`, `onnxruntime`, and the application modules; query `importlib.metadata.version` for the direct compatibility-sensitive packages; and inspect `transformers.dependency_versions_table.deps["tokenizers"]`. Assert both the expected application pin or documented deviation and that `packaging.requirements.Requirement` accepts the installed version.
- Use upstream's relevant unit tests only after adapting external services, databases, model downloads, and hardware assumptions to the sandbox. The release's own test requirement file says several system components should be stubbed, so a full upstream suite is not currently a credible package check without further work. [Upstream test requirements](https://github.com/NeptuneHub/AudioMuse-AI/blob/31239fa986afb91a15e039e1a9a64ed5a2d6fa12/test/requirements.txt)
- Add a small `passthru.tests` smoke test only if the repository's CI selects and builds it. Nixpkgs documents `passthru.tests` as a way to attach package tests, but defining it does not make an ordinary package build execute it. [Nixpkgs package-test guidance](https://github.com/NixOS/nixpkgs/blob/8ce4ef6cb6f871616146b9fe26d2a5ae594e94fe/pkgs/README.md#writing-larger-package-tests)
- Build a lightweight Python-only check in normal CI. It instantiates the final composed environment, imports every API-sensitive library, and verifies the generated Transformers requirement without downloading the model derivation. Keep the full model-backed package audit opt-in when its size or licensing policy makes hosted builds inappropriate.

## Validation and limits

Validation performed on 2026-09-15:

- The updater's 21 stdlib-only tests pass, including stable-release selection, full-revision handling, managed Python source refreshes, contract rejection, per-Dockerfile model checks, atomic writes, no-write failures, and help without network access or Nix.
- The live `--dry-run` path passed against the official AudioMuse-AI release API. The current `v3.6.0` contract was also checked against its resolved commit before hashing.
- `workstation-task nix build .#audiomuse-ai --no-link --show-trace` passed. This built the independently pinned Transformers source and the final application install check.
- The package repository's `audiomuse-ai-python` and `package-unit-tests` derivations passed. Ruff and ty passed for the updater and its tests.
- `just os-build desktop` passed for the full `nixosConfigurations.desktop` closure without activating it.

The application was not started against PostgreSQL or a media server, model artifacts were not re-downloaded during validation, upstream tests were not run, and no other CPU architecture was built.

The release/tag API establishes that `v3.6.0` points at the recorded commit at retrieval time. It does not guarantee future availability, tag immutability, model-asset immutability, or compatibility with future Nixpkgs revisions. The proposed compatibility gates reduce accidental update breakage; they cannot prove the service works against PostgreSQL, media servers, real models, or every supported CPU architecture.

## Implication for this repository

The implementation applies the update gate, source-manifest split, managed Python refresh, and Python-only CI contract. Keep `buildPythonApplication` with `format = "other"`. Treat changes to the Transformer source, generated dependency table, model releases, or Nixpkgs-backed requirement pins as reviewed compatibility updates with the focused checks above. This note records the research and validation basis; package implementation remains in the package directory.
