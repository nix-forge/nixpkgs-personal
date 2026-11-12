# shellcheck shell=bash
runHook preCheck
npm run typecheck
npm run lint
npm run format:check
npm test
runHook postCheck
