# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
cd "$out/libexec/wardrowbe-backend" || exit
export NUMBA_CACHE_DIR="$TMPDIR/numba"
export REDIS_URL=unix:///run/redis-wardrowbe/redis.sock
mkdir -p "$NUMBA_CACHE_DIR"
@pythonEnv@/bin/python @pythonCheck1@ "$out/share/doc/wardrowbe/requirements.txt"
PYTHONPATH="$PWD" @pythonEnv@/bin/python @entrypointsCheck@
check_cpu_provider=@checkCpuProvider@
if [[ $check_cpu_provider == true ]]; then
  @pythonEnv@/bin/python @cpuProviderCheck@
fi
# Upstream ONNX Runtime cannot import inside an aarch64 Linux sandbox
# without /sys CPU information. Keep its upstream exception scoped to that
# check; all Wardrowbe entry points are still imported above.
PYTHONPATH="$PWD" @pythonEnv@/bin/python "$providerSmokePath"
PYTHONPATH="$PWD" @pythonEnv@/bin/python "$browserAuthSmokePath"
@pythonEnv@/bin/python "$queueSmokePath" @valkey@/bin/valkey-server \
  "$TMPDIR/queue.sock" "$TMPDIR/queue.log"
# Exercise persistence, ownership, review history and both independent
# migration ledgers against a disposable database, never a deployment DB.
mkdir -p "$TMPDIR/planning-pg"
initdb -D "$TMPDIR/planning-db" --username=wardrowbe_test --auth=trust \
  --no-locale --encoding=UTF8 >"$TMPDIR/planning-init.log"
pg_ctl -D "$TMPDIR/planning-db" -l "$TMPDIR/planning-pg.log" \
  -o "-k $TMPDIR/planning-pg -c listen_addresses=" -w start
trap 'pg_ctl -D "$TMPDIR/planning-db" -m immediate -w stop >/dev/null 2>&1 || true' EXIT
createdb --host "$TMPDIR/planning-pg" --username wardrowbe_test wardrowbe_planning_test
export DATABASE_URL="postgresql+asyncpg://wardrowbe_test@localhost/wardrowbe_planning_test?host=$TMPDIR/planning-pg"
export PLANNING_TEST_DATABASE_URL="$DATABASE_URL"
export STORAGE_PATH="$TMPDIR/planning-uploads"
"$out/bin/wardrowbe-migrate"
"$out/bin/wardrowbe-migrate"
PYTHONPATH="$PWD" @pythonEnv@/bin/python "$paginationSmokePath"
PYTHONPATH="$PWD" @pythonEnv@/bin/python -m unittest discover -s app/planning/tests -v
pg_ctl -D "$TMPDIR/planning-db" -m fast -w stop
trap - EXIT
runHook postInstallCheck
