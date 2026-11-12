# shellcheck shell=bash
# Reject a stale version pin after source updates, without importing the source.
test "$(cat VERSION)" = "@source_version@"
cp @bar_icon_policy_h@ src/shell/bar/widgets/bar_icon_policy.h

substituteInPlace meson.build \
  --replace-fail "_git_revision_config.set('VCS_TAG', 'unknown')" "_git_revision_config.set('VCS_TAG', '@source_revision@')" \
  --replace-fail "fallback: 'unknown'," "fallback: '@source_revision@',"
