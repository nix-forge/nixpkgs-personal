let
  flake = builtins.getFlake ("git+file://" + toString ../..);
  package = flake.packages.aarch64-linux.wordcraft;
in
package.overrideAttrs (previous: {
  pname = "wordcraft-arm-ui-diagnostic";
  cargoBuildType = "debug";
  cargoCheckType = "debug";
  cargoBuildFlags = [ "-p" "wordcraft-ui-egui" "--lib" "--locked" ];
  cargoTestFlags = [ "-p" "wordcraft-ui-egui" "--lib" "--locked" ];
  env = previous.env // {
    CARGO_INCREMENTAL = "0";
    CARGO_PROFILE_DEV_DEBUG = "0";
    CARGO_PROFILE_TEST_DEBUG = "0";
  };
  postPatch = previous.postPatch + ''
    substituteInPlace crates/ui-egui/src/lib.rs \
      --replace-fail 'assert!(body_text(h.state()).ends_with(text), "{what}: typing continues in the document");' \
      'assert!(body_text(h.state()).ends_with(text), "{what}: typing continues in the document; expected suffix={text:?}, actual={:?}, focus={:?}, anchor={:?}, want_focus={}, tab={:?}", body_text(h.state()), h.state().session.sel.focus, h.state().session.sel.anchor, h.state().canvas.want_focus, h.state().ui.tab);'
  '';
  installPhase = ''
    mkdir -p "$out"
    touch "$out/passed"
  '';
  postInstall = "";
  postFixup = "";
  doInstallCheck = false;
  passthru = {};
})
