#!/usr/bin/env python3
"""Update AudioMuse-AI without accepting an unreviewed release contract."""

from __future__ import annotations

import argparse
import contextlib
import difflib
import json
import os
import re
import shutil
import ssl
import stat
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Final, NoReturn
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen

GITHUB_API: Final = "https://api.github.com/repos/NeptuneHub/AudioMuse-AI"
GITHUB_HOST: Final = "api.github.com"
RAW_GITHUB_HOST: Final = "raw.githubusercontent.com"
DOWNLOAD_HOST: Final = "github.com"
APP_OWNER: Final = "NeptuneHub"
APP_REPOSITORY: Final = "AudioMuse-AI"
VERSION_TAG_PATTERN: Final = re.compile(r"^v([0-9]+)\.([0-9]+)\.([0-9]+)$")
REVISION_PATTERN: Final = re.compile(r"^[0-9a-f]{40}$")
HASH_PATTERN: Final = re.compile(r"^sha256-[A-Za-z0-9+/=]+$")
TOKENIZERS_REQUIREMENT_PATTERN: Final = re.compile(
    r'^\s*"(tokenizers(?:===|==|!=|~=|>=|<=|>|<)[^" ]*)",\s*$'
)
HTTP_USER_AGENT: Final = (
    "nix-conf-audiomuse-updater/1.0 (+https://github.com/NixOS/nixpkgs)"
)
SOURCE_PATTERN: Final = re.compile(
    r"\A\{\n"
    r"  app = \{\n"
    r'    version = "([^"]+)";\n'
    r'    tag = "([^"]+)";\n'
    r'    rev = "([0-9a-f]{40})";\n'
    r'    hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"  \};\n\n"
    r"  compatibility = \{\n"
    r'    tokenizers = "([^"]+)";\n'
    r'    onnxruntime = "([^"]+)";\n'
    r"  \};\n\n"
    r"  models = \{\n"
    r'    release = "([^"]+)";\n'
    r'    dclapRelease = "([^"]+)";\n'
    r'    saeRelease = "([^"]+)";\n'
    r"  \};\n\n"
    r"  python = \{\n"
    r"    googleGenai = \{\n"
    r'      version = "([^"]+)";\n'
    r'      tag = "([^"]+)";\n'
    r'      rev = "([0-9a-f]{40})";\n'
    r'      hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"    \};\n\n"
    r"    huggingfaceHub = \{\n"
    r'      version = "([^"]+)";\n'
    r'      tag = "([^"]+)";\n'
    r'      rev = "([0-9a-f]{40})";\n'
    r'      hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"    \};\n\n"
    r"    mistralai = \{\n"
    r'      version = "([^"]+)";\n'
    r'      tag = "([^"]+)";\n'
    r'      rev = "([0-9a-f]{40})";\n'
    r'      hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r"    \};\n\n"
    r"    transformers = \{\n"
    r'      version = "([^"]+)";\n'
    r'      tag = "([^"]+)";\n'
    r'      rev = "([0-9a-f]{40})";\n'
    r'      hash = "(sha256-[A-Za-z0-9+/=]+)";\n'
    r'      upstreamTokenizersRequirement = "([^"]+)";\n'
    r'      tokenizersRequirement = "([^"]+)";\n'
    r"    \};\n"
    r"  \};\n"
    r"\}\n\Z"
)
REQUIRED_SOURCE_ENTRIES: Final = {
    "LICENSE": "blob",
    "dclap_sae_concepts.json": "blob",
    "genre_subgenre.json": "blob",
    "mood_centroids_real_080_clap.json": "blob",
    "error": "tree",
    "lyrics": "tree",
    "plugin": "tree",
    "query": "tree",
    "static": "tree",
    "taskqueue": "tree",
    "tasks": "tree",
    "templates": "tree",
    "native-build/linux/__init__.py": "blob",
    "native-build/linux/launcher.py": "blob",
    "native-build/native_common/__init__.py": "blob",
    "native-build/native_common/frozen_children.py": "blob",
    "service_roles.py": "blob",
}
SERVICE_PATCH_ANCHORS: Final = (
    "import os",
    "FLASK_BIND_HOST = '0.0.0.0'",
    "FLASK_BIND_PORT = 8000",
)


