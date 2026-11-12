# shellcheck shell=bash
# The distributed module targets PowerShell 7. Keep the referenced
# compatibility project on its netstandard2.0 target during restore.
substituteInPlace Engine/Engine.csproj Rules/Rules.csproj \
  --replace-fail '<TargetFrameworks>net8;net462</TargetFrameworks>' \
  '<TargetFrameworks>net8</TargetFrameworks>'
substituteInPlace PSCompatibilityCollector/Microsoft.PowerShell.CrossCompatibility/Microsoft.PowerShell.CrossCompatibility.csproj \
  --replace-fail '<TargetFrameworks>netstandard2.0;net462</TargetFrameworks>' \
  '<TargetFrameworks>netstandard2.0</TargetFrameworks>'
