# shellcheck shell=bash
cp @browser_auth_mts@ src/utils/browser-auth.mts
cp @articleImageGallery_tsx@ src/components/Article/ArticleImageGallery.tsx
cp @media_policy_mts@ src/utils/media-policy.mts
cp @authState_mts@ src/store/authState.mts
substituteInPlace src/utils/settings-schema.js \
  --replace-fail 'const DEFAULT_SETTINGS = Object.fromEntries(' \
  'const UPSTREAM_SETTINGS = Object.fromEntries('
# Preferences are defaults, not policy; existing user choices still win.
substituteInPlace src/utils/settings-schema.js \
  --replace-fail 'export const createDefaultSettings' \
  @defaultSettings@
