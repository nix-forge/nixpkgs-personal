# shellcheck shell=bash
# Resolve configured fonts with target fontconfig rather than fixed host folders.
substituteInPlace crates/text/src/fonts.rs \
  --replace-fail 'Command::new("font-timeout")' 'Command::new("@timeoutExecutable@")' \
  --replace-fail '"fc-list"' '"@fontconfigExecutable@"'
