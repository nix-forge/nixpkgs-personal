{
  pkgs,
  testExecutable,
  runtimeLibraries,
  qemu,
  testFixtures ? [ ],
  expectedTestCount ? null,
  rayonThreads ? 8,
  memoryMb ? 1536,
  timeoutSeconds ? 7200,
}:
assert pkgs.stdenv.hostPlatform.isLinux;
assert pkgs.lib.versionAtLeast qemu.version "11.1.2";
assert expectedTestCount == null || expectedTestCount > 0;
assert rayonThreads > 0 && memoryMb >= 64 && timeoutSeconds > 0;
pkgs.runCommand "lightcraft-emulated-ui-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    targetRuntimeLibraries = runtimeLibraries;
    inherit testFixtures;
    preferLocalBuild = true;
    allowSubstitutes = false;
  }
  ''
    mkdir -p "$out"
    results="$TMPDIR/ui-results"
    if python3 ${./run_emulated_ui_tests.py} \
      --qemu ${qemu}/bin/qemu-aarch64 \
      --executable ${pkgs.lib.escapeShellArg (toString testExecutable)} \
      --output "$results" \
      --rayon-threads ${toString rayonThreads} \
      --memory-mb ${toString memoryMb} \
      --timeout-seconds ${toString timeoutSeconds} \
      ${pkgs.lib.optionalString (
        expectedTestCount != null
      ) "--expected-test-count ${toString expectedTestCount}"}
    then
      status=0
    else
      status=$?
      echo "UI suite failed; use --keep-failed to retain $results with its logs and receipt" >&2
    fi
    if [ -d "$results" ]; then
      cp -a "$results/." "$out/"
    fi
    if [ -f "$results/receipt.json" ]; then
      cat "$results/receipt.json"
    fi
    exit "$status"
  ''
