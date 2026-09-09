# PSScriptAnalyzer

This package installs Microsoft's PowerShell Gallery release without modifying
its assemblies. The version and archive hash are pinned in `source.nix`.
The upstream MIT license is retained alongside the module and under `share/doc`.

Updates are manual because a new rule set can change configuration acceptance.
Review the release notes and bundled notices, update the version and hash, then
run the package's installation check and consumer script checks before adopting
new diagnostics. The installation check imports the module and requires it to
find a known unused-variable defect; it does not execute the analyzed script.
