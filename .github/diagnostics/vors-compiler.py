import asyncio
import contextlib
import json
import logging
import os
import shutil
import signal
import time
from pathlib import Path

LOGGER = logging.getLogger(__name__)

ROOT = Path("diagnostic-work").resolve()
ROOT.mkdir(exist_ok=True)
SOURCE = Path.cwd()

SWIFT = shutil.which("swiftc")
if SWIFT is None:
    raise RuntimeError("Nix-selected swiftc is missing")
SDK = os.environ["SDKROOT"]
HEADER = os.environ["DIAGNOSTIC_SQLITE_HEADER"]
LIBRARY = os.environ["DIAGNOSTIC_SQLITE_LIBRARY"]
REPORT = Path(os.environ["DIAGNOSTIC_REPORT"])
REPORT.mkdir(exist_ok=True)
MAP = ROOT / "sqlite-module"
MAP.mkdir(exist_ok=True)
(MAP / "module.modulemap").write_text(
    f'module SQLite3 [system] {{\n header "{HEADER}"\n link "sqlite3"\n export *\n}}\n'
)
BASE = ["-swift-version", "5", "-target", "arm64-apple-macosx14.0", "-sdk", SDK]
SQLITE = [
    "-I",
    str(MAP),
    "-L",
    LIBRARY,
    "-lsqlite3",
    "-Xlinker",
    "-rpath",
    "-Xlinker",
    LIBRARY,
]
APP = sorted(
    str(p.relative_to(SOURCE)) for p in (SOURCE / "Sources/Vorssaint").rglob("*.swift")
)
ENV = os.environ.copy()
ENV["SDKROOT"] = SDK
RESULTS = []


async def terminate(process):
    if process.returncode is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        await asyncio.wait_for(asyncio.shield(process.wait()), 5)
    except TimeoutError, asyncio.CancelledError:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGKILL)
        await process.wait()


async def spawn(*args, **kwargs):
    pending = asyncio.create_task(asyncio.create_subprocess_exec(*args, **kwargs))
    try:
        return await asyncio.shield(pending)
    except asyncio.CancelledError:
        process = await pending
        await terminate(process)
        raise


async def run(name, args, limit, executable=None):
    start = time.monotonic()
    command = [executable or SWIFT, *args]
    LOGGER.info("start %s deadline=%ss", name, limit)
    with (ROOT / (name + ".log")).open("wb") as log:
        process = await spawn(
            *command,
            cwd=SOURCE,
            env=ENV,
            stdout=log,
            stderr=asyncio.subprocess.STDOUT,
            start_new_session=True,
        )
        timed_out = False
        try:
            await asyncio.wait_for(process.wait(), limit)
        except TimeoutError:
            timed_out = True
            LOGGER.info("%s exceeded its deadline", name)
        finally:
            await terminate(process)
    result = {
        "name": name,
        "elapsed": round(time.monotonic() - start, 3),
        "returncode": process.returncode,
        "timed_out": timed_out,
        "command": [
            part.replace(str(SOURCE), "<source>").replace(
                str(ROOT), "<diagnostic-work>"
            )
            for part in command
        ],
    }
    RESULTS.append(result)
    (ROOT / "results.json").write_text(json.dumps(RESULTS, indent=2) + "\n")
    LOGGER.info("%s", json.dumps({k: v for k, v in result.items() if k != "command"}))
    return result


async def main():
    loop = asyncio.get_running_loop()
    owner = asyncio.current_task()
    for sig in [signal.SIGINT, signal.SIGTERM, signal.SIGHUP]:
        loop.add_signal_handler(sig, owner.cancel)
    old_cache = ROOT / "old-cache"
    new_cache = ROOT / "new-cache"
    shared_cache = ROOT / "shared-cache"
    for cache in [old_cache, new_cache, shared_cache]:
        cache.mkdir(exist_ok=True)
    app = ["-I", "Sources/VMStatisticsCompat", "-I", "Sources/HIDEventSystem", *APP]
    diagnostics = ["-v", "-Xfrontend", "-debug-time-function-bodies"]
    await run(
        "old-typecheck",
        [*BASE, "-typecheck", "-module-cache-path", str(old_cache), *diagnostics, *app],
        120,
    )
    await run(
        "new-typecheck-isolated",
        [
            *BASE,
            "-typecheck",
            "-module-cache-path",
            str(new_cache),
            *SQLITE,
            *diagnostics,
            *app,
        ],
        120,
    )
    smoke = await run(
        "sqlite-smoke",
        [
            *BASE,
            "-module-cache-path",
            str(shared_cache),
            *SQLITE,
            os.environ["DIAGNOSTIC_SQLITE_SMOKE"],
            "-o",
            str(ROOT / "check-sqlite"),
        ],
        45,
    )
    if smoke["returncode"] != 0:
        return
    runtime = await run(
        "sqlite-smoke-runtime", [], 10, executable=str(ROOT / "check-sqlite")
    )
    if runtime["returncode"] != 0:
        return
    await run(
        "new-typecheck-primed",
        [
            *BASE,
            "-typecheck",
            "-module-cache-path",
            str(shared_cache),
            *SQLITE,
            *diagnostics,
            *app,
        ],
        120,
    )
    await run(
        "old-optimized",
        [
            *BASE,
            "-O",
            "-module-cache-path",
            str(old_cache),
            *diagnostics,
            *app,
            "-o",
            str(ROOT / "old-app"),
        ],
        360,
    )
    await run(
        "new-optimized-isolated",
        [
            *BASE,
            "-O",
            "-module-cache-path",
            str(new_cache),
            *SQLITE,
            *diagnostics,
            *app,
            "-o",
            str(ROOT / "new-app"),
        ],
        360,
    )


def publish_reports():
    # Publish only compiler logs and classified results, never app binaries,
    # source trees, caches, environment dumps or process listings.
    for path in ROOT.glob("*.log"):
        text = path.read_text(errors="replace").replace(str(SOURCE), "<source>")
        text = text.replace(str(ROOT), "<diagnostic-work>")
        (REPORT / path.name).write_text(text)
    if RESULTS:
        (REPORT / "results.json").write_text(json.dumps(RESULTS, indent=2) + "\n")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    try:
        asyncio.run(main())
    finally:
        publish_reports()
