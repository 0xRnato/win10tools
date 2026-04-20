function Register-MaintenanceActions {
    [CmdletBinding()]
    param()

    Register-Action @{
        Id          = 'maintenance.sfc-scannow'
        Category    = 'Maintenance'
        Name        = 'Run System File Checker (sfc /scannow)'
        Description = 'Scans protected system files and replaces corrupted ones. Runs a few minutes to tens of minutes.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $out = & cmd.exe /c 'sfc /scannow' 2>&1 | Out-String
            Write-W10Log -Level 'Info' -ActionId 'maintenance.sfc-scannow' -Message 'sfc done' -Data @{
                tail = $out.Substring([Math]::Max(0, $out.Length - 400))
            }
        }
        DryRunSummary = { '[MAINTENANCE] sfc.exe /scannow' }
    }

    Register-Action @{
        Id          = 'maintenance.dism-check-health'
        Category    = 'Maintenance'
        Name        = 'DISM CheckHealth (quick)'
        Description = 'Queries component store for corruption flags without running a scan. Seconds.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $out = & dism.exe /Online /Cleanup-Image /CheckHealth 2>&1 | Out-String
            Write-W10Log -Level 'Info' -ActionId 'maintenance.dism-check-health' -Message 'dism check' -Data @{
                tail = $out.Substring([Math]::Max(0, $out.Length - 400))
            }
        }
        DryRunSummary = { '[MAINTENANCE] dism /Online /Cleanup-Image /CheckHealth' }
    }

    Register-Action @{
        Id          = 'maintenance.dism-restore-health'
        Category    = 'Maintenance'
        Name        = 'DISM RestoreHealth (deep repair)'
        Description = 'Repairs the Windows component store from Windows Update. Can take 20+ minutes.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $out = & dism.exe /Online /Cleanup-Image /RestoreHealth 2>&1 | Out-String
            Write-W10Log -Level 'Info' -ActionId 'maintenance.dism-restore-health' -Message 'dism restore done' -Data @{
                tail = $out.Substring([Math]::Max(0, $out.Length - 400))
            }
        }
        DryRunSummary = { '[MAINTENANCE] dism /Online /Cleanup-Image /RestoreHealth' }
    }

    Register-Action @{
        Id          = 'maintenance.create-restore-point'
        Category    = 'Maintenance'
        Name        = 'Create a manual restore point'
        Description = 'Calls Checkpoint-Computer with a descriptive label. Windows rate-limits to 1 per 24h by default.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            New-AutoRestorePoint -Description "win10tools manual $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-Null
        }
        DryRunSummary = { '[MAINTENANCE] Checkpoint-Computer (rate-limited by Windows)' }
    }
}

Register-Enumerator 'Register-MaintenanceActions'
