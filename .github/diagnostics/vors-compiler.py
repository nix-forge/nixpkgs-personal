import asyncio
import contextlib
import json
import logging
import os
import shutil
import signal
import sys
import time
from pathlib import Path

LOGGER = logging.getLogger(__name__)
SCRIPT = str(Path(__file__).resolve())

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
    # The supervisor ignores TERM and remains the live group leader after the
    # compiler exits. Its PID therefore anchors ownership until our final KILL.
    # Unexpected supervisor exit makes group ownership unprovable: fail closed.
    if process.returncode is not None:
        return
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGTERM)
    try:
        await asyncio.sleep(0.25)
    finally:
        if process.returncode is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
        await process.wait()


async def completed(reader):
    message = await reader.readline()
    if not message:
        raise RuntimeError("Owned compiler supervisor exited without a result")
    return json.loads(message)["returncode"]


def supervise(result_fd, command):
    # Preserve the group leader even if the compiler leaves live descendants.
    # Only the compiler receives normal signal dispositions.
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        signal.signal(sig, signal.SIG_IGN)

    child = os.fork()
    if child == 0:
        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(sig, signal.SIG_DFL)
        os.close(result_fd)
        # Fixed owned compiler arguments, no shell or upstream helper execution.
        os.execvpe(command[0], command, os.environ)  # ruff: ignore[start-process-with-no-shell] - owned argv, no shell
    _, status = os.waitpid(child, 0)
    os.write(
        result_fd,
        (json.dumps({"returncode": os.waitstatus_to_exitcode(status)}) + "\n").encode(),
    )
    os.close(result_fd)
    while True:
        signal.pause()


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
    returncode = None
    read_fd, write_fd = os.pipe()
    reader = asyncio.StreamReader(limit=1024)
    protocol = asyncio.StreamReaderProtocol(reader)
    transport = None
    try:
        transport, _ = await asyncio.get_running_loop().connect_read_pipe(
            lambda: protocol, os.fdopen(read_fd, "rb", buffering=0)
        )
        with (ROOT / (name + ".log")).open("wb") as log:
            try:
                process = await spawn(
                    sys.executable,
                    SCRIPT,
                    "--supervise",
                    str(write_fd),
                    *command,
                    cwd=SOURCE,
                    env=ENV,
                    stdout=log,
                    stderr=asyncio.subprocess.STDOUT,
                    start_new_session=True,
                    pass_fds=(write_fd,),
                )
            finally:
                os.close(write_fd)
                write_fd = None
            timed_out = False
            try:
                returncode = await asyncio.wait_for(completed(reader), limit)
            except TimeoutError:
                timed_out = True
                LOGGER.info("%s exceeded its deadline", name)
            finally:
                await terminate(process)
    finally:
        if write_fd is not None:
            os.close(write_fd)
        if transport is not None:
            transport.close()
        else:
            with contextlib.suppress(OSError):
                os.close(read_fd)
    result = {
        "name": name,
        "elapsed": round(time.monotonic() - start, 3),
        "returncode": returncode,
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


if __name__ == "__main__" and len(sys.argv) > 1 and sys.argv[1] == "--supervise":
    supervise(int(sys.argv[2]), sys.argv[3:])
elif __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    try:
        asyncio.run(main())
    finally:
        publish_reports()
