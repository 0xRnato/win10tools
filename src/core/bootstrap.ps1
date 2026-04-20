function Get-W10BootstrapZipUrl {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Owner  = '0xRnato',
        [string]$Repo   = 'win10tools',
        [string]$Branch = 'main'
    )
    "https://github.com/$Owner/$Repo/archive/refs/heads/$Branch.zip"
}

function New-W10BootstrapTargetDir {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Root = $env:TEMP
    )

    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = Join-Path $Root "win10tools-$stamp"
    New-Item -Path $target -ItemType Directory -Force | Out-Null
    $target
}

function Find-W10ExtractedRepoRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$TargetRoot
    )

    if (-not (Test-Path -LiteralPath $TargetRoot)) {
        throw "target root '$TargetRoot' does not exist"
    }

    $dir = Get-ChildItem -LiteralPath $TargetRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'win10tools-*' } |
        Select-Object -First 1

    if (-not $dir) {
        throw "no win10tools-* directory found under '$TargetRoot'"
    }

    $localRun = Join-Path $dir.FullName 'run.ps1'
    if (-not (Test-Path -LiteralPath $localRun)) {
        throw "run.ps1 not present in extracted archive at '$($dir.FullName)'"
    }

    $dir.FullName
}

function Invoke-W10Bootstrap {
    [CmdletBinding()]
    param(
        [string]$ZipUrl      = (Get-W10BootstrapZipUrl),
        [string]$TargetRoot,
        [string[]]$ArgumentList = @(),
        [switch]$DryRun
    )

    if (-not $TargetRoot) {
        $TargetRoot = New-W10BootstrapTargetDir
    } elseif (-not (Test-Path -LiteralPath $TargetRoot)) {
        New-Item -Path $TargetRoot -ItemType Directory -Force | Out-Null
    }

    $zipPath = Join-Path $TargetRoot 'repo.zip'

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ZipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop | Out-Null

    Expand-Archive -Path $zipPath -DestinationPath $TargetRoot -Force

    $repoRoot = Find-W10ExtractedRepoRoot -TargetRoot $TargetRoot
    $localRun = Join-Path $repoRoot 'run.ps1'

    if ($DryRun) {
        return [pscustomobject]@{
            TargetRoot = $TargetRoot
            RepoRoot   = $repoRoot
            RunPath    = $localRun
            Executed   = $false
        }
    }

    & $localRun @ArgumentList

    [pscustomobject]@{
        TargetRoot = $TargetRoot
        RepoRoot   = $repoRoot
        RunPath    = $localRun
        Executed   = $true
    }
}
