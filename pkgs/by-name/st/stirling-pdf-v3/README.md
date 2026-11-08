# Stirling PDF v3 release package

This package installs Stirling PDF 3.3.0 from the versioned, login-enabled
upstream JAR. The JAR includes the web UI and authentication. It uses Java 25
and copies the matching upstream `scripts/` helpers for PDF operations.

The Nixpkgs `stirling-pdf` recipe at the reviewed revision builds version
2.14.3 from source. Its npm, Cargo, and Gradle dependencies have separate pins,
so changing only the version and source hash does not produce a v3 build. This
release package is a temporary way to run v3 while a source-built Nixpkgs recipe
is prepared. The NixOS `services.stirling-pdf.package` option can select it
without replacing the NixOS service module.

Stirling 3.3.0 already selects local fallback fonts by the requested face and
PDFium's pitch-family flags. The old local JAR rewrite is retired. Install checks
exercise the released viewer's actual font-selection class with serif, monospace,
sans, subset names, bold/italic and non-Latin cases. Runtime checks confirm the
viewer and local fallback font files are served. PDF contents are unchanged.

The login-enabled artifact contains proprietary code as well as MIT-licensed
code. Its license metadata includes both `mit` and `unfree`, and the relevant
upstream license notices are installed. Review the
[v3.3.0 proprietary license](https://github.com/Stirling-Tools/Stirling-PDF/blob/v3.3.0/app/proprietary/LICENSE)
before use or redistribution, especially if modifying or publishing the built
JAR. The binary artifact also bundles native code, so a Nix source build is
preferable for dependency auditability when available.

There is no automatic updater: each v3 release needs review of the JAR hash,
matching source hash, bundled licenses, frontend asset identity and font-selection behavior, and
runtime/redaction behavior. The package's runtime check launches the server with
synthetic credentials and confirms login initialization, UI serving, the current
font helper's CLI, and local font assets. Version 3.3 removed the legacy Python
CFF converter; its font helper check now exercises the shipped subsetting tool.
