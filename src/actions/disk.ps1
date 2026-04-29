function Invoke-DiskPathClear {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-W10Log -Level 'Info' -Message "path not present; skipping" -Data @{ path = $Path }
        return
    }

    $deleted = 0
    $failed  = 0
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $result = Remove-ItemSafely -Path $_.FullName
            if ($result.removed) { $deleted++ } else { $failed++ }
        } catch { $failed++ }
    }
    Write-W10Log -Level 'Info' -Message "cleared $deleted items ($failed locked)" -Data @{ path = $Path }
}

function Register-DiskActions {
    [CmdletBinding()]
    param()

    $defs = @(
        @{
            Id       = 'disk.clear-user-temp'
            Name     = 'Clear user temp folder'
            Path     = $env:TEMP
            Risk     = 'Safe'
            NeedsAdmin = $false
            Desc     = 'Removes files under %TEMP%. Open handles (locked files) are skipped.'
        }
        @{
            Id       = 'disk.clear-system-temp'
            Name     = 'Clear system temp (C:\Windows\Temp)'
            Path     = Join-Path $env:WINDIR 'Temp'
            Risk     = 'Minor'
            NeedsAdmin = $true
            Desc     = 'Removes files under C:\Windows\Temp. Locked files are skipped.'
        }
        @{
            Id       = 'disk.clear-crash-dumps'
            Name     = 'Clear crash dumps'
            Path     = Join-Path $env:LOCALAPPDATA 'CrashDumps'
            Risk     = 'Safe'
            NeedsAdmin = $false
            Desc     = 'Removes .dmp files from %LOCALAPPDATA%\CrashDumps.'
        }
        @{
            Id       = 'disk.clear-delivery-optimization-cache'
            Name     = 'Clear Delivery Optimization cache'
            Path     = 'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization'
            Risk     = 'Safe'
            NeedsAdmin = $true
            Desc     = 'Removes cached Windows Update delivery peers data.'
        }
    )

    foreach ($d in $defs) {
        Register-Action @{
            Id          = $d.Id
            Category    = 'Disk'
            Name        = $d.Name
            Description = $d.Desc
            Risk        = $d.Risk
            Destructive = $true
            NeedsAdmin  = $d.NeedsAdmin
            Context     = @{ Path = $d.Path }
            Invoke      = {
                param($c)
                Invoke-DiskPathClear -Path $c.Path
            }
            Check       = {
                param($c)
                if (-not (Test-Path -LiteralPath $c.Path)) { return $true }
                @(Get-ChildItem -LiteralPath $c.Path -Force -ErrorAction SilentlyContinue).Count -eq 0
            }
            DryRunSummary = {
                param($c)
                "[DISK] Remove items under $($c.Path)"
            }
        }
    }

    Register-Action @{
        Id          = 'disk.empty-recycle-bin'
        Category    = 'Disk'
        Name        = 'Empty Recycle Bin'
        Description = 'Empties the current user Recycle Bin. Irreversible.'
        Risk        = 'Minor'
        Destructive = $true
        NeedsAdmin  = $false
        Invoke      = {
            try {
                Clear-RecycleBin -Force -ErrorAction Stop
                Write-W10Log -Level 'Info' -ActionId 'disk.empty-recycle-bin' -Message 'recycle bin emptied'
            } catch {
                Write-W10Log -Level 'Warn' -ActionId 'disk.empty-recycle-bin' -Message 'empty failed' -Data @{ error = $_.Exception.Message }
                throw
            }
        }
        DryRunSummary = { '[DISK] Clear-RecycleBin -Force' }
    }

    Register-Action @{
        Id          = 'disk.clear-wu-cache'
        Category    = 'Disk'
        Name        = 'Clear Windows Update cache'
        Description = 'Stops wuauserv + bits, removes SoftwareDistribution\Download, restarts services. Windows will re-download pending updates.'
        Risk        = 'Minor'
        Destructive = $true
        NeedsAdmin  = $true
        Invoke      = {
            $services = 'wuauserv', 'bits'
            foreach ($s in $services) {
                try { Stop-Service -Name $s -Force -ErrorAction Stop } catch { Write-Verbose "stop $s : $($_.Exception.Message)" }
            }
            $dl = Join-Path $env:WINDIR 'SoftwareDistribution\Download'
            if (Test-Path $dl) { Remove-ItemSafely -Path $dl | Out-Null }
            foreach ($s in $services) {
                try { Start-Service -Name $s -ErrorAction Stop } catch { Write-Verbose "start $s : $($_.Exception.Message)" }
            }
            Write-W10Log -Level 'Info' -ActionId 'disk.clear-wu-cache' -Message 'wu cache cleared'
        }
        DryRunSummary = { '[DISK] Stop wuauserv/bits, wipe SoftwareDistribution\Download, restart services' }
    }

    Register-Action @{
        Id          = 'disk.run-cleanmgr'
        Category    = 'Disk'
        Name        = 'Run Disk Cleanup (cleanmgr /sagerun:1)'
        Description = 'Runs Windows Disk Cleanup using the win10tools preset. First run sets the preset via /sageset:1.'
        Risk        = 'Safe'
        Destructive = $true
        NeedsAdmin  = $true
        Invoke      = {
            $sagesetKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
            $stateFlag  = 'StateFlags0001'
            $markerKey  = 'HKCU:\Software\win10tools'
            $markerName = 'CleanmgrPresetApplied'

            $alreadyApplied = $false
            try {
                $m = Get-ItemProperty -Path $markerKey -Name $markerName -ErrorAction SilentlyContinue
                if ($m -and $m.$markerName -eq 1) { $alreadyApplied = $true }
            } catch { Write-Verbose "preset marker lookup: $($_.Exception.Message)" }

            if (-not $alreadyApplied) {
                Get-ChildItem -Path $sagesetKey -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        Set-ItemProperty -Path $_.PsPath -Name $stateFlag -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
                    } catch { Write-Verbose "preset write: $($_.Exception.Message)" }
                }
                if (-not (Test-Path $markerKey)) { New-Item -Path $markerKey -Force | Out-Null }
                Set-ItemProperty -Path $markerKey -Name $markerName -Value 1 -Type DWord -Force
            }

            Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:1' -Wait -ErrorAction Stop
            Write-W10Log -Level 'Info' -ActionId 'disk.run-cleanmgr' -Message 'cleanmgr completed'
        }
        DryRunSummary = { '[DISK] cleanmgr.exe /sagerun:1 (first run writes preset under /sageset:1)' }
    }

    Register-Action @{
        Id          = 'disk.clear-thumbnail-cache'
        Category    = 'Disk'
        Name        = 'Clear thumbnail cache'
        Description = 'Removes thumbcache_*.db in %LOCALAPPDATA%\Microsoft\Windows\Explorer. Windows will regenerate.'
        Risk        = 'Safe'
        Destructive = $true
        NeedsAdmin  = $false
        Invoke      = {
            $thumbs = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
            if (-not (Test-Path $thumbs)) { return }
            Get-ChildItem -LiteralPath $thumbs -Filter 'thumbcache_*.db' -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-ItemSafely -Path $_.FullName | Out-Null } catch { Write-Verbose "locked: $($_.FullName)" }
            }
            Get-ChildItem -LiteralPath $thumbs -Filter 'iconcache_*.db' -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-ItemSafely -Path $_.FullName | Out-Null } catch { Write-Verbose "locked: $($_.FullName)" }
            }
            Write-W10Log -Level 'Info' -ActionId 'disk.clear-thumbnail-cache' -Message 'thumbnail + icon caches cleared'
        }
        DryRunSummary = { '[DISK] Delete thumbcache_*.db and iconcache_*.db under %LOCALAPPDATA%\Microsoft\Windows\Explorer' }
    }

    $browsers = @(
        @{ Id='chrome';  Proc='chrome';   Path=(Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache') }
        @{ Id='edge';    Proc='msedge';   Path=(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache') }
        @{ Id='firefox'; Proc='firefox';  Path=(Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles') }
        @{ Id='brave';   Proc='brave';    Path=(Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data\Default\Cache') }
    )

    foreach ($b in $browsers) {
        Register-Action @{
            Id          = "disk.clear-browser-cache-$($b.Id)"
            Category    = 'Disk'
            Name        = "Clear $($b.Id) browser cache"
            Description = "Removes browser cache for $($b.Id). Skipped if the browser is running."
            Risk        = 'Minor'
            Destructive = $true
            NeedsAdmin  = $false
            Context     = @{ ProcName = $b.Proc; CachePath = $b.Path; Browser = $b.Id }
            Check       = {
                param($c)
                if (-not (Test-Path -LiteralPath $c.CachePath)) { return $true }
                $false
            }
            Invoke      = {
                param($c)
                $running = @(Get-Process -Name $c.ProcName -ErrorAction SilentlyContinue)
                if ($running.Count -gt 0) {
                    throw "$($c.Browser) is running; close it first"
                }
                if (Test-Path -LiteralPath $c.CachePath) {
                    Invoke-DiskPathClear -Path $c.CachePath
                }
            }
            DryRunSummary = {
                param($c)
                "[DISK] Clear $($c.Browser) cache at $($c.CachePath) (only if $($c.ProcName) not running)"
            }
        }
    }
}

Register-Enumerator 'Register-DiskActions'
