# shellcheck shell=bash
runHook preCheck
node --test @auth_test_mts@
cp @images_test_mts@ images.test.mts
cp @typescript_config@ local-tsconfig.json
tsc --project local-tsconfig.json
oxlint --type-aware --deny-warnings --tsconfig local-tsconfig.json --config @lint_config@ \
  src/utils/browser-auth.mts src/utils/media-policy.mts src/store/authState.mts \
  src/components/Article/ArticleImageGallery.tsx images.test.mts
node --test images.test.mts
runHook postCheck
