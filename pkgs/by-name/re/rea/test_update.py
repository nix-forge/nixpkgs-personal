"""Exercise release mismatches, native pinning, and no-write preview behavior."""

import json
from io import StringIO
from typing import TYPE_CHECKING
from unittest.mock import patch

import pytest
import update

if TYPE_CHECKING:
    from pathlib import Path


def test_native_version_comes_from_lock():
    assert (
        update.native_version({
            "packages": {"node_modules/@lydell/node-pty": {"version": "1.2.3"}}
        })
        == "1.2.3"
    )
    with pytest.raises(ValueError, match="not a stable"):
        update.native_version({
            "packages": {"node_modules/@lydell/node-pty": {"version": "1.2.3-beta"}}
        })


def test_ambiguous_headers_stop_update(tmp_path: Path):
    (tmp_path / "yarn.lock").write_text('node-addon-api@^7.1.0:\n  version "7.1.0"\n')
    assert update.header_version(tmp_path) == "7.1.0"
    with (tmp_path / "yarn.lock").open("a") as stream:
        stream.write('node-addon-api@^8.0.0:\n  version "8.0.0"\n')
    with pytest.raises(ValueError, match="one locked"):
        update.header_version(tmp_path)


def test_registry_source_mismatch_does_not_prefetch():
    responses = [
        {"name": "rea-agents", "version": "6.4.0", "gitHead": "b" * 40},
        {"tag_name": "rea-agents-6.4.0"},
    ]
    with (
        patch.object(update, "fetch_json", side_effect=responses),
        patch.object(update, "tag_commit", return_value="a" * 40),
        patch.object(update, "github_source") as fetch,
    ):
        with pytest.raises(ValueError, match="disagree"):
            update.candidate(None)
        fetch.assert_not_called()


def test_failure_before_publish_preserves_pins(tmp_path: Path):
    source = tmp_path / "source.nix"
    source.write_text("original pins\n")
    with (
        patch.object(update, "PACKAGE", tmp_path),
        patch.object(
            update, "candidate", side_effect=ValueError("incomplete dependency fetch")
        ),
        patch("sys.argv", ["update.py"]),
        pytest.raises(ValueError, match="incomplete dependency"),
    ):
        update.main()
    assert source.read_text() == "original pins\n"


def test_preview_leaves_source_unchanged(tmp_path: Path):
    source = tmp_path / "source.nix"
    source.write_text("original pins\n")
    with (
        patch.object(update, "PACKAGE", tmp_path),
        patch.object(update, "candidate", return_value="candidate pins\n"),
        patch("sys.argv", ["update.py", "--check"]),
    ):
        update.main()
    assert source.read_text() == "original pins\n"


def test_render_rejects_fake_hash():
    with pytest.raises(ValueError, match="Invalid SHA256"):
        update.checked_hash("sha256-" + "A" * 43 + "=")


def test_success_refreshes_every_pin(tmp_path: Path):
    app = tmp_path / "app"
    native = tmp_path / "native"
    app.mkdir()
    native.mkdir()
    (app / "package.json").write_text(
        json.dumps({
            "name": "rea-agents",
            "version": "6.4.1",
            "license": "MIT",
            "bin": {"rea": "cli.js", "rea-agents": "cli.js"},
            "dependencies": {"evmole": "0.9.3"},
            "engines": {"node": "^22.23.4 || ^24.22.1 || >=26.12.1"},
        })
    )
    (app / "package-lock.json").write_text(
        json.dumps({
            "packages": {"node_modules/@lydell/node-pty": {"version": "1.2.3"}}
        })
    )
    (native / "package.json").write_text(json.dumps({"forkVersion": "1.2.3"}))
    (native / "yarn.lock").write_text('node-addon-api@^7.1.0:\n  version "7.1.0"\n')
    digest = "sha256-" + "B" * 43 + "="
    with (
        patch.object(
            update,
            "fetch_json",
            side_effect=[
                {"name": "rea-agents", "version": "6.4.1", "gitHead": "a" * 40},
                {"tag_name": "rea-agents-6.4.1"},
            ],
        ),
        patch.object(update, "tag_commit", side_effect=["a" * 40, "b" * 40]),
        patch.object(
            update,
            "github_source",
            side_effect=[
                {"storePath": str(app), "hash": digest},
                {"storePath": str(native), "hash": digest},
            ],
        ),
        patch.object(update, "prefetch", return_value={"hash": digest}),
        patch.object(update, "command", return_value=digest),
    ):
        result = update.candidate("6.4.1")
    assert 'version = "6.4.1";' in result
    assert 'version = "1.2.3";' in result
    assert 'version = "7.1.0";' in result
    expected_hash_count = 4
    assert result.count(digest) == expected_hash_count


