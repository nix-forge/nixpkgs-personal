# shellcheck shell=bash
node -e 'const p = JSON.parse(require("fs").readFileSync("package-lock.json")); if (p.packages["node_modules/@lydell/node-pty"].version !== process.argv[1]) throw new Error("Native PTY source does not match the locked dependency")' '@ptyVersion@'
pty_dir="node_modules/@ptyPackage@"
test -d "$pty_dir"
install -m755 @nodePty@/pty.node "$pty_dir/pty.node"
if [[ -f @nodePty@/spawn-helper ]]; then
  install -m755 @nodePty@/spawn-helper "$pty_dir/spawn-helper"
fi

@tsrsPatch@
