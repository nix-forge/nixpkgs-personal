let
  flake = builtins.getFlake ("git+file://" + toString ../..);
  posthog = flake.packages.${builtins.currentSystem}.stirling-pdf-engine.tests.posthog;
in
posthog.overridePythonAttrs (previous: {
  preCheck = (previous.preCheck or "") + ''
    mkdir -p "$TMPDIR/posthog-observation"
    cp ${./posthog_fork_trace.py} "$TMPDIR/posthog-observation/sitecustomize.py"
    export PYTHONPATH="$TMPDIR/posthog-observation''${PYTHONPATH:+:$PYTHONPATH}"
  '';
})