def test_changed_license_stops_before_dependency_fetch(tmp_path: Path):
    (tmp_path / "package.json").write_text(
        json.dumps({"name": "rea-agents", "version": "6.4.1", "license": "GPL-3.0"})
    )
    with (
        patch.object(
            update,
            "fetch_json",
            side_effect=[
                {"name": "rea-agents", "version": "6.4.1", "gitHead": "a" * 40},
                {"tag_name": "rea-agents-6.4.1"},
            ],
        ),
        patch.object(update, "tag_commit", return_value="a" * 40),
        patch.object(
            update,
            "github_source",
            return_value={
                "storePath": str(tmp_path),
                "hash": "sha256-" + "B" * 43 + "=",
            },
        ),
        patch.object(update, "native_pins") as native,
        pytest.raises(ValueError, match="licensing changed"),
    ):
        update.candidate("6.4.1")
    native.assert_not_called()


@pytest.mark.parametrize("optional", [{}, {"frida": "17.23.2"}])
def test_reviewed_optional_provider_and_node_engine(optional):
    update.check_runtime_requirements({
        "optionalDependencies": optional,
        "engines": {"node": "^22.23.4 || ^24.22.1 || >=26.12.1"},
    })


@pytest.mark.parametrize(
    "optional",
    [{"frida": "17.23.3"}, {"other": "1.0.0"}, {"frida": "17.23.2", "other": "1.0.0"}],
)
def test_unreviewed_optional_dependencies_rejected(optional):
    with pytest.raises(ValueError, match="packaging review"):
        update.check_runtime_requirements({"optionalDependencies": optional})


@pytest.mark.parametrize("engine", ["^26.12.1", ">=24.22.2", "^24.23.0"])
def test_incompatible_engine_stops_update(engine):
    with pytest.raises(ValueError, match="incompatible"):
        update.check_runtime_requirements({"engines": {"node": engine}})


@pytest.mark.parametrize("engine", ["", ">=24", "*", "^24.22.1 || unknown"])
def test_unknown_engine_syntax_requires_review(engine):
    with pytest.raises(ValueError, match="syntax changed"):
        update.check_runtime_requirements({"engines": {"node": engine}})


def test_node_pin_rendered_with_application_and_native_pins():
    digest = "sha256-" + "B" * 43 + "="
    rendered = update.render(
        {"version": "6.8.0", "rev": "a" * 40, "hash": digest, "npmDepsHash": digest},
        {"version": "1.1.0", "rev": "b" * 40, "hash": digest},
        {"version": "7.1.0", "hash": digest},
    )
    assert f'version = "{update.NODE_VERSION}";' in rendered
    assert f'hash = "{update.NODE_HASH}";' in rendered
    assert f'version = "{update.BROTLI_VERSION}";' in rendered
    assert f'hash = "{update.BROTLI_HASH}";' in rendered


@pytest.mark.parametrize(
    ("url", "authenticated"),
    [
        ("https://api.github.com/repos/morluto/rea/releases", True),
        ("https://registry.npmjs.org/rea-agents/latest", False),
    ],
)
def test_github_credentials_only_sent_to_github_api(url, authenticated):
    with (
        patch.object(
            update,
            "github_api_headers",
            return_value={"Authorization": "Bearer fixture"},
        ) as headers,
        patch.object(update.urllib.request, "urlopen") as open_url,
    ):
        open_url.return_value.__enter__.return_value = StringIO('{"version": "6.8.0"}')
        assert update.fetch_json(url) == {"version": "6.8.0"}
    request = open_url.call_args.args[0]
    assert bool(request.get_header("Authorization")) is authenticated
    assert headers.call_count == int(authenticated)
