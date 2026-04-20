[CmdletBinding()]
param(
    [switch]$Cli,
    [switch]$SkipElevation,
    [string]$BootstrapUrl = 'https://raw.githubusercontent.com/0xRnato/win10tools/main/run.ps1'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$scriptRoot = if ($PSCommandPath) {
    Split-Path -Parent $PSCommandPath
} elseif ($PSScriptRoot) {
    $PSScriptRoot
} else {
    $null
}

if (-not $scriptRoot) {
    Write-Host "win10tools: running in bootstrap mode." -ForegroundColor Yellow
    Write-Host "Full-remote bootstrap is not implemented yet (arriving in M9)." -ForegroundColor Yellow
    Write-Host "Clone the repo and run the local copy:" -ForegroundColor Yellow
    Write-Host "  git clone https://github.com/0xRnato/win10tools.git"
    Write-Host "  cd win10tools"
    Write-Host "  .\run.ps1"
    exit 2
}

$srcRoot = Join-Path $scriptRoot 'src'

foreach ($subdir in @('core', 'enumerators', 'actions')) {
    $dir = Join-Path $srcRoot $subdir
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -File |
        Sort-Object Name |
        ForEach-Object { . $_.FullName }
}

Initialize-W10Logger
Write-W10Log -Level 'Info' -Message 'win10tools starting' -Data @{
    cli            = [bool]$Cli
    skipElevation  = [bool]$SkipElevation
    admin          = Test-IsAdmin
    scriptRoot     = $scriptRoot
}

Invoke-AllEnumerators

if (-not (Test-IsAdmin) -and -not $SkipElevation) {
    Write-Host 'win10tools needs Administrator. Relaunching elevated...' -ForegroundColor Yellow
    $argList = @()
    if ($Cli) { $argList += '-Cli' }
    Invoke-Elevate -ScriptPath $PSCommandPath -ArgumentList $argList -BootstrapUrl $BootstrapUrl
    return
}

$actionCount = Get-ActionCount
$categories  = Get-ActionCategories

Write-W10Log -Level 'Info' -Message 'registry loaded' -Data @{
    actions    = $actionCount
    categories = @($categories)
}

Write-Host ''
Write-Host 'win10tools' -ForegroundColor Cyan
Write-Host "  session  : $(Get-W10SessionId)"
Write-Host "  admin    : $(Test-IsAdmin)"
Write-Host "  log      : $(Get-W10LogPath)"
Write-Host "  actions  : $actionCount"
if ($categories) {
    Write-Host "  groups   : $($categories -join ', ')"
} else {
    Write-Host '  groups   : (none registered yet - enumerators arrive in M2+)'
}
Write-Host ''

if ($Cli) {
    Write-Host 'CLI mode placeholder - interactive menu lands in M8.' -ForegroundColor DarkGray
} else {
    Write-Host 'GUI mode placeholder - WPF window lands in M7.' -ForegroundColor DarkGray
}

Write-W10Log -Level 'Info' -Message 'win10tools finished' -Data @{ status = 'ok' }
