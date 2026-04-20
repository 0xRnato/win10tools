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
    Write-Host 'win10tools: bootstrap mode - downloading source from GitHub...' -ForegroundColor Cyan
    $stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target     = Join-Path $env:TEMP "win10tools-$stamp"
    $zipUrl     = 'https://github.com/0xRnato/win10tools/archive/refs/heads/main.zip'
    $zipPath    = Join-Path $target 'repo.zip'

    try {
        New-Item -Path $target -ItemType Directory -Force | Out-Null
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $target -Force

        $extracted = Get-ChildItem -LiteralPath $target -Directory -ErrorAction Stop |
            Where-Object { $_.Name -like 'win10tools-*' } |
            Select-Object -First 1
        if (-not $extracted) { throw 'extracted archive missing win10tools-* directory' }

        $localRun = Join-Path $extracted.FullName 'run.ps1'
        if (-not (Test-Path -LiteralPath $localRun)) { throw "run.ps1 not found in $($extracted.FullName)" }

        Write-Host "win10tools: handing off to $localRun" -ForegroundColor Cyan
        $forward = @()
        if ($Cli)           { $forward += '-Cli' }
        if ($SkipElevation) { $forward += '-SkipElevation' }
        & $localRun @forward
        exit $LASTEXITCODE
    } catch {
        Write-Host "Bootstrap failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ''
        Write-Host 'Fallback (clone manually):' -ForegroundColor Yellow
        Write-Host '  git clone https://github.com/0xRnato/win10tools.git'
        Write-Host '  cd win10tools'
        Write-Host '  .\run.ps1'
        exit 2
    }
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
    $cliScript = Join-Path $srcRoot 'cli/menu.ps1'
    if (Test-Path -LiteralPath $cliScript) {
        . $cliScript
        . (Join-Path $srcRoot 'ui/main-window-helpers.ps1')
        Show-CliMenu
    } else {
        Write-Host 'CLI script missing.' -ForegroundColor DarkGray
    }
} else {
    $guiScript = Join-Path $srcRoot 'ui/main-window.ps1'
    if (Test-Path -LiteralPath $guiScript) {
        . $guiScript
        Show-MainWindow
    } else {
        Write-Host 'GUI script missing.' -ForegroundColor DarkGray
    }
}

Write-W10Log -Level 'Info' -Message 'win10tools finished' -Data @{ status = 'ok' }