@dataclass(frozen=True)
class _Compatibility:
    tokenizers: str
    onnxruntime: str


@dataclass(frozen=True)
class _PythonSource:
    version: str
    tag: str
    rev: str
    hash: str


@dataclass(frozen=True)
class _TransformersSource(_PythonSource):
    upstream_tokenizers_requirement: str
    tokenizers_requirement: str


@dataclass(frozen=True)
class _Source:
    app_version: str
    app_tag: str
    app_rev: str
    app_hash: str
    compatibility: _Compatibility
    model_release: str
    dclap_release: str
    sae_release: str
    google_genai: _PythonSource
    huggingface_hub: _PythonSource
    mistralai: _PythonSource
    transformers: _TransformersSource


@dataclass(frozen=True)
class _Requirements:
    google_genai: str
    huggingface_hub: str
    mistralai: str
    transformers: str
    tokenizers: str
    onnxruntime: str


@dataclass(frozen=True)
class _Release:
    version: str
    tag: str
    rev: str = ""


def _stderr(message: str) -> None:
    sys.stderr.write(f"{message}\n")


def _stdout(message: str) -> None:
    sys.stdout.write(f"{message}\n")


def _fail(message: str) -> NoReturn:
    _stderr(f"error: {message}")
    raise SystemExit(1)


def _github_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": HTTP_USER_AGENT,
    }
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _fetch_json(url: str, *, label: str) -> object:
    parsed = urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != GITHUB_HOST:
        _fail(f"unexpected GitHub API URL for {label}: {url!r}")

    try:
        request = Request(url, headers=_github_headers())
        with urlopen(
            request, timeout=30, context=ssl.create_default_context()
        ) as response:
            return json.load(response)
    except HTTPError as exc:
        _fail(f"failed to fetch {label} from {url}: HTTP {exc.code}")
    except (URLError, json.JSONDecodeError) as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")


def _fetch_text(url: str, *, label: str) -> str:
    parsed = urlparse(url)
    if (
        parsed.scheme != "https"
        or parsed.netloc != RAW_GITHUB_HOST
        or parsed.query
        or parsed.fragment
    ):
        _fail(f"unexpected raw GitHub URL for {label}: {url!r}")

    try:
        request = Request(url, headers={"User-Agent": HTTP_USER_AGENT})
        with urlopen(
            request, timeout=30, context=ssl.create_default_context()
        ) as response:
            return response.read().decode("utf-8")
    except HTTPError as exc:
        _fail(f"failed to fetch {label} from {url}: HTTP {exc.code}")
    except (URLError, UnicodeDecodeError) as exc:
        _fail(f"failed to fetch {label} from {url}: {exc}")


def _select_release(data: object) -> _Release:
    if not isinstance(data, list):
        _fail("AudioMuse-AI releases response was not a list")

    candidates: list[tuple[tuple[int, int, int], str, str]] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        if item.get("draft") is not False or item.get("prerelease") is not False:
            continue
        tag = item.get("tag_name")
        if not isinstance(tag, str):
            continue
        match = VERSION_TAG_PATTERN.fullmatch(tag)
        if match is None:
            # This intentionally excludes model and prerelease tags.
            continue
        version = (
            int(match.group(1)),
            int(match.group(2)),
            int(match.group(3)),
        )
        candidates.append((version, tag, f"{version[0]}.{version[1]}.{version[2]}"))

    if not candidates:
        _fail("AudioMuse-AI has no stable release with a vX.Y.Z tag")

    _, tag, version = max(candidates)
    return _Release(version=version, tag=tag)


def _discover_release() -> _Release:
    return _select_release(
        _fetch_json(
            f"{GITHUB_API}/releases?per_page=100", label="AudioMuse-AI releases"
        )
    )


def _resolve_revision(
    tag: str,
    *,
    owner: str = APP_OWNER,
    repository: str = APP_REPOSITORY,
) -> str:
    data = _fetch_json(
        f"https://{GITHUB_HOST}/repos/{quote(owner, safe='')}/"
        f"{quote(repository, safe='')}/commits/{quote(tag, safe='')}",
        label=f"{owner}/{repository} {tag} commit",
    )
    if not isinstance(data, dict):
        _fail(f"{owner}/{repository} {tag} commit response was not an object")
    revision = data.get("sha")
    if not isinstance(revision, str) or REVISION_PATTERN.fullmatch(revision) is None:
        _fail(f"{owner}/{repository} {tag} did not resolve to a full commit revision")
    return revision


