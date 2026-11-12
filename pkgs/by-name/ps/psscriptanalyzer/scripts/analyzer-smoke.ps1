$ErrorActionPreference = "Stop"
Import-Module $env:ANALYZER_PATH
$findings = @(Invoke-ScriptAnalyzer -ScriptDefinition "`$unused = 1")
if ($findings.RuleName -notcontains "PSUseDeclaredVarsMoreThanAssignments") {
    throw "Analyzer failed to detect an unused variable"
}
