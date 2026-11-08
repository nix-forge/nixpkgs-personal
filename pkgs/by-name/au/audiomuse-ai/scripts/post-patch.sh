# shellcheck shell=bash
substituteInPlace service_roles.py \
  --replace-fail "FLASK_BIND_HOST = '0.0.0.0'" \
  "FLASK_BIND_HOST = os.environ.get('AUDIOMUSE_HOST', '127.0.0.1')" \
  --replace-fail "FLASK_BIND_PORT = 8000" \
  "FLASK_BIND_PORT = int(os.environ.get('AUDIOMUSE_PORT', '8000'))"