def _raw_url(
    revision: str,
    path: str,
    *,
    owner: str = APP_OWNER,
    repository: str = APP_REPOSITORY,
) -> str:
    if REVISION_PATTERN.fullmatch(revision) is None:
        _fail(f"cannot construct a source URL from invalid revision {revision!r}")
    if not re.fullmatch(r"(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+", path):
        _fail(f"unexpected upstream source path: {path!r}")
    return (
        f"https://{RAW_GITHUB_HOST}/{quote(owner, safe='')}/"
        f"{quote(repository, safe='')}/{revision}/{path}"
    )


def _parse_existing(content: str) -> _Source:
    match = SOURCE_PATTERN.fullmatch(content)
    if match is None:
        _fail("source.nix does not match the updater-owned format")

    groups = match.groups()
    if groups[1] != f"v{groups[0]}":
        _fail(f"source.nix app tag {groups[1]!r} does not match version {groups[0]!r}")

    python_sources = {
        "google-genai": (groups[9], groups[10]),
        "huggingface-hub": (groups[13], groups[14]),
        "mistralai": (groups[17], groups[18]),
        "transformers": (groups[21], groups[22]),
    }
    for package, (version, tag) in python_sources.items():
        if tag != f"v{version}":
            _fail(
                f"source.nix {package} tag {tag!r} does not match version {version!r}"
            )

    return _Source(
        app_version=groups[0],
        app_tag=groups[1],
        app_rev=groups[2],
        app_hash=groups[3],
        compatibility=_Compatibility(
            tokenizers=groups[4],
            onnxruntime=groups[5],
        ),
        model_release=groups[6],
        dclap_release=groups[7],
        sae_release=groups[8],
        google_genai=_PythonSource(groups[9], groups[10], groups[11], groups[12]),
        huggingface_hub=_PythonSource(groups[13], groups[14], groups[15], groups[16]),
        mistralai=_PythonSource(groups[17], groups[18], groups[19], groups[20]),
        transformers=_TransformersSource(
            groups[21],
            groups[22],
            groups[23],
            groups[24],
            groups[25],
            groups[26],
        ),
    )


def _render_python_source(source: _PythonSource, *, indent: str) -> str:
    return (
        f'{indent}version = "{source.version}";\n'
        f'{indent}tag = "{source.tag}";\n'
        f'{indent}rev = "{source.rev}";\n'
        f'{indent}hash = "{source.hash}";\n'
    )


def _render_source(
    existing: _Source,
    release: _Release,
    hash_sri: str,
    *,
    python_sources: tuple[
        _PythonSource, _PythonSource, _PythonSource, _TransformersSource
    ]
    | None = None,
) -> str:
    if not HASH_PATTERN.fullmatch(hash_sri):
        _fail(f"cannot render an invalid source hash: {hash_sri!r}")
    google_genai, huggingface_hub, mistralai, transformers = python_sources or (
        existing.google_genai,
        existing.huggingface_hub,
        existing.mistralai,
        existing.transformers,
    )
    for source_name, source in (
        ("google-genai", google_genai),
        ("huggingface-hub", huggingface_hub),
        ("mistralai", mistralai),
        ("transformers", transformers),
    ):
        if not REVISION_PATTERN.fullmatch(source.rev):
            _fail(f"cannot render an invalid {source_name} revision: {source.rev!r}")
        if not HASH_PATTERN.fullmatch(source.hash):
            _fail(f"cannot render an invalid {source_name} hash: {source.hash!r}")
    return (
        "{\n"
        "  app = {\n"
        f'    version = "{release.version}";\n'
        f'    tag = "{release.tag}";\n'
        f'    rev = "{release.rev}";\n'
        f'    hash = "{hash_sri}";\n'
        "  };\n\n"
        "  compatibility = {\n"
        f'    tokenizers = "{existing.compatibility.tokenizers}";\n'
        f'    onnxruntime = "{existing.compatibility.onnxruntime}";\n'
        "  };\n\n"
        "  models = {\n"
        f'    release = "{existing.model_release}";\n'
        f'    dclapRelease = "{existing.dclap_release}";\n'
        f'    saeRelease = "{existing.sae_release}";\n'
        "  };\n\n"
        "  python = {\n"
        "    googleGenai = {\n"
        + _render_python_source(google_genai, indent="      ")
        + "    };\n\n"
        + "    huggingfaceHub = {\n"
        + _render_python_source(huggingface_hub, indent="      ")
        + "    };\n\n"
        + "    mistralai = {\n"
        + _render_python_source(mistralai, indent="      ")
        + "    };\n\n"
        + "    transformers = {\n"
        + _render_python_source(transformers, indent="      ")
        + f'      upstreamTokenizersRequirement = "{transformers.upstream_tokenizers_requirement}";\n'
        + f'      tokenizersRequirement = "{transformers.tokenizers_requirement}";\n'
        + "    };\n"
        + "  };\n"
        "}\n"
    )


