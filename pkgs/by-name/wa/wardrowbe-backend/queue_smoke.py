"""Exercise ARQ over an owned Unix socket using startup and task notifications."""

import asyncio
import sys
from pathlib import Path

# The recipe provides these modules; the tooling shell intentionally does not.
from arq import create_pool  # ty: ignore[import-not-found]
from arq.connections import RedisSettings  # ty: ignore[import-not-found]
from arq.worker import Worker  # ty: ignore[import-not-found]


async def double(_ctx, value):  # ruff: ignore[unused-async] - ARQ requires a coroutine function.
    return value * 2


async def exercise(socket_path):
    settings = RedisSettings(unix_socket_path=socket_path, conn_retries=0)
    pool = await create_pool(settings)
    expected = 42
    worker = Worker(functions=[double], redis_pool=pool, handle_signals=False)
    worker.ctx["redis"] = pool
    try:
        job = await pool.enqueue_job("double", 21)
        if job is None:
            raise RuntimeError("ARQ did not enqueue the test job")
        # This fixture owns one already enqueued job. Use the worker's public
        # execution entry point and await its tasks instead of polling the queue.
        await worker.start_jobs([job.job_id.encode()])
        await asyncio.gather(*worker.tasks.values())
        result = await job.result_info()
        if result is None or not result.success or result.result != expected:
            raise RuntimeError("ARQ returned an incorrect job result")
        if worker.jobs_complete != 1 or worker.jobs_failed:
            raise RuntimeError("ARQ did not complete exactly one successful job")
    finally:
        await worker.close()
        await pool.aclose()


async def main():
    executable, socket_path, logfile = sys.argv[1:]
    server = await asyncio.create_subprocess_exec(
        executable,
        "--port",
        "0",
        "--unixsocket",
        socket_path,
        "--save",
        "",
        "--appendonly",
        "no",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        if server.stdout is None:
            raise RuntimeError("Valkey startup output is unavailable")
        async with asyncio.timeout(15):
            with Path(logfile).open("wb") as output:  # ruff: ignore[blocking-open-call-in-async-function] - Small fixture diagnostics; startup and task waits are asynchronous.
                while line := await server.stdout.readline():
                    output.write(line)
                    if b"Ready to accept connections" in line:
                        break
                else:
                    raise RuntimeError("Valkey exited before readiness")
            await exercise(socket_path)
    finally:
        if server.returncode is None:
            server.terminate()
            try:
                await asyncio.wait_for(server.wait(), 5)
            except TimeoutError:
                server.kill()
                await server.wait()


asyncio.run(main())
