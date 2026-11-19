# shellcheck shell=bash
# Built-in model installation must work without curl in the user's profile.
substituteInPlace crates/engine/src/analysis/models.rs crates/engine/src/system/library.rs \
  --replace-fail 'Command::new("curl")' 'Command::new("@curl@")'