def _requirement_version(content: str, package: str, *, label: str) -> str:
    expected_name = package.lower().replace("_", "-")
    matches: list[str] = []
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line or line.startswith(("-", "r ")):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)\s*==\s*([^\s;]+)(?:\s*;.*)?", line)
        if (
            match is not None
            and match.group(1).lower().replace("_", "-") == expected_name
        ):
            matches.append(match.group(2))

    if len(matches) != 1:
        _fail(
            f"expected exactly one exact {package} pin in {label}, found {len(matches)}"
        )
    return matches[0]


def _validate_source_layout(revision: str) -> None:
    data = _fetch_json(
        f"{GITHUB_API}/git/trees/{revision}?recursive=1",
        label="AudioMuse-AI source tree",
    )
    if not isinstance(data, dict) or data.get("truncated") is not False:
        _fail("AudioMuse-AI source tree response was missing or truncated")
    tree = data.get("tree")
    if not isinstance(tree, list):
        _fail("AudioMuse-AI source tree response did not contain a tree list")

    entries: dict[str, str] = {}
    for item in tree:
        if not isinstance(item, dict):
            continue
        path = item.get("path")
        kind = item.get("type")
        if isinstance(path, str) and isinstance(kind, str):
            entries[path] = kind

    missing = [
        path
        for path, kind in REQUIRED_SOURCE_ENTRIES.items()
        if entries.get(path) != kind
    ]
    if missing:
        _fail(
            "AudioMuse-AI source layout no longer contains the paths required by "
            f"the Nix install phase: {', '.join(sorted(missing))}"
        )

    service_roles = _fetch_text(
        _raw_url(revision, "service_roles.py"),
        label="AudioMuse-AI service_roles.py",
    )
    missing_anchors = [
        anchor for anchor in SERVICE_PATCH_ANCHORS if anchor not in service_roles
    ]
    if missing_anchors:
        _fail(
            "AudioMuse-AI service_roles.py no longer contains the patch anchors "
            f"required by package.nix: {', '.join(missing_anchors)}"
        )


def _validate_requirements(source: _Source, revision: str) -> _Requirements:
    common = _fetch_text(
        _raw_url(revision, "requirements/common.txt"),
        label="AudioMuse-AI common requirements",
    )
    linux = _fetch_text(
        _raw_url(revision, "requirements/linux.txt"),
        label="AudioMuse-AI Linux requirements",
    )
    actual = _Requirements(
        google_genai=_requirement_version(
            common, "google-genai", label="requirements/common.txt"
        ),
        huggingface_hub=_requirement_version(
            common, "huggingface-hub", label="requirements/common.txt"
        ),
        mistralai=_requirement_version(
            common, "mistralai", label="requirements/common.txt"
        ),
        transformers=_requirement_version(
            common, "transformers", label="requirements/common.txt"
        ),
        tokenizers=_requirement_version(
            common, "tokenizers", label="requirements/common.txt"
        ),
        onnxruntime=_requirement_version(
            linux, "onnxruntime", label="requirements/linux.txt"
        ),
    )

    # These two packages are supplied by the pinned Nixpkgs Python set rather
    # than a private source recipe. A change is intentionally review-gated so
    # an application release cannot silently outrun that set.
    for package, expected, value in (
        ("tokenizers", source.compatibility.tokenizers, actual.tokenizers),
        ("onnxruntime", source.compatibility.onnxruntime, actual.onnxruntime),
    ):
        if value != expected:
            _fail(
                f"AudioMuse-AI requirements change {package}: manifest pins "
                f"{expected}, upstream pins {value}; update the Nixpkgs-backed "
                "Python compatibility contract separately"
            )

    return actual


