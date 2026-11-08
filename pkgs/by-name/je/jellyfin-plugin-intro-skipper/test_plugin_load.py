"""Reject plugin/API metadata that does not prove real selected compatibility."""

import asyncio
import json
import secrets
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest.mock import AsyncMock

import check_jellyfin_plugin as checker


class PluginTests(unittest.TestCase):
    def plugin(self) -> dict[str, object]:
        return {
            "Id": checker.PLUGIN_ID,
            "Name": "Intro Skipper",
            "Version": "12.0.5.0",
            "Status": "Active",
        }

    def test_exact_active_plugin(self) -> None:
        checker.validate_plugins([self.plugin()], "12.0.5.0")

    def test_selected_jellyfin_compact_guid_format(self) -> None:
        compact = checker.PLUGIN_ID.replace("-", "")
        checker.validate_plugins([self.plugin() | {"Id": compact}], "12.0.5.0")
        checker.validate_plugins([self.plugin() | {"Id": compact.upper()}], "12.0.5.0")
        with self.assertRaises(ValueError):
            checker.validate_plugins(
                [self.plugin(), self.plugin() | {"Id": compact}], "12.0.5.0"
            )

    def test_malformed_guid_does_not_match_identity(self) -> None:
        for identity in (
            None,
            42,
            checker.PLUGIN_ID + "-backup",
            "{" + checker.PLUGIN_ID + "}",
        ):
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                checker.validate_plugins([self.plugin() | {"Id": identity}], "12.0.5.0")

    def test_missing_and_duplicate_identity(self) -> None:
        for records in ([], [{"Id": "another-plugin"}], [self.plugin(), self.plugin()]):
            with (
                self.subTest(records=records),
                self.assertRaises((ValueError, TypeError)),
            ):
                checker.validate_plugins(records, "12.0.5.0")

    def test_malfunctioned_unsupported_and_disabled_statuses(self) -> None:
        for status in ("Malfunctioned", "NotSupported", "Disabled", None):
            with self.subTest(status=status), self.assertRaises(ValueError):
                checker.validate_plugins(
                    [self.plugin() | {"Status": status}], "12.0.5.0"
                )

    def test_wrong_name_version_and_api_shape(self) -> None:
        for records in (
            {},
            [self.plugin() | {"Name": "different"}],
            [self.plugin() | {"Version": "12.0.4.0"}],
            [self.plugin() | {"Version": 12}],
        ):
            with (
                self.subTest(records=records),
                self.assertRaises((ValueError, TypeError)),
            ):
                checker.validate_plugins(records, "12.0.5.0")

    def test_version_padding_preserves_actual_release_identity(self) -> None:
        self.assertEqual(
            checker.version_tuple("12.2"), checker.version_tuple("12.2.0.0")
        )
        self.assertNotEqual(
            checker.version_tuple("12.1"), checker.version_tuple("12.2")
        )
        for version in ("12.2-preview", "12", "12.2.0.0.1"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                checker.version_tuple(version)

    def test_exact_assembly_path_and_version(self) -> None:
        dll = Path("/fixture/IntroSkipper.dll")
        good = f"Loaded assembly IntroSkipper, Version=12.0.5.0, Culture=neutral from {dll}"
        checker.validate_log(good, dll, "12.0.5.0")
        for text in (
            "Startup complete",
            good.replace("12.0.5.0", "12.0.4.0"),
            good.replace("/fixture/", "/different/"),
            good + ".backup",
        ):
            with self.subTest(text=text), self.assertRaises(ValueError):
                checker.validate_log(text, dll, "12.0.5.0")

    def test_healthy_server_does_not_admit_load_or_dependency_failure(self) -> None:
        dll = Path("/fixture/IntroSkipper.dll")
        good = f"Loaded assembly IntroSkipper, Version=12.0.5.0, Culture=neutral from {dll}"
        for failure in (
            "Failed to load assembly",
            "Error registering plugin services",
            "ReflectionTypeLoadException",
            "MissingMethodException",
            "Unable to resolve service for type",
            "Unexpected error while checking the installed FFmpeg version",
        ):
            with self.subTest(failure=failure), self.assertRaises(ValueError):
                checker.validate_log(good + "\n" + failure, dll, "12.0.5.0")


class StartupTests(unittest.TestCase):
    def test_fresh_server_admin_is_initialized_before_update(self) -> None:
        async def exercise() -> None:
            initialized = False
            configured = False
            completed = False
            seen_password = ""
            api = checker.Api(1)

            def request(
                path: str, payload: object = None, token: str | None = None
            ) -> bytes:
                nonlocal initialized, configured, completed, seen_password
                if path == "/Startup/User" and payload is None:
                    initialized = True
                    return b'{"Name":"initial-user"}'
                if path == "/Startup/User":
                    self.assertTrue(
                        initialized, "selected server requires GET initialization"
                    )
                    self.assertIsInstance(payload, dict)
                    if not isinstance(payload, dict):
                        raise TypeError("startup payload must be an object")
                    self.assertEqual(payload["Name"], "plugin-check")
                    self.assertIsInstance(payload["Password"], str)
                    seen_password = str(payload["Password"])
                    self.assertTrue(seen_password)
                    configured = True
                    return b""
                if path == "/Startup/Complete":
                    self.assertTrue(configured)
                    completed = True
                    return b""
                if path == "/Users/AuthenticateByName":
                    self.assertTrue(completed)
                    self.assertEqual(
                        payload, {"Username": "plugin-check", "Pw": seen_password}
                    )
                    return json.dumps({"AccessToken": "fixture-token"}).encode()
                raise AssertionError(f"unexpected API operation: {path}")

            api.request = AsyncMock(side_effect=request)
            self.assertEqual(await api.authenticate(), "fixture-token")

        asyncio.run(exercise())


class AuthorizationTests(unittest.TestCase):
    def test_actual_request_uses_supported_token_header_without_legacy_auth(self):
        seen = []
        fixture_token = secrets.token_hex(12)

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                authorization = self.headers.get("Authorization", "")
                seen.append((authorization, self.headers.get("X-Emby-Token")))
                if f', Token="{fixture_token}"' not in authorization:
                    self.send_response(401)
                else:
                    self.send_response(200)
                self.end_headers()
                self.wfile.write(b"[]")

            def log_message(self, *args: object, **kwargs: object) -> None:
                pass

        with HTTPServer(("127.0.0.1", 0), Handler) as server:
            server.timeout = 5
            thread = threading.Thread(target=server.handle_request)
            thread.start()
            try:
                result = asyncio.run(
                    checker.Api(server.server_port).request(
                        "/Plugins", token=fixture_token
                    )
                )
                self.assertEqual(result, b"[]")
                self.assertEqual(len(seen), 1)
                self.assertIsNone(seen[0][1])
                self.assertIn('Client="Package check"', seen[0][0])
            finally:
                thread.join(timeout=5)
                self.assertFalse(thread.is_alive())


class LifecycleTests(unittest.TestCase):
    def executable(self, root: Path, code: str) -> Path:
        command = root / "fixture-server"
        command.write_text("#!" + sys.executable + "\n" + code)
        command.chmod(0o755)
        return command

    def test_retained_stdout_descendant_is_terminated_after_leader_exit(self) -> None:
        async def exercise(root: Path) -> None:
            marker = root / "descendant-stopped"
            command = self.executable(
                root,
                f"""import os, signal
ready_read, ready_write = os.pipe()
if os.fork():
    os.close(ready_write)
    os.read(ready_read, 1)
    os._exit(0)
os.close(ready_read)
def stop(signum, frame):
    with open({str(marker)!r}, 'w') as output:
        output.write('terminated')
    os._exit(0)
signal.signal(signal.SIGTERM, stop)
print('descendant ready', flush=True)
os.write(ready_write, b'1')
os.close(ready_write)
signal.pause()
""",
            )
            async with checker.launch(str(command), root) as running:
                with self.assertRaisesRegex(RuntimeError, "exited during startup"):
                    await running.wait_started()
            self.assertTrue(running.exit_task.done())
            # The process-group signal reaches the descendant rather than only
            # checking the already-exited leader's returncode.
            self.assertEqual(marker.read_text(), "terminated")

        with tempfile.TemporaryDirectory() as directory:
            asyncio.run(exercise(Path(directory)))

    def test_normal_started_server_has_bounded_owned_shutdown(self) -> None:
        async def exercise(root: Path) -> None:
            marker = root / "server-stopped"
            command = self.executable(
                root,
                f"""import os, signal
def stop(signum, frame):
    with open({str(marker)!r}, 'w') as output:
        output.write('terminated')
    os._exit(0)
signal.signal(signal.SIGTERM, stop)
print('Startup complete', flush=True)
signal.pause()
""",
            )
            async with checker.launch(str(command), root) as running:
                await running.wait_started()
            self.assertEqual(running.process.returncode, 0)
            self.assertEqual(marker.read_text(), "terminated")

        with tempfile.TemporaryDirectory() as directory:
            asyncio.run(exercise(Path(directory)))

    def test_real_early_child_exit_fails_without_startup_timeout(self) -> None:
        async def exercise(root: Path) -> None:
            # Python rejects the server-specific arguments and exits immediately.
            # Exercise a real child notification, not a mocked return code.
            async with checker.launch(sys.executable, root) as running:
                with self.assertRaisesRegex(RuntimeError, "exited during startup"):
                    await running.wait_started()
                self.assertNotEqual(running.process.returncode, 0)
                self.assertFalse(running.started.is_set())

        with tempfile.TemporaryDirectory() as directory:
            asyncio.run(exercise(Path(directory)))


if __name__ == "__main__":
    unittest.main()
