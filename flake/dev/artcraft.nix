{ packageNixpkgs, packageOverlay, ... }: {
  perSystem =
    { pkgs, system, ... }:
    let
      packages = import packageNixpkgs (
        (import ../platform-args.nix system) // { overlays = [ packageOverlay ]; }
      );
      native = packages.buildPackages;
      names = import ../artcraft-apps.nix;
      guiObserver = native.writers.writePython3Bin "artcraft-gui-observer" {
        libraries = [
          native.python3Packages.python-xlib
          (native.callPackage ../../pkgs/by-name/no/notification-process/package.nix { })
        ];
        flakeIgnore = [ "E501" ];
      } ./artcraft_gui.py;
      guiCheck =
        name:
        native.runCommand "${name}-gui-smoke"
          {
            nativeBuildInputs = [
              native.coreutils
              native.xvfb-run
              native.xwininfo
              native.ripgrep
            ];
          }
          (
            (import ../../lib/render-text.nix) ./scripts/artcraft-gui-smoke.sh {
              pkgs_lib_makeLibraryPath_packages_mesa = pkgs.lib.makeLibraryPath [ packages.mesa ];
              packages_mesa = packages.mesa;
              if_system_x86_64_linux_then_x86_64_else_aarch64 =
                if system == "x86_64-linux" then "x86_64" else "aarch64";
              artcraft_gui_sh = pkgs.writeShellScript "artcraft-gui" (
                (import ../../lib/render-text.nix) ./artcraft-gui.sh {
                  artcraft_gui_python = pkgs.lib.getExe guiObserver;
                }
              );
              pkgs_lib_escapeShellArg_packages_name_bin_name = pkgs.lib.escapeShellArg "${packages.${name}}/bin/${name}";
            }
          );
      waylandCheck =
        name:
        native.runCommand "${name}-wayland-smoke"
          {
            nativeBuildInputs = [
              native.cage
              native.dbus
              native.python3
            ];
          }
          ''
            export HOME="$TMPDIR/home" XDG_RUNTIME_DIR="$TMPDIR/runtime"
            export XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_DATA_HOME="$TMPDIR/data"
            mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
            chmod 700 "$XDG_RUNTIME_DIR"
            unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS XAUTHORITY
            export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1
            export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=cage
            # Upstream intentionally defaults these two apps to X11 when DISPLAY exists.
            export DECKCRAFT_WAYLAND=1 DESIGNCRAFT_WAYLAND=1
            dbus-run-session --config-file ${./artcraft-session-bus.conf} -- cage -D -- env \
              LIBGL_ALWAYS_SOFTWARE=1 \
              LIBGL_DRIVERS_PATH=${packages.mesa}/lib/dri \
              __EGL_VENDOR_LIBRARY_FILENAMES=${packages.mesa}/share/glvnd/egl_vendor.d/50_mesa.json \
              VK_DRIVER_FILES=${packages.mesa}/share/vulkan/icd.d/lvp_icd.${
                if system == "x86_64-linux" then "x86_64" else "aarch64"
              }.json \
              python3 ${./check_wayland.py} \
              ${pkgs.lib.escapeShellArg "${packages.${name}}/bin/${name}"} \
              ${
                pkgs.lib.escapeShellArg (
                  if name == "craft-launcher" then "io.github.nix_forge.craft-launcher" else "ai.storyteller.${name}"
                )
              } \
              "$TMPDIR/wayland.log" > "$out"
          '';
      waylandChecks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        pkgs.lib.genAttrs (map (name: "${name}-wayland") names) (
          check: waylandCheck (pkgs.lib.removeSuffix "-wayland" check)
        )
      );
      guiChecks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        pkgs.lib.genAttrs (map (name: "${name}-gui") names) (
          check: guiCheck (pkgs.lib.removeSuffix "-gui" check)
        )
      );
    in
    {
      # Each check builds the native app and exercises its installed CLI.
      checks = {
        artcraft-wayland-observer =
          pkgs.runCommand "artcraft-wayland-observer" { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              python3 ${../../tests/test_check_wayland.py} ${./check_wayland.py}
              touch "$out"
            '';
      }
      // pkgs.lib.genAttrs (map (name: "${name}-cli") names) (
        check: packages.${pkgs.lib.removeSuffix "-cli" check}.tests.cli
      )
      // pkgs.lib.genAttrs (map (name: "${name}-licenses") names) (
        check: packages.${pkgs.lib.removeSuffix "-licenses" check}.tests.licenses
      )
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        pkgs.lib.genAttrs (map (name: "${name}-appstream") names) (
          check: packages.${pkgs.lib.removeSuffix "-appstream" check}.tests.appstream
        )
      )
      // {
        craft-launcher-quit-state = packages.craft-launcher.tests.quitState;
        deckcraft-archive-compatibility = packages.deckcraft.tests.archiveCompatibility;
        designcraft-archive-compatibility = packages.designcraft.tests.archiveCompatibility;
        figcraft-archive-compatibility = packages.figcraft.tests.archiveCompatibility;
        figcraft-server = packages.figcraft.tests.server;
        filmcraft-menu-dependencies = packages.filmcraft.tests.menuDependencies;
        filmcraft-tls-provider = packages.filmcraft.tests.tlsProvider;
        filmcraft-archive-compatibility = packages.filmcraft.tests.archiveCompatibility;
        gridcraft-archive-compatibility = packages.gridcraft.tests.archiveCompatibility;
        lightcraft-tls-provider = packages.lightcraft.tests.tlsProvider;
        lightcraft-segment-compatibility = packages.lightcraft.tests.segmentCompatibility;
        wordcraft-archive-compatibility = packages.wordcraft.tests.archiveCompatibility;
        soundcraft-archive-compatibility = packages.soundcraft.tests.archiveCompatibility;
      }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        craft-launcher-host-tests-artifact = packages.craft-launcher.hostTests.native;
        photocraft-host-tests-artifact = packages.photocraft.hostTests.native;
        soundcraft-host-tests-artifact = packages.soundcraft.hostTests.native;
      }
      // pkgs.lib.optionalAttrs (
        pkgs.stdenv.hostPlatform.isLinux && (packages.craft-launcher.tests ? appimageRuntime)
      ) { craft-launcher-appimage-runtime = packages.craft-launcher.tests.appimageRuntime; }
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        pdfcraft-wayland-clipboard = packages.pdfcraft.tests.waylandClipboard;
      }
      // guiChecks
      // waylandChecks
      // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        artcraft-gui = native.runCommand "artcraft-gui-smoke" { } ''
          ${pkgs.lib.concatMapStringsSep "\n" (name: "test -e ${guiChecks."${name}-gui"}") names}
          touch "$out"
        '';

      };
    };
}
