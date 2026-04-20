[CmdletBinding()]
param(
    [switch]$Integration,
    [switch]$All,
    [switch]$Coverage
)

$ErrorActionPreference = 'Stop'

Import-Module Pester -MinimumVersion 5.5.0 -ErrorAction Stop

$repoRoot = Split-Path -Parent $PSScriptRoot
$config   = New-PesterConfiguration

if ($All) {
    $config.Run.Path = (Join-Path $repoRoot 'tests')
} elseif ($Integration) {
    $config.Run.Path     = (Join-Path $repoRoot 'tests/integration')
    $config.Filter.Tag   = @('Integration')
} else {
    $config.Run.Path          = (Join-Path $repoRoot 'tests/unit')
    $config.Filter.ExcludeTag = @('Integration')
}

$config.Output.Verbosity    = 'Detailed'
$config.TestResult.Enabled  = $true
$config.TestResult.OutputPath = (Join-Path $repoRoot 'TestResults.xml')

if ($Coverage) {
    $config.CodeCoverage.Enabled    = $true
    $config.CodeCoverage.Path       = (Join-Path $repoRoot 'src')
    $config.CodeCoverage.OutputPath = (Join-Path $repoRoot 'Coverage.xml')
}

Invoke-Pester -Configuration $config
