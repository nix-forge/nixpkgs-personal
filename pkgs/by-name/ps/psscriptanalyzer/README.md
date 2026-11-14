# PSScriptAnalyzer

This package compiles the PowerShell 7 module from the tagged .NET 8 source.
It uses `buildDotnetModule` and a pinned NuGet restore graph in `deps.json`.
The Gallery archive supplies only the generated external-help XML; no Gallery
assemblies are installed. The module still includes the pinned Pluralize.NET
NuGet assembly, recorded as binary bytecode in its provenance. The upstream
MIT license and third-party notices are retained under `share/doc`.

Run `python3 update.py --dry-run` to preview the latest stable release, then
`python3 update.py` to refresh the GitHub source hash, Gallery help hash, and
NuGet dependency graph together. The updater stages the new graph before
changing the package. Build the package and run consumer script checks before
adopting new diagnostics: a new rule set can change configuration acceptance.
The installation check imports the source-built module and requires it to find
a known unused-variable defect; it does not execute the analyzed script.

On Darwin, compilation uses the pinned Nixpkgs `sdk_8_0-bin` and
`runtime_8_0-bin` toolchain packages. This avoids bootstrapping .NET itself
for a small analyzer build. The module is still compiled from the same tagged
source with the same NuGet hashes, import check and rule-detection check.
Linux retains the ordinary Nixpkgs SDK and runtime selections.