def _fetch_transformers_tokenizers_requirement(revision: str) -> str:
    setup = _fetch_text(
        _raw_url(
            revision,
            "setup.py",
            owner="huggingface",
            repository="transformers",
        ),
        label="Transformers setup.py",
    )
    matches = [
        match.group(1)
        for line in setup.splitlines()
        if (match := TOKENIZERS_REQUIREMENT_PATTERN.fullmatch(line)) is not None
    ]
    if len(matches) != 1:
        _fail(
            "Transformers setup.py did not contain exactly one tokenizers "
            f"requirement, found {len(matches)}"
        )
    return matches[0]


def _version_key(version: str) -> tuple[int, ...]:
    match = re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version)
    if match is None:
        _fail(
            f"unsupported Python package version for compatibility check: {version!r}"
        )
    parts = [int(part) for part in version.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


COMPATIBLE_RELEASE_COMPONENTS: Final = 2


def _constraint_contains(
    operator: str, candidate: tuple[int, ...], bound: tuple[int, ...]
) -> bool:
    if operator in {"==", "==="}:
        result = candidate == bound
    elif operator == "!=":
        result = candidate != bound
    elif operator == ">=":
        result = candidate >= bound
    elif operator == "<=":
        result = candidate <= bound
    elif operator == ">":
        result = candidate > bound
    elif operator == "<":
        result = candidate < bound
    elif operator == "~=":
        if len(bound) <= COMPATIBLE_RELEASE_COMPONENTS:
            compatible_upper = (bound[0] + 1,)
        else:
            compatible_upper = (*bound[:1], bound[1] + 1)
        result = candidate >= bound and candidate < compatible_upper
    else:
        _fail(f"unsupported version operator in requirement: {operator!r}")
    return result


def _requirement_contains(requirement: str, version: str) -> bool:
    match = re.fullmatch(r"tokenizers((?:===|==|!=|~=|>=|<=|>|<).+)", requirement)
    if match is None:
        _fail(f"unsupported Transformers tokenizers requirement: {requirement!r}")
    candidate = _version_key(version)
    constraints = re.findall(
        r"(===|==|!=|~=|>=|<=|>|<)\s*([0-9]+(?:\.[0-9]+)*)", match.group(1)
    )
    if not constraints:
        _fail(
            f"Transformers tokenizers requirement has no constraints: {requirement!r}"
        )

    return all(
        _constraint_contains(operator, candidate, _version_key(bound_text))
        for operator, bound_text in constraints
    )


def _nixpkgs_python_version(package: str) -> str:
    nix = shutil.which("nix")
    if nix is None:
        _fail("nix executable not found in PATH")

    repository_root = Path(__file__).resolve().parents[3]
    attribute = f".#legacyPackages.x86_64-linux.python313Packages.{package}.version"
    completed = subprocess.run(
        [
            nix,
            "eval",
            "--raw",
            "--option",
            "allow-import-from-derivation",
            "false",
            attribute,
        ],
        capture_output=True,
        check=False,
        cwd=repository_root,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "(no output)"
        _fail(f"failed to evaluate the pinned Nixpkgs {package} version: {detail}")
    version = completed.stdout.strip()
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version):
        _fail(f"pinned Nixpkgs returned an invalid {package} version: {version!r}")
    return version


def _fetch_python_source(
    *,
    owner: str,
    repository: str,
    version: str,
    label: str,
) -> _PythonSource:
    tag = f"v{version}"
    revision = _resolve_revision(tag, owner=owner, repository=repository)
    return _PythonSource(
        version=version,
        tag=tag,
        rev=revision,
        hash=_prefetch_source_hash(
            revision,
            owner=owner,
            repository=repository,
            label=f"{label} {tag}",
        ),
    )


def _update_python_sources(
    source: _Source,
    requirements: _Requirements,
    *,
    refresh: bool,
) -> tuple[_PythonSource, _PythonSource, _PythonSource, _TransformersSource]:
    sources = (
        (
            source.google_genai,
            requirements.google_genai,
            "googleapis",
            "python-genai",
            "google-genai",
        ),
        (
            source.huggingface_hub,
            requirements.huggingface_hub,
            "huggingface",
            "huggingface_hub",
            "huggingface-hub",
        ),
        (
            source.mistralai,
            requirements.mistralai,
            "mistralai",
            "client-python",
            "mistralai",
        ),
    )
    updated: list[_PythonSource] = []
    for current, version, owner, repository, label in sources:
        if not refresh and current.version == version and current.tag == f"v{version}":
            updated.append(current)
            continue
        updated.append(
            _fetch_python_source(
                owner=owner,
                repository=repository,
                version=version,
                label=label,
            )
        )

    current_transformers = source.transformers
    transformer_changed = (
        refresh
        or current_transformers.version != requirements.transformers
        or current_transformers.tag != f"v{requirements.transformers}"
    )
    if not transformer_changed:
        transformers = current_transformers
    else:
        base = _fetch_python_source(
            owner="huggingface",
            repository="transformers",
            version=requirements.transformers,
            label="transformers",
        )
        upstream_requirement = _fetch_transformers_tokenizers_requirement(base.rev)
        nixpkgs_tokenizers = _nixpkgs_python_version("tokenizers")
        same_source = (
            current_transformers.version == base.version
            and current_transformers.tag == base.tag
            and current_transformers.rev == base.rev
        )
        if same_source and _requirement_contains(
            current_transformers.tokenizers_requirement, nixpkgs_tokenizers
        ):
            # Keep the explicitly reviewed local widening when refreshing the
            # current release. It is allowed to differ from upstream metadata,
            # but remains checked against the actual Nixpkgs package version.
            local_requirement = current_transformers.tokenizers_requirement
        elif _requirement_contains(upstream_requirement, nixpkgs_tokenizers):
            local_requirement = upstream_requirement
        else:
            _fail(
                f"Transformers {base.version} requires {upstream_requirement!r}, "
                f"but pinned Nixpkgs provides tokenizers {nixpkgs_tokenizers}; "
                "review the compatibility override before updating source.nix"
            )
        transformers = _TransformersSource(
            base.version,
            base.tag,
            base.rev,
            base.hash,
            upstream_requirement,
            local_requirement,
        )

    return updated[0], updated[1], updated[2], transformers


MODEL_REFERENCE_PATTERNS: Final = {
    "model release": re.compile(r"AudioMuse-AI/releases/download/([^/\s\"'$]+)"),
    "DCLAP release": re.compile(r"AudioMuse-AI-DCLAP/releases/download/([^/\s\"'$]+)"),
    "SAE release": re.compile(r"AudioMuse-AI-SAE/releases/download/([^/\s\"'$]+)"),
}
MODEL_REFERENCES_BY_DOCKERFILE: Final = {
    "Dockerfile": frozenset(MODEL_REFERENCE_PATTERNS),
    # The no-AVX2 image intentionally does not download the SAE graphs.
    "Dockerfile-noavx2": frozenset({"model release", "DCLAP release"}),
}


def _validate_model_references(source: _Source, revision: str) -> None:
    expected = {
        "model release": source.model_release,
        "DCLAP release": source.dclap_release,
        "SAE release": source.sae_release,
    }
    for filename in ("Dockerfile", "Dockerfile-noavx2"):
        content = _fetch_text(
            _raw_url(revision, filename),
            label=f"AudioMuse-AI {filename}",
        )
        references_by_kind = {label: set() for label in MODEL_REFERENCE_PATTERNS}
        for label, pattern in MODEL_REFERENCE_PATTERNS.items():
            references_by_kind[label].update(pattern.findall(content))
        expected_labels = MODEL_REFERENCES_BY_DOCKERFILE[filename]
        for label, references in references_by_kind.items():
            expected_references = (
                {expected[label]} if label in expected_labels else set()
            )
            if references != expected_references:
                expected_text = (
                    f"manifest pins {expected[label]!r}"
                    if label in expected_labels
                    else "no reference is expected"
                )
                _fail(
                    f"AudioMuse-AI {filename} changes the {label}: {expected_text}, "
                    "upstream references "
                    f"{sorted(references)!r}; update model metadata separately"
                )


def _validate_release_contract(source: _Source, revision: str) -> _Requirements:
    _validate_source_layout(revision)
    requirements = _validate_requirements(source, revision)
    _validate_model_references(source, revision)
    return requirements


def _prefetch_source_hash(
    revision: str,
    *,
    owner: str = APP_OWNER,
    repository: str = APP_REPOSITORY,
    label: str = "AudioMuse-AI source",
) -> str:
    nix = shutil.which("nix")
    if nix is None:
        _fail("nix executable not found in PATH")

    url = (
        f"https://{DOWNLOAD_HOST}/{quote(owner, safe='')}/"
        f"{quote(repository, safe='')}/archive/{revision}.tar.gz"
    )
    completed = subprocess.run(
        [
            nix,
            "store",
            "prefetch-file",
            "--unpack",
            "--json",
            "--hash-type",
            "sha256",
            url,
        ],
        capture_output=True,
        check=False,
        text=True,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or "(no output)"
        _fail(f"failed to prefetch {label}: {detail}")

    try:
        response = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        _fail(f"could not parse Nix prefetch output for {label}: {exc}")
    hash_sri = response.get("hash") if isinstance(response, dict) else None
    if not isinstance(hash_sri, str) or not HASH_PATTERN.fullmatch(hash_sri):
        _fail(f"Nix prefetch returned an invalid hash for {label}: {hash_sri!r}")
    return hash_sri


def _write_atomic(path: Path, content: str) -> None:
    mode = stat.S_IMODE(path.stat().st_mode)
    file_descriptor, temporary_path = tempfile.mkstemp(
        prefix=f"{path.name}.", dir=path.parent
    )
    try:
        Path(temporary_path).chmod(mode)
        with os.fdopen(file_descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        Path(temporary_path).replace(path)
    finally:
        with contextlib.suppress(OSError):
            Path(temporary_path).unlink(missing_ok=True)


def _diff(old: str, new: str, path: Path) -> str:
    return "".join(
        difflib.unified_diff(
            old.splitlines(keepends=True),
            new.splitlines(keepends=True),
            fromfile=str(path),
            tofile=str(path),
        )
    )


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero when application or Python source pins would change",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show the source.nix diff without writing it",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="re-download and verify current application and Python source hashes",
    )
    return parser.parse_args(argv)


def _main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv if argv is not None else sys.argv[1:])
    source_path = Path(__file__).resolve().with_name("source.nix")
    old_content = source_path.read_text(encoding="utf-8")
    existing = _parse_existing(old_content)

    discovered = _discover_release()
    release = _Release(
        version=discovered.version,
        tag=discovered.tag,
        rev=_resolve_revision(discovered.tag),
    )
    requirements = _validate_release_contract(existing, release.rev)
    python_sources = _update_python_sources(
        existing,
        requirements,
        refresh=args.refresh,
    )

    current_app = (
        existing.app_version == release.version
        and existing.app_tag == release.tag
        and existing.app_rev == release.rev
    )
    current_python = python_sources == (
        existing.google_genai,
        existing.huggingface_hub,
        existing.mistralai,
        existing.transformers,
    )
    if current_app and current_python and not args.refresh:
        _stdout("[update] audiomuse-ai is already up to date")
        return 0

    hash_sri = (
        _prefetch_source_hash(release.rev)
        if not current_app or args.refresh
        else existing.app_hash
    )
    new_content = _render_source(
        existing,
        release,
        hash_sri,
        python_sources=python_sources,
    )
    if new_content == old_content:
        _stdout("[update] audiomuse-ai is already up to date")
        return 0

    diff = _diff(old_content, new_content, source_path)
    if args.check:
        _stdout(diff)
        return 1
    if args.dry_run:
        _stdout(diff)
        return 0

    _write_atomic(source_path, new_content)
    changes: list[str] = []
    if not current_app:
        changes.append(f"application {existing.app_tag} -> {release.tag}")
    if not current_python:
        changes.append("API-sensitive Python source pins")
    if hash_sri != existing.app_hash:
        changes.append("application source hash")
    _stdout(f"[update] audiomuse-ai: {', '.join(changes)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
