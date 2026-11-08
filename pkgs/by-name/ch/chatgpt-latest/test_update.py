"""Check release selection, integrity and publication without live services."""

from __future__ import annotations

import base64
import gzip
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.request import Request

import release_support
import update
from defusedxml.common import DefusedXmlException

CHECKSUM = "1" * 64
HASH = "sha256-" + base64.b64encode(bytes.fromhex(CHECKSUM)).decode()


def deb(version="26.1007.71326", architecture="amd64", **extra) -> bytes:
    fields = {
        "Package": "chatgpt",
        "Architecture": architecture,
        "Version": version,
        "Filename": f"pool/main/c/chatgpt/chatgpt_{version}_{architecture}.deb",
        "SHA256": CHECKSUM,
        "Size": "10",
        **extra,
    }
    return (
        "\n".join(f"{key}: {value}" for key, value in fields.items()) + "\n\n"
    ).encode()


def appcast(version="26.1007.71326", **attributes) -> bytes:
    enclosure = {
        "url": f"{update.BASE}/ChatGPT-darwin-arm64-{version}.zip",
        "length": "10",
        **attributes,
    }
    attrs = " ".join(f'{key}="{value}"' for key, value in enclosure.items())
    return (
        f'<rss xmlns:sparkle="{update.SPARKLE[1:-1]}"><channel><item>'
        f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>"
        "<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"
        f"<enclosure {attrs}/></item></channel></rss>"
    ).encode()


class FeedTests(unittest.TestCase):
    def test_linux_selects_newest_matching_package_independent_of_order(self) -> None:
        data = deb("26.1007.71326") + deb("26.1002.51308") + deb(Package="other")
        selected = update.linux_release(gzip.compress(data), "amd64")
        self.assertEqual(selected.version, "26.1007.71326")
        self.assertEqual(selected.expected_hash, HASH)
        self.assertTrue(selected.url.endswith("chatgpt_26.1007.71326_amd64.deb"))

    def test_architectures_are_selected_independently(self) -> None:
        selected = update.linux_release(
            gzip.compress(deb("26.1002.51308", "arm64")), "arm64"
        )
        self.assertEqual(selected.version, "26.1002.51308")

    def test_duplicate_release_disagreement_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "Conflicting"):
            update.linux_release(gzip.compress(deb() + deb(Size="11")), "amd64")

    def test_duplicate_fields_are_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicate"):
            update.linux_release(
                gzip.compress(deb() + b"Package: chatgpt\nPackage: other\n"), "amd64"
            )

    def test_download_path_and_checksum_are_validated(self) -> None:
        for fields in [
            {"Filename": "../../outside.deb"},
            {"SHA256": "wrong"},
            {"Size": "0"},
        ]:
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                update.linux_release(gzip.compress(deb(**fields)), "amd64")

    def test_decompressed_metadata_is_bounded(self) -> None:
        with (
            patch.object(update, "MAX_METADATA", 4),
            self.assertRaisesRegex(ValueError, "size limit"),
        ):
            update.linux_release(gzip.compress(b"a" * 5), "amd64")

    def test_darwin_uses_full_vendor_archive(self) -> None:
        selected = update.darwin_release(appcast())
        self.assertEqual(selected.version, "26.1007.71326")
        self.assertEqual(selected.size, 10)

    def test_darwin_rejects_external_artifacts(self) -> None:
        with self.assertRaisesRegex(ValueError, "URL"):
            update.darwin_release(appcast(url="https://other.example/app.zip"))

    def test_xml_entities_are_rejected(self) -> None:
        with self.assertRaises(DefusedXmlException):
            update.darwin_release(
                b'<!DOCTYPE rss [<!ENTITY test "payload">]><rss>&test;</rss>'
            )


class CandidateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.release = update.Release(
            "26.1007.71326", f"{update.BASE}/archive.zip", 10, HASH
        )
        self.current = {
            "platform": {
                "version": "26.1002.51308",
                "src": {"url": "old", "hash": HASH},
            }
        }

    def test_downgrade_stops_before_download(self) -> None:
        self.current["platform"]["version"] = "26.1008.1"
        with (
            patch.object(update, "prefetch") as fetch,
            self.assertRaisesRegex(ValueError, "downgrade"),
        ):
            update.candidate(self.current, {"platform": self.release})
        fetch.assert_not_called()

    def test_size_or_checksum_failure_prevents_publication(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            artifact = Path(directory) / "artifact"
            artifact.write_bytes(b"x" * 10)
            with patch.object(update, "prefetch", return_value=(HASH, artifact)):
                result = update.candidate(self.current, {"platform": self.release})
                self.assertEqual(result["platform"]["src"]["hash"], HASH)
            with (
                patch.object(update, "prefetch", return_value=("wrong", artifact)),
                self.assertRaisesRegex(ValueError, "checksum"),
            ):
                update.candidate(self.current, {"platform": self.release})
            artifact.write_bytes(b"short")
            with (
                patch.object(update, "prefetch", return_value=(HASH, artifact)),
                self.assertRaisesRegex(ValueError, "size"),
            ):
                update.candidate(self.current, {"platform": self.release})

    def test_missing_architecture_is_not_a_partial_update(self) -> None:
        with self.assertRaisesRegex(ValueError, "every supported"):
            update.candidate(self.current, {})

    def test_same_version_changed_checksum_is_rejected(self) -> None:
        self.current["platform"] = {
            "version": self.release.version,
            "src": {"url": self.release.url, "hash": "changed"},
        }
        with self.assertRaisesRegex(ValueError, "changed checksum"):
            update.candidate(self.current, {"platform": self.release})


class PublicationTests(unittest.TestCase):
    def test_preview_and_failure_leave_source_bytes_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.nix"
            source.write_bytes(b"original")
            with (
                patch.object(release_support, "load_pins", return_value={}),
                patch.object(
                    release_support, "run", return_value=Mock(stdout="candidate")
                ),
                patch("sys.stdout", new_callable=io.StringIO),
            ):
                release_support.publish(
                    source, b"original", {"version": "1.2.3"}, dry_run=True
                )
            self.assertEqual(source.read_bytes(), b"original")
            with (
                patch.object(release_support, "load_pins", return_value={}),
                patch.object(
                    release_support, "run", side_effect=ValueError("format failed")
                ),
                self.assertRaisesRegex(ValueError, "format failed"),
            ):
                release_support.publish(
                    source, b"original", {"version": "1.2.3"}, dry_run=False
                )
            self.assertEqual(source.read_bytes(), b"original")

    def test_concurrent_edits_are_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.nix"
            source.write_bytes(b"edited")
            with self.assertRaisesRegex(ValueError, "changed while"):
                release_support.publish(source, b"original", {}, dry_run=False)

    def test_edit_during_formatting_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "source.nix"
            source.write_bytes(b"original")

            def formatter(*_args, **_kwargs):
                source.write_bytes(b"concurrent edit")
                return Mock(stdout="candidate")

            with (
                patch.object(release_support, "load_pins", return_value={}),
                patch.object(release_support, "run", side_effect=formatter),
                patch("sys.stdout", new_callable=io.StringIO),
                self.assertRaisesRegex(ValueError, "changed while"),
            ):
                release_support.publish(
                    source, b"original", {"version": "1.2.3"}, dry_run=False
                )
            self.assertEqual(source.read_bytes(), b"concurrent edit")

    def test_untrusted_metadata_origins_never_reach_network(self) -> None:
        with (
            patch.object(release_support, "build_opener") as opener,
            self.assertRaisesRegex(ValueError, "HTTPS origin"),
        ):
            release_support.metadata("file:///etc/passwd")
        opener.assert_not_called()

    def test_redirects_keep_metadata_on_its_authenticated_origin(self) -> None:
        handler = release_support.SameOriginRedirect()
        request = Request("https://api.github.com/repos/openai/codex/releases/latest")
        for target in [
            "http://api.github.com/releases",
            "https://other.example/releases",
        ]:
            with self.subTest(target=target), self.assertRaises(ValueError):
                handler.redirect_request(request, None, 302, "Found", {}, target)
        redirected = handler.redirect_request(
            request, None, 302, "Found", {}, "https://api.github.com/releases"
        )
        self.assertEqual(redirected.full_url, "https://api.github.com/releases")

    def test_nix_rendering_escapes_interpolation(self) -> None:
        self.assertIn(r"\${payload}", release_support.render({"value": "${payload}"}))


if __name__ == "__main__":
    unittest.main()
