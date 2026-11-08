"""Serialize Feishin's mpv restarts and wait for each old child to exit."""

import sys
from pathlib import Path

EXPECTED_CLEANUP_SITES = 2


def fragment(name: str) -> str:
    """Read an exact bundle anchor or replacement fragment.

    Returns:
        The fragment without its source-file terminal newline.

    """
    return (
        (Path(__file__).with_name("mpv-fragments") / name)
        .read_text(encoding="utf-8")
        .removesuffix("\n")
    )


def replace_once(source: str, old: str, new: str, name: str) -> str:
    count = source.count(old)
    if count != 1:
        raise ValueError(f"Expected one {name} anchor, found {count}")
    return source.replace(old, new, 1)


main_path = Path(sys.argv[1]) / "out/main/index.js"
main = main_path.read_text()
main = replace_once(
    main,
    "const mpvProcess = mpv.process || mpv.mpvProcess;",
    "const mpvProcess = mpv.mpvPlayer || mpv.process || mpv.mpvProcess;",
    "node-mpv child process",
)
if (
    main.count("const mpvProcess = instance.process || instance.mpvProcess;")
    != EXPECTED_CLEANUP_SITES
):
    raise ValueError("Expected two cleanup child process anchors")
main = main.replace(
    "const mpvProcess = instance.process || instance.mpvProcess;",
    "const mpvProcess = instance.mpvPlayer || instance.process || instance.mpvProcess;",
)
main = replace_once(
    main,
    fragment("socket-cleanup-before.js.in"),
    fragment("socket-cleanup-after.js.in"),
    "wait for old mpv child",
)
main = replace_once(
    main,
    "let mpvCreatePromise = null;",
    fragment("transition-state.js.in"),
    "mpv transition lock",
)
main = replace_once(
    main,
    fragment("before-quit-cleanup-before.js.in"),
    fragment("before-quit-cleanup-after.js.in"),
    "quitting during mpv creation",
)
if main.count("  await cleanupMpv(true);") != EXPECTED_CLEANUP_SITES:
    raise ValueError("Expected two signal cleanup anchors")
main = main.replace("  await cleanupMpv(true);", fragment("signal-cleanup.js.in"))
main = replace_once(
    main,
    fragment("restart-handler-before.js.in"),
    fragment("restart-handler-after.js.in"),
    "serialized mpv restart",
)
main = replace_once(
    main,
    fragment("restart-handler-close-before.js.in"),
    fragment("restart-handler-close-after.js.in"),
    "restart transition close",
)
main = replace_once(
    main,
    fragment("initialize-handler-before.js.in"),
    fragment("initialize-handler-after.js.in"),
    "serialized mpv initialize",
)
main = replace_once(
    main,
    fragment("initialize-handler-close-before.js.in"),
    fragment("initialize-handler-close-after.js.in"),
    "initialize transition close",
)
main = replace_once(
    main,
    'require$$0.ipcMain.on("player-quit", async () => {',
    'require$$0.ipcMain.on("player-quit", async () => mpvTransition = mpvTransition.then(async () => {',
    "serialized player quit",
)
main = replace_once(
    main,
    fragment("player-quit-stop-before.js.in"),
    fragment("player-quit-stop-after.js.in"),
    "avoid unbounded stop before quitting",
)
main = replace_once(
    main,
    fragment("player-quit-handler-close-before.js.in"),
    fragment("player-quit-handler-close-after.js.in"),
    "quit transition close",
)
# The volume control enumerates devices during engine initialization. Its
# temporary mpv shares the playback socket, so it must finish and remove that
# socket before initialization starts a persistent child.
main = replace_once(
    main,
    fragment("audio-device-handler-before.js.in"),
    fragment("audio-device-handler-after.js.in"),
    "serialized audio device discovery",
)
main = replace_once(
    main,
    fragment("audio-device-handler-close-before.js.in"),
    fragment("audio-device-handler-close-after.js.in"),
    "audio device transition close",
)
main = replace_once(
    main,
    "const QUIT_TIMEOUT_MS = 3e3;",
    fragment("audio-device-query-timeout.js.in"),
    "bounded audio device query",
)
main = replace_once(
    main,
    'const deviceList = await mpvToUse.getProperty("audio-device-list");',
    "const deviceList = await mpvDeviceQuery(mpvToUse);",
    "audio device query timeout",
)
# A socket inode can precede listen(). The owning start promise certifies IPC
# connection completion; report that lifecycle to the artwork observer.
main = replace_once(
    main,
    "const createMpv = async (data) => {",
    fragment("ipc-starting.js.in"),
    "IPC startup producer",
)
main = replace_once(
    main,
    "    await mpv.start();",
    fragment("ipc-ready.js.in"),
    "IPC readiness producer",
)
main = replace_once(
    main,
    "const quit$1 = async (instance) => {",
    fragment("ipc-stopping.js.in"),
    "IPC stop producer",
)

main_path.write_text(main)
