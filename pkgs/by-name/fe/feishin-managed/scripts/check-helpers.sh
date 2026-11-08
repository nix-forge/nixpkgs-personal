# shellcheck shell=bash
runHook preCheck
npm run lint
npm run format:check
node --test --test-timeout=30000 dist/managed-login.test.cjs dist/mpv-readiness.test.cjs
runHook postCheck
