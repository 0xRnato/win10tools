function Get-InstalledProgramIndex {
    [CmdletBinding()]
    param()

    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $programs = [System.Collections.Generic.List[object]]::new()

    foreach ($k in $keys) {
        try {
            Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | ForEach-Object {
                if (-not $_.DisplayName) { return }
                if ($_.SystemComponent -eq 1) { return }
                if ($_.ParentKeyName)         { return }

                $programs.Add([pscustomobject]@{
                    Name            = [string]$_.DisplayName
                    Publisher       = [string]$_.Publisher
                    Version         = [string]$_.DisplayVersion
                    InstallLocation = [string]$_.InstallLocation
                    UninstallString = [string]$_.UninstallString
                    RegistryPath    = [string]$_.PSPath
                    Source          = 'Win32'
                }) | Out-Null
            }
        } catch {
            Write-Verbose "uninstall key scan ($k): $($_.Exception.Message)"
        }
    }

    try {
        Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object {
            $programs.Add([pscustomobject]@{
                Name            = [string]$_.Name
                Publisher       = [string]$_.Publisher
                Version         = [string]$_.Version
                InstallLocation = [string]$_.InstallLocation
                UninstallString = $null
                RegistryPath    = $null
                Source          = 'Appx'
            }) | Out-Null
        }
    } catch {
        Write-Verbose "Get-AppxPackage failed: $($_.Exception.Message)"
    }

    $programs
}

function Get-PrefetchIndex {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    $map = @{}
    $prefetchDir = Join-Path $env:WINDIR 'Prefetch'
    if (-not (Test-Path -LiteralPath $prefetchDir)) { return $map }

    try {
        Get-ChildItem -LiteralPath $prefetchDir -Filter '*.pf' -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -match '^([^-]+)-[0-9A-F]+\.pf$') {
                $exe = $matches[1].ToUpperInvariant()
                if (-not $map.ContainsKey($exe) -or $map[$exe] -lt $_.LastWriteTime) {
                    $map[$exe] = $_.LastWriteTime
                }
            }
        }
    } catch {
        Write-Verbose "Prefetch scan failed: $($_.Exception.Message)"
    }

    $map
}

function Invoke-StaleAppsScan {
    [CmdletBinding()]
    param(
        [int]$ThresholdDays = 90
    )

    $cutoff   = (Get-Date).AddDays(-$ThresholdDays)
    $prefetch = Get-PrefetchIndex
    $index    = Get-InstalledProgramIndex

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $index) {
        if ($p.Source -eq 'Appx') { continue }

        $exeName = $null
        if ($p.InstallLocation -and (Test-Path -LiteralPath $p.InstallLocation)) {
            $exe = @(Get-ChildItem -LiteralPath $p.InstallLocation -Filter '*.exe' -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($exe.Count -gt 0) { $exeName = $exe[0].Name }
        }

        $lastRun = $null
        if ($exeName) {
            $upper = $exeName.ToUpperInvariant()
            if ($prefetch.ContainsKey($upper)) {
                $lastRun = $prefetch[$upper]
            }
        }

        if ($null -eq $lastRun) {
            $results.Add([pscustomobject]@{
                Program       = $p
                LastRun       = $null
                AgeDays       = [int]::MaxValue
                Reason        = 'no-prefetch-entry'
            }) | Out-Null
            continue
        }

        if ($lastRun -lt $cutoff) {
            $results.Add([pscustomobject]@{
                Program   = $p
                LastRun   = $lastRun
                AgeDays   = [int]((Get-Date) - $lastRun).TotalDays
                Reason    = 'stale-mtime'
            }) | Out-Null
        }
    }

    $results | Sort-Object -Property AgeDays -Descending
}

function Register-StaleAppsActions {
    [CmdletBinding()]
    param()

    Register-Action @{
        Id          = 'cleanup.stale-apps.scan'
        Category    = 'Deep Cleanup'
        Name        = 'Scan for apps unused beyond threshold (Prefetch-based)'
        Description = 'Cross-references installed Win32 programs against Windows Prefetch timestamps to flag apps that have not run within the threshold (default 90 days).'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $false
        Context     = @{ ThresholdDays = 90 }
        Invoke      = {
            param($c)
            $items = Invoke-StaleAppsScan -ThresholdDays $c.ThresholdDays
            $count = @($items).Count
            Write-W10Log -Level 'Info' -ActionId 'cleanup.stale-apps.scan' -Message "scan complete" -Data @{
                count           = $count
                thresholdDays   = $c.ThresholdDays
                prefetchEnabled = (Test-Path (Join-Path $env:WINDIR 'Prefetch'))
            }
            $items
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Cross-reference Win32 install registry against Prefetch mtime; threshold $($c.ThresholdDays) days"
        }
    }
}

Register-Enumerator 'Register-StaleAppsActions'
