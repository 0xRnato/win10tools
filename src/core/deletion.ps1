$script:W10DeleteMode = 'RecycleBin'

function Set-DeletionMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('RecycleBin', 'Direct')]
        [string]$Mode
    )
    $script:W10DeleteMode = $Mode
    Write-W10Log -Level 'Info' -Message "deletion mode set" -Data @{ mode = $Mode }
}

function Get-DeletionMode { $script:W10DeleteMode }

function Remove-ItemSafely {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path,

        [ValidateSet('RecycleBin', 'Direct', 'Auto')]
        [string]$Mode = 'Auto'
    )

    process {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-W10Log -Level 'Warn' -Message 'path not found - nothing to remove' -Data @{ path = $Path }
            return [pscustomobject]@{ path = $Path; removed = $false; reason = 'not-found' }
        }

        $effective = if ($Mode -eq 'Auto') { $script:W10DeleteMode } else { $Mode }

        try {
            if ($effective -eq 'RecycleBin') {
                Send-PathToRecycleBin -Path $Path
            } else {
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            }

            Write-W10Log -Level 'Info' -Message 'removed' -Data @{ path = $Path; mode = $effective }
            return [pscustomobject]@{ path = $Path; removed = $true; mode = $effective }
        }
        catch {
            Write-W10Log -Level 'Error' -Message 'remove failed' -Data @{ path = $Path; mode = $effective; error = $_.Exception.Message }
            return [pscustomobject]@{ path = $Path; removed = $false; reason = 'error'; error = $_.Exception.Message }
        }
    }
}

function Send-PathToRecycleBin {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop

    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $ui   = [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs
    $recycle = [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin

    if ((Get-Item -LiteralPath $full -Force).PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($full, $ui, $recycle)
    } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($full, $ui, $recycle)
    }
}
