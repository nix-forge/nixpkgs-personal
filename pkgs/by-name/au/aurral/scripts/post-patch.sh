# shellcheck shell=bash
# Match the security-fixed Node minor used by the release image; keep engine checks.
substituteInPlace package.json \
  --replace-fail '"node": "26.12.x"' '"node": "^26.12.0"'
# The service remains private until a consumer explicitly selects a wider bind.
substituteInPlace backend/server.ts \
  --replace-fail 'httpServer.listen(PORT, async () => {' \
  'httpServer.listen(PORT, process.env.AURRAL_HOST || "127.0.0.1", async () => {'

# Binding a host requires Node's numeric TCP-port overload, not a string path.
substituteInPlace backend/server.ts \
  --replace-fail 'const PORT = process.env.PORT || 3001;' \
  'const PORT = Number(process.env.PORT || 3001);
if (!Number.isInteger(PORT) || PORT < 0 || PORT > 65535) {
  throw new Error("PORT must be an integer between 0 and 65535");
}'
