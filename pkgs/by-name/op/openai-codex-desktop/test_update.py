"""Verify pinned desktop releases and reject inconsistent upstream metadata."""

from __future__ import annotations

import contextlib
import hashlib
import importlib.util
import io
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

UPDATE_PATH = Path(__file__).with_name("update.py")
SPEC = importlib.util.spec_from_file_location(
    "openai_codex_desktop_update", UPDATE_PATH
)
if SPEC is None or SPEC.loader is None:
    message = f"could not load {UPDATE_PATH}"
    raise RuntimeError(message)
update = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = update
SPEC.loader.exec_module(update)


def _ar_member(name: str, content: bytes) -> bytes:
    fields = (
        f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(content):<10}`\n"
    ).encode("ascii")
    return fields + content + (b"\n" if len(content) % 2 else b"")


def _debian_package(control: str) -> bytes:
    control_archive = io.BytesIO()
    control_data = control.encode()
    with tarfile.open(fileobj=control_archive, mode="w:xz") as archive:
        member = tarfile.TarInfo("./control")
        member.size = len(control_data)
        member.mode = 0o644
        archive.addfile(member, io.BytesIO(control_data))
    return b"!<arch>\n" + _ar_member("control.tar.xz", control_archive.getvalue())


def _source(
    system: str,
    *,
    version: str = "26.901.41600",
    hash_sri: str = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
) -> update._Source:
    suffixes = {
        "aarch64-darwin": f"ChatGPT-darwin-arm64-{version}.zip",
        "aarch64-linux": (f"linux/deb/pool/main/c/chatgpt/chatgpt_{version}_arm64.deb"),
        "x86_64-linux": (f"linux/deb/pool/main/c/chatgpt/chatgpt_{version}_amd64.deb"),
    }
    return update._Source(
        version=version,
        url=f"https://persistent.oaistatic.com/codex-app-prod/{suffixes[system]}",
        hash_sri=hash_sri,
    )


class SourceMetadataTests(unittest.TestCase):
    """Check immutable source metadata and platform-specific releases."""

    def test_rendered_source_round_trips_with_per_system_versions(self) -> None:
        """Preserve independently released versions when serializing Nix sources."""
        state = update._UpstreamState(
            app_name="ChatGPT",
            sources={
                system: _source(
                    system,
                    version=(
                        "26.901.41123" if system == "aarch64-darwin" else "26.901.41600"
                    ),
                )
                for system in update.SUPPORTED_SYSTEMS
            },
        )

        self.assertEqual(update._parse_existing(update._render_source(state)), state)

    def test_macos_url_must_match_appcast_version(self) -> None:
        """Reject an archive whose filename disagrees with its release version."""
        with (
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            update._validate_macos_url(
                "26.901.41600",
                "https://persistent.oaistatic.com/codex-app-prod/"
                "ChatGPT-darwin-arm64-26.901.00000.zip",
            )

    def test_linux_metadata_hash_change_is_detected(self) -> None:
        """Refresh a source when upstream changes its digest."""
        existing = _source("x86_64-linux")
        discovered = update._DiscoveredSource(
            version=existing.version,
            url=existing.url,
            expected_size=1,
            published_sha256="11" * 32,
        )

        self.assertFalse(update._source_matches_discovery(existing, discovered))

    def test_macos_republished_build_is_detected_without_a_version_change(self) -> None:
        """A new Sparkle build at the same archive URL needs a source refresh."""
        source = _source("aarch64-darwin")
        existing = update._Source(
            source.version, source.url, source.hash_sri, build_version="13232"
        )
        discovered = update._DiscoveredSource(
            source.version, source.url, expected_size=1, build_version="13520"
        )
        self.assertFalse(update._source_matches_discovery(existing, discovered))
        current = update._Source(
            source.version, source.url, source.hash_sri, build_version="13520"
        )
        self.assertTrue(update._source_matches_discovery(current, discovered))

    def test_macos_build_identity_round_trips_and_migrates_old_pins(self) -> None:
        """Persist the build identity and refresh pins that predate its tracking."""
        sources = {system: _source(system) for system in update.SUPPORTED_SYSTEMS}
        macos = sources["aarch64-darwin"]
        discovered = update._DiscoveredSource(
            macos.version, macos.url, expected_size=1, build_version="13520"
        )
        self.assertFalse(update._source_matches_discovery(macos, discovered))
        sources["aarch64-darwin"] = update._Source(
            macos.version, macos.url, macos.hash_sri, build_version="13520"
        )
        state = update._UpstreamState(app_name="ChatGPT", sources=sources)
        self.assertEqual(update._parse_existing(update._render_source(state)), state)

    def test_macos_feed_records_the_numeric_build_identity(self) -> None:
        """Track Sparkle's build rather than only its reused short version."""
        source = _source("aarch64-darwin")
        xml = f'''<rss xmlns:sparkle="{update.SPARKLE_NAMESPACE["sparkle"]}">
            <channel><item>
                <sparkle:version>13520</sparkle:version>
                <sparkle:shortVersionString>{source.version}</sparkle:shortVersionString>
                <enclosure url="{source.url}" length="1"
                    sparkle:edSignature="{"A" * 86}==" />
            </item></channel>
        </rss>'''
        with mock.patch.object(
            update, "_fetch_xml", return_value=update.ET.fromstring(xml)
        ):
            _, discovered = update._discover_macos_source()
        self.assertEqual(discovered.build_version, "13520")
        with (
            mock.patch.object(
                update,
                "_fetch_xml",
                return_value=update.ET.fromstring(xml.replace("13520", "invalid")),
            ),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            update._discover_macos_source()

    def test_fetched_macos_source_preserves_build_identity(self) -> None:
        """The update path must write the identity needed by the next scheduled run."""
        sources = {system: _source(system) for system in update.SUPPORTED_SYSTEMS}
        source = sources["aarch64-darwin"]
        discovered = update._DiscoveredSource(
            source.version, source.url, expected_size=1, build_version="13520"
        )
        release = update._Release("ChatGPT", {"aarch64-darwin": discovered})
        existing = update._UpstreamState("ChatGPT", sources)
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "macos.zip"
            archive.write_bytes(b"x")
            prefetched = update._PrefetchedSource(source.hash_sri, archive)
            with mock.patch.object(update, "_prefetch_source", return_value=prefetched):
                fetched = update._fetch_upstream(release, existing, ["aarch64-darwin"])
        self.assertEqual(fetched.sources["aarch64-darwin"].build_version, "13520")
        self.assertEqual(
            update._changed_systems(
                fetched,
                update._Release(
                    "ChatGPT",
                    {
                        system: discovered
                        if system == "aarch64-darwin"
                        else update._DiscoveredSource(
                            sources[system].version, sources[system].url, 1
                        )
                        for system in update.SUPPORTED_SYSTEMS
                    },
                ),
            ),
            [],
        )


class DebianMetadataTests(unittest.TestCase):
    """Check APT records against the downloaded Debian package."""

    def test_negative_archive_member_size_is_rejected(self) -> None:
        """Reject malformed ar headers before reading or seeking payload bytes."""
        header = (
            f"{'control.tar.xz/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{-1:<10}`\n"
        ).encode("ascii")
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "invalid.deb"
            package.write_bytes(b"!<arch>\n" + header)
            with (
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                update._read_ar_member(package, frozenset({"control.tar.xz"}))

    def test_expected_apt_record_produces_immutable_url(self) -> None:
        """Resolve a versioned APT path beneath the fixed release origin."""
        fields = (
            "Package: chatgpt\n"
            "Version: 26.901.41600\n"
            "Architecture: amd64\n"
            "Maintainer: OpenAI <support@openai.com>\n"
            "Filename: pool/main/c/chatgpt/chatgpt_26.901.41600_amd64.deb\n"
            "Size: 42\n"
            f"SHA256: {'ab' * 32}\n"
        )
        with mock.patch.object(
            update,
            "_fetch_bytes",
            return_value=update.gzip.compress(fields.encode()),
        ):
            source = update._discover_linux_source("x86_64-linux")

        self.assertEqual(source.version, "26.901.41600")
        self.assertEqual(
            source.url,
            "https://persistent.oaistatic.com/codex-app-prod/linux/deb/"
            "pool/main/c/chatgpt/chatgpt_26.901.41600_amd64.deb",
        )
        self.assertNotIn("/latest/", source.url)

    def test_mutable_or_unexpected_apt_filename_is_rejected(self) -> None:
        """Reject mutable download paths even when other metadata is valid."""
        fields = (
            "Package: chatgpt\n"
            "Version: 26.901.41600\n"
            "Architecture: arm64\n"
            "Maintainer: OpenAI <support@openai.com>\n"
            "Filename: latest/chatgpt_arm64.deb\n"
            "Size: 42\n"
            f"SHA256: {'ab' * 32}\n"
        )
        with (
            mock.patch.object(
                update,
                "_fetch_bytes",
                return_value=update.gzip.compress(fields.encode()),
            ),
            contextlib.redirect_stderr(io.StringIO()),
            self.assertRaises(SystemExit),
        ):
            update._discover_linux_source("aarch64-linux")

    def test_downloaded_deb_control_and_published_hash_are_validated(self) -> None:
        """Accept a package whose control record and digest match the index."""
        package_bytes = _debian_package(
            "Package: chatgpt\n"
            "Version: 26.901.41600\n"
            "Architecture: amd64\n"
            "Maintainer: OpenAI <support@openai.com>\n"
        )
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "chatgpt.deb"
            package.write_bytes(package_bytes)
            digest = hashlib.sha256(package_bytes).hexdigest()
            discovered = update._DiscoveredSource(
                version="26.901.41600",
                url=_source("x86_64-linux").url,
                expected_size=len(package_bytes),
                published_sha256=digest,
            )
            prefetched = update._PrefetchedSource(
                hash_sri=update._hex_sha256_to_sri(digest),
                store_path=package,
            )

            self.assertIsNone(
                update._validate_prefetched_source(
                    "x86_64-linux", discovered, prefetched
                )
            )

    def test_mismatched_deb_version_is_rejected(self) -> None:
        """Reject package bytes for a different version than the index claims."""
        package_bytes = _debian_package(
            "Package: chatgpt\n"
            "Version: 26.901.00000\n"
            "Architecture: amd64\n"
            "Maintainer: OpenAI <support@openai.com>\n"
        )
        with tempfile.TemporaryDirectory() as temporary:
            package = Path(temporary) / "chatgpt.deb"
            package.write_bytes(package_bytes)
            digest = hashlib.sha256(package_bytes).hexdigest()
            discovered = update._DiscoveredSource(
                version="26.901.41600",
                url=_source("x86_64-linux").url,
                expected_size=len(package_bytes),
                published_sha256=digest,
            )
            prefetched = update._PrefetchedSource(
                hash_sri=update._hex_sha256_to_sri(digest),
                store_path=package,
            )

            with (
                contextlib.redirect_stderr(io.StringIO()),
                self.assertRaises(SystemExit),
            ):
                update._validate_prefetched_source(
                    "x86_64-linux", discovered, prefetched
                )


if __name__ == "__main__":
    unittest.main()
