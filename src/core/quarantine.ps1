$script:W10QuarantineRoot    = Join-Path $env:LOCALAPPDATA 'win10tools\quarantine'
$script:W10QuarantineMaxDays = 30

function Get-QuarantineRoot { $script:W10QuarantineRoot }

function Set-QuarantineRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $script:W10QuarantineRoot = $Path
}

function New-QuarantineBatch {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Label
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $name  = if ($Label) { "$stamp-$Label" } else { $stamp }
    $batch = Join-Path $script:W10QuarantineRoot $name

    if (-not (Test-Path -LiteralPath $batch)) {
        New-Item -Path $batch -ItemType Directory -Force | Out-Null
    }

    Write-W10Log -Level 'Info' -Message 'quarantine batch created' -Data @{ batch = $batch }
    $batch
}

function Move-ToQuarantine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BatchPath,
        [string]$RelativeName
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-W10Log -Level 'Warn' -Message 'quarantine: source missing' -Data @{ path = $Path }
        return $null
    }

    $target = if ($RelativeName) {
        Join-Path $BatchPath $RelativeName
    } else {
        $leaf  = Split-Path -Leaf $Path
        $drive = (Split-Path -Qualifier $Path).TrimEnd(':')
        $dir   = Join-Path $BatchPath $drive
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Join-Path $dir $leaf
    }

    $targetDir = Split-Path -Parent $target
    if ($targetDir -and -not (Test-Path -LiteralPath $targetDir)) {
        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
    }

    Move-Item -LiteralPath $Path -Destination $target -Force -ErrorAction Stop
    Write-W10Log -Level 'Info' -Message 'quarantined' -Data @{ from = $Path; to = $target }
    $target
}

function Export-RegistryKeyToQuarantine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RegistryPath,
        [Parameter(Mandatory)][string]$BatchPath
    )

    $safe = ($RegistryPath -replace '[\\/:*?"<>|]', '_')
    $file = Join-Path $BatchPath "$safe.reg"

    $regArg = $RegistryPath -replace '^(HKCU|HKLM|HKCR|HKU|HKCC):', '$1'

    $proc = Start-Process -FilePath 'reg.exe' -ArgumentList @('export', $regArg, $file, '/y') -NoNewWindow -Wait -PassThru

    if ($proc.ExitCode -ne 0) {
        Write-W10Log -Level 'Error' -Message 'reg export failed' -Data @{ key = $RegistryPath; exit = $proc.ExitCode }
        return $null
    }

    Write-W10Log -Level 'Info' -Message 'registry key exported' -Data @{ key = $RegistryPath; file = $file }
    $file
}

function Remove-OldQuarantine {
    [CmdletBinding()]
    param(
        [int]$MaxDays = $script:W10QuarantineMaxDays
    )

    if (-not (Test-Path -LiteralPath $script:W10QuarantineRoot)) { return 0 }

    $cutoff  = (Get-Date).AddDays(-$MaxDays)
    $removed = 0

    Get-ChildItem -LiteralPath $script:W10QuarantineRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.CreationTime -lt $cutoff } |
        ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                $removed++
                Write-W10Log -Level 'Info' -Message 'old quarantine batch removed' -Data @{ batch = $_.Name }
            } catch {
                Write-W10Log -Level 'Warn' -Message 'failed to remove old quarantine' -Data @{ batch = $_.Name; error = $_.Exception.Message }
            }
        }

    $removed
}
