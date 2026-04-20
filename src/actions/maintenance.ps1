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

    $cleanupTaskName   = 'win10tools-quarantine-cleanup'
    $cleanupScriptPath = Join-Path $env:LOCALAPPDATA 'win10tools\scheduled\cleanup-quarantine.ps1'

    Register-Action @{
        Id          = 'maintenance.schedule-quarantine-cleanup'
        Category    = 'Maintenance'
        Name        = 'Schedule daily quarantine cleanup (>30 days)'
        Description = 'Creates a daily scheduled task that removes win10tools quarantine batches older than 30 days. Self-contained helper written to %LOCALAPPDATA%\win10tools\scheduled\.'
        Risk        = 'Safe'
        Destructive = $true
        NeedsReboot = $false
        NeedsAdmin  = $true
        Context     = @{
            TaskName   = $cleanupTaskName
            ScriptPath = $cleanupScriptPath
            MaxAgeDays = 30
        }
        Check       = {
            param($c)
            $existing = Get-ScheduledTask -TaskName $c.TaskName -ErrorAction SilentlyContinue
            [bool]$existing -and (Test-Path -LiteralPath $c.ScriptPath)
        }
        Invoke      = {
            param($c)
            $scriptDir = Split-Path -Parent $c.ScriptPath
            if (-not (Test-Path -LiteralPath $scriptDir)) {
                New-Item -Path $scriptDir -ItemType Directory -Force | Out-Null
            }

            $body = @"
`$root   = Join-Path `$env:LOCALAPPDATA 'win10tools\quarantine'
if (-not (Test-Path -LiteralPath `$root)) { exit 0 }
`$cutoff = (Get-Date).AddDays(-$($c.MaxAgeDays))
Get-ChildItem -LiteralPath `$root -Directory -ErrorAction SilentlyContinue |
    Where-Object { `$_.CreationTime -lt `$cutoff } |
    ForEach-Object {
        try { Remove-Item -LiteralPath `$_.FullName -Recurse -Force -ErrorAction Stop }
        catch { }
    }
"@
            Set-Content -LiteralPath $c.ScriptPath -Value $body -Encoding UTF8

            $existing = Get-ScheduledTask -TaskName $c.TaskName -ErrorAction SilentlyContinue
            if ($existing) {
                Unregister-ScheduledTask -TaskName $c.TaskName -Confirm:$false -ErrorAction SilentlyContinue
            }

            $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$($c.ScriptPath)`""
            $trigger   = New-ScheduledTaskTrigger -Daily -At 3am
            $principal = New-ScheduledTaskPrincipal -UserId (Get-CimInstance -Class Win32_ComputerSystem).UserName -LogonType Interactive -RunLevel Limited
            $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

            Register-ScheduledTask -TaskName $c.TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'win10tools: daily cleanup of quarantine batches older than 30 days' -Force | Out-Null

            Write-W10Log -Level 'Info' -ActionId 'maintenance.schedule-quarantine-cleanup' -Message 'scheduled task registered' -Data @{
                taskName   = $c.TaskName
                scriptPath = $c.ScriptPath
                maxAgeDays = $c.MaxAgeDays
            }
        }
        Revert      = {
            param($c)
            $existing = Get-ScheduledTask -TaskName $c.TaskName -ErrorAction SilentlyContinue
            if ($existing) {
                Unregister-ScheduledTask -TaskName $c.TaskName -Confirm:$false -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $c.ScriptPath) {
                Remove-Item -LiteralPath $c.ScriptPath -Force -ErrorAction SilentlyContinue
            }
            $scriptDir = Split-Path -Parent $c.ScriptPath
            if ((Test-Path -LiteralPath $scriptDir) -and -not (Get-ChildItem -LiteralPath $scriptDir -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $scriptDir -Force -ErrorAction SilentlyContinue
            }
        }
        DryRunSummary = {
            param($c)
            "[MAINTENANCE] Register-ScheduledTask '$($c.TaskName)' (daily 03:00) -> $($c.ScriptPath); prunes quarantine >$($c.MaxAgeDays)d"
        }
    }
}

Register-Enumerator 'Register-MaintenanceActions'
