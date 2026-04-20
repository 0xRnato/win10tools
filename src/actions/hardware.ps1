function Register-HardwareActions {
    [CmdletBinding()]
    param()

    Register-Action @{
        Id          = 'hardware.smart-report'
        Category    = 'Hardware'
        Name        = 'Generate SMART health report'
        Description = 'Reads Get-PhysicalDisk + Get-StorageReliabilityCounter for every disk. Flags non-healthy drives.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
            foreach ($d in $disks) {
                $rc = $null
                try { $rc = Get-StorageReliabilityCounter -PhysicalDisk $d -ErrorAction Stop } catch { Write-Verbose "reliability counters unavailable for $($d.DeviceId)" }
                Write-W10Log -Level 'Info' -ActionId 'hardware.smart-report' -Message 'disk report' -Data @{
                    deviceId     = $d.DeviceId
                    friendlyName = $d.FriendlyName
                    media        = $d.MediaType
                    health       = $d.HealthStatus
                    operational  = $d.OperationalStatus
                    wearPercent  = if ($rc) { $rc.Wear }             else { $null }
                    readErrors   = if ($rc) { $rc.ReadErrorsTotal }  else { $null }
                    writeErrors  = if ($rc) { $rc.WriteErrorsTotal } else { $null }
                    temperature  = if ($rc) { $rc.Temperature }      else { $null }
                    powerHours   = if ($rc) { $rc.PowerOnHours }     else { $null }
                }
                if ($d.HealthStatus -ne 'Healthy') {
                    Write-W10Log -Level 'Warn' -ActionId 'hardware.smart-report' -Message "disk $($d.FriendlyName) is $($d.HealthStatus)"
                }
            }
        }
        DryRunSummary = { '[HARDWARE] SMART + reliability counters for every PhysicalDisk' }
    }

    Register-Action @{
        Id          = 'hardware.schedule-memory-test'
        Category    = 'Hardware'
        Name        = 'Schedule memory test (mdsched) on next boot'
        Description = 'Invokes mdsched.exe /check which sets the flag for Memory Diagnostic to run at next reboot.'
        Risk        = 'Minor'
        Destructive = $true
        NeedsReboot = $true
        NeedsAdmin  = $true
        Invoke      = {
            Start-Process -FilePath 'mdsched.exe' -ArgumentList '/check' -Wait -WindowStyle Hidden -ErrorAction Stop
            Write-W10Log -Level 'Info' -ActionId 'hardware.schedule-memory-test' -Message 'memory test scheduled for next boot'
        }
        DryRunSummary = { '[HARDWARE] mdsched.exe /check (runs at next reboot)' }
    }

    Register-Action @{
        Id          = 'hardware.schedule-chkdsk'
        Category    = 'Hardware'
        Name        = 'Schedule chkdsk /f /r on system drive at next boot'
        Description = 'Queues chkdsk C: /f /r to run at next reboot.'
        Risk        = 'Minor'
        Destructive = $true
        NeedsReboot = $true
        NeedsAdmin  = $true
        Invoke      = {
            $out = & cmd.exe /c 'echo Y| chkdsk C: /f /r' 2>&1 | Out-String
            Write-W10Log -Level 'Info' -ActionId 'hardware.schedule-chkdsk' -Message 'chkdsk scheduled' -Data @{ stdout = $out.Substring(0, [Math]::Min(400, $out.Length)) }
        }
        DryRunSummary = { '[HARDWARE] chkdsk C: /f /r (queued at next boot)' }
    }

    Register-Action @{
        Id          = 'hardware.battery-report'
        Category    = 'Hardware'
        Name        = 'Generate battery report HTML'
        Description = 'Runs powercfg /batteryreport, writes HTML under %TEMP% and opens it.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $out = Join-Path $env:TEMP ('battery-report-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.html')
            $null = & powercfg /batteryreport /output $out 2>&1
            if (Test-Path $out) {
                Start-Process -FilePath $out
                Write-W10Log -Level 'Info' -ActionId 'hardware.battery-report' -Message 'battery report generated' -Data @{ path = $out }
            } else {
                Write-W10Log -Level 'Warn' -ActionId 'hardware.battery-report' -Message 'battery report not produced (no battery?)'
            }
        }
        DryRunSummary = { '[HARDWARE] powercfg /batteryreport /output %TEMP%\battery-report-<stamp>.html' }
    }

    Register-Action @{
        Id          = 'hardware.system-info'
        Category    = 'Hardware'
        Name        = 'Dump system info + dxdiag reports'
        Description = 'Writes Get-ComputerInfo JSON + dxdiag /t to %TEMP%.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $false
        Invoke      = {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $ci    = Join-Path $env:TEMP "sysinfo-$stamp.json"
            $dx    = Join-Path $env:TEMP "dxdiag-$stamp.txt"

            Get-ComputerInfo -ErrorAction SilentlyContinue |
                ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath $ci -Encoding UTF8

            Start-Process -FilePath 'dxdiag.exe' -ArgumentList @('/t', $dx) -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
            Write-W10Log -Level 'Info' -ActionId 'hardware.system-info' -Message 'reports written' -Data @{ sysinfo = $ci; dxdiag = $dx }
        }
        DryRunSummary = { '[HARDWARE] Get-ComputerInfo -> JSON + dxdiag /t -> txt' }
    }

    Register-Action @{
        Id          = 'hardware.event-log-triage'
        Category    = 'Hardware'
        Name        = 'Event log triage (last 24h, critical + error)'
        Description = 'Pulls Level 1 (critical) and 2 (error) events from Application and System logs over the past 24 hours, grouped by provider.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $since  = (Get-Date).AddHours(-24)
            $events = @()
            foreach ($logName in 'Application', 'System') {
                try {
                    $events += @(Get-WinEvent -FilterHashtable @{
                        LogName   = $logName
                        Level     = 1, 2
                        StartTime = $since
                    } -ErrorAction SilentlyContinue)
                } catch { Write-Verbose "log $logName : $($_.Exception.Message)" }
            }

            $groups = $events | Group-Object ProviderName | Sort-Object Count -Descending
            $top5   = @($groups | Select-Object -First 5 | ForEach-Object {
                @{ source = $_.Name; count = $_.Count }
            })

            Write-W10Log -Level 'Info' -ActionId 'hardware.event-log-triage' -Message "events=$($events.Count)" -Data @{
                total = $events.Count
                top5  = $top5
            }
        }
        DryRunSummary = { '[HARDWARE] Get-WinEvent Application+System (Level 1,2; last 24h) grouped by provider' }
    }

    Register-Action @{
        Id          = 'hardware.cpu-temperature'
        Category    = 'Hardware'
        Name        = 'Check CPU temperature via ACPI'
        Description = 'Reads MSAcpi_ThermalZoneTemperature. Most consumer BIOSes do not expose it; failure is normal.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            try {
                $tz = Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop
                foreach ($t in $tz) {
                    $celsius = [math]::Round((($t.CurrentTemperature / 10) - 273.15), 1)
                    Write-W10Log -Level 'Info' -ActionId 'hardware.cpu-temperature' -Message "zone $($t.InstanceName)" -Data @{ celsius = $celsius }
                }
            } catch {
                Write-W10Log -Level 'Info' -ActionId 'hardware.cpu-temperature' -Message 'thermal zone not reported (normal on most consumer hardware)'
            }
        }
        DryRunSummary = { '[HARDWARE] MSAcpi_ThermalZoneTemperature (often unsupported by BIOS)' }
    }
}

Register-Enumerator 'Register-HardwareActions'
