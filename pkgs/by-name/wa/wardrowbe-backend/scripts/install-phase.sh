# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
app="$out/libexec/wardrowbe-backend"
mkdir -p "$app" "$out/bin" "$out/share/doc/wardrowbe"
cp -R backend/app backend/migrations backend/alembic.ini "$app/"
cp LICENSE "$out/share/doc/wardrowbe/LICENSE"
cp backend/requirements.txt "$out/share/doc/wardrowbe/requirements.txt"
makeWrapper @pythonEnv@/bin/uvicorn "$out/bin/wardrowbe-backend" \
  --add-flags 'app.main:app --host 127.0.0.1' \
  --set PYTHONPATH "$app"
makeWrapper @pythonEnv@/bin/arq "$out/bin/wardrowbe-worker" \
  --add-flags app.workers.worker.WorkerSettings \
  --set PYTHONPATH "$app"
makeWrapper @pythonEnv@/bin/arq "$out/bin/wardrowbe-image-worker" \
  --add-flags app.workers.image_worker.ImageWorkerSettings \
  --set PYTHONPATH "$app"
makeWrapper @pythonEnv@/bin/python "$out/bin/wardrowbe-migrate" \
  --add-flags "-m app.planning.migrate $app/alembic.ini" \
  --set PYTHONPATH "$app"
runHook postInstall
