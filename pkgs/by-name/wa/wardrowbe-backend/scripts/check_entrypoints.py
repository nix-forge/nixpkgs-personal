"""Check application imports and Redis socket configuration."""

import importlib

for name in ("app.main", "app.workers.worker", "app.workers.image_worker"):
    importlib.import_module(name)
settings = importlib.import_module("app.workers.settings")
assert (
    settings.get_redis_settings().unix_socket_path == "/run/redis-wardrowbe/redis.sock"
)
