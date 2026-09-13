{ lib, ... }: {
  perSystem =
    { config, pkgs, ... }:
    let
      updaterSource = lib.fileset.toSource {
        root = ../..;
        fileset = ../../pkgs/by-name/op/openai-codex-desktop;
      };
      codexDesktop = config.packages.openai-codex-desktop;
      optionalTool = pkgs.writeShellScriptBin "chatgpt-optional-tool" "exit 0";
      callerTool = pkgs.writeShellScriptBin "chatgpt-optional-tool" "exit 1";
      extraToolsDesktop = codexDesktop.override { extraPackages = [ optionalTool ]; };
    in
    lib.mkMerge [
      {
        checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          openai-codex-desktop-extra-tools = pkgs.runCommand "chatgpt-extra-tools" { } ''
            # Exercise the generated launcher setup but intercept its final exec
            # to keep GUI startup and namespaces out of the Nix build sandbox.
            for toolPath in ${pkgs.coreutils}/bin ${callerTool}/bin:${pkgs.coreutils}/bin; do
              env -i PATH="$toolPath" NIX_ENFORCE_PURITY=1 NIX_CFLAGS_COMPILE=sentinel \
                ${pkgs.bash}/bin/bash -euc '
                  expected="$2"
                  originalPath="$PATH"
                  exec() {
                    if [ "$1" = -a ]; then shift 2; fi
                    test "$1" = "${extraToolsDesktop}/lib/chatgpt/ChatGPT"
                    test "$(command -v chatgpt-optional-tool)" = "$expected"
                    case "$PATH" in "$originalPath":*) ;; *) exit 1;; esac
                    test "$NIX_ENFORCE_PURITY" = 1
                    test "$NIX_CFLAGS_COMPILE" = sentinel
                  }
                  source "$1"
                ' launcher-check ${extraToolsDesktop}/bin/.chatgpt-wrapped \
                "$(if [ "$toolPath" = ${pkgs.coreutils}/bin ]; then
                      echo ${optionalTool}/bin/chatgpt-optional-tool
                    else
                      echo ${callerTool}/bin/chatgpt-optional-tool
                    fi)"
            done
            touch "$out"
          '';
        };
      }
      {
        checks.openai-codex-desktop-updater =
          pkgs.runCommand "openai-codex-desktop-updater-tests" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              cd ${updaterSource}
              python -B -m unittest discover \
                -s pkgs/by-name/op/openai-codex-desktop \
                -p 'test_*.py'
              touch "$out"
            '';

        checks.openai-codex-desktop-package-contract =
          pkgs.runCommand "openai-codex-desktop-package-contract"
            {
              nativeBuildInputs = [
                pkgs.file
                pkgs.python3
              ]
              ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [ pkgs.rcodesign ]
              ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
                pkgs.asar
                pkgs.desktop-file-utils
                pkgs.patchelf
              ];
            }
            (
              if pkgs.stdenv.hostPlatform.isDarwin then
                ''
                  test -d ${codexDesktop}/Applications/ChatGPT.app
                  test -x ${codexDesktop}/Applications/ChatGPT.app/Contents/MacOS/ChatGPT
                  test -L ${codexDesktop}/bin/chatgpt
                  test "$(readlink ${codexDesktop}/bin/chatgpt)" = \
                    ${codexDesktop}/Applications/ChatGPT.app/Contents/MacOS/ChatGPT
                  test -L ${codexDesktop}/bin/openai-codex-desktop
                  test "$(readlink ${codexDesktop}/bin/openai-codex-desktop)" = chatgpt
                  python - <<'PY'
                  import plistlib
                  from pathlib import Path

                  with Path(
                      "${codexDesktop}/Applications/ChatGPT.app/Contents/Info.plist"
                  ).open("rb") as plist_file:
                      info = plistlib.load(plist_file)
                  assert info["CFBundleIdentifier"] == "com.openai.codex"
                  assert info["CFBundleShortVersionString"] == "${codexDesktop.version}"
                  PY
                  file ${codexDesktop}/Applications/ChatGPT.app/Contents/MacOS/ChatGPT | grep -F arm64
                  rcodesign verify ${codexDesktop}/Applications/ChatGPT.app/Contents/MacOS/ChatGPT
                  touch "$out"
                ''
              else
                ''
                  test -x ${codexDesktop}/bin/chatgpt
                  head -n 1 ${codexDesktop}/bin/.chatgpt-wrapped | \
                    grep -E '^#! ?/nix/store/.+/bin/bash -e$'
                  grep -F NIXOS_OZONE_WL ${codexDesktop}/bin/.chatgpt-wrapped
                  grep -F WAYLAND_DISPLAY ${codexDesktop}/bin/.chatgpt-wrapped
                  grep -F -- '--ozone-platform=wayland' \
                    ${codexDesktop}/bin/.chatgpt-wrapped
                  if grep -F -- '--ozone-platform-hint=auto' \
                    ${codexDesktop}/bin/.chatgpt-wrapped; then
                    exit 1
                  fi
                  test -L ${codexDesktop}/bin/openai-codex-desktop
                  test "$(readlink ${codexDesktop}/bin/openai-codex-desktop)" = chatgpt
                  test -x ${codexDesktop}/lib/chatgpt/ChatGPT
                  test -x ${codexDesktop}/lib/chatgpt/resources/codex
                  test -x ${codexDesktop}/lib/chatgpt/resources/.codex-wrapped
                  test ! -e ${codexDesktop}/libexec/chatgpt-runtime
                  # Exercise the CLI wrapper without the user's PATH. The native
                  # enforcement probe runs outside the Nix build sandbox.
                  env -i PATH=${pkgs.coreutils}/bin \
                    ${codexDesktop}/lib/chatgpt/resources/codex --version | grep -F codex-cli
                  # Run the desktop shell setup, replacing only its final exec
                  # so the check needs neither a display nor nested namespaces.
                  # wrapProgram may compile the CLI wrapper; its enforcement is
                  # covered by the separate native probe, not by sourcing it.
                  env -i PATH=${pkgs.coreutils}/bin ${pkgs.bash}/bin/bash -c '
                    exec() { bwrap --version; }
                    source "$1"
                  ' wrapper-check ${codexDesktop}/bin/.chatgpt-wrapped | grep -F bubblewrap
                  test -f ${codexDesktop}/share/applications/chatgpt.desktop
                  test -f ${codexDesktop}/share/pixmaps/chatgpt.png
                  desktop-file-validate ${codexDesktop}/share/applications/chatgpt.desktop
                  grep -Fx 'Exec=chatgpt %U' \
                    ${codexDesktop}/share/applications/chatgpt.desktop
                  file ${codexDesktop}/lib/chatgpt/ChatGPT | grep -F 'ELF 64-bit'
                  patchelf --print-interpreter ${codexDesktop}/lib/chatgpt/ChatGPT | grep -F /nix/store/
                  ${codexDesktop}/lib/chatgpt/resources/codex --version | grep -F codex-cli
                  asar list --is-pack ${codexDesktop}/lib/chatgpt/resources/app.asar > asar-files
                  if grep -E '^pack[[:space:]]*: .*\.node$' asar-files; then
                    echo 'Native modules must stay unpacked for autoPatchelf' >&2
                    exit 1
                  fi
                  grep -E '^unpack[[:space:]]*: .*@parcel/watcher-.*/watcher\.node$' asar-files
                  asar extract ${codexDesktop}/lib/chatgpt/resources/app.asar app-asar
                  detect_libc=app-asar/node_modules/@parcel/watcher/node_modules/detect-libc/lib/filesystem.js
                  grep -F "const LDD_PATH = '${pkgs.stdenv.cc.libc.bin}/bin/ldd';" \
                    "$detect_libc"
                  if grep -F "const LDD_PATH = '/usr/bin/ldd';" "$detect_libc"; then
                    exit 1
                  fi
                  touch "$out"
                ''
            );
      }
    ];
}
