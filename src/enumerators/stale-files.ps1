function Get-NtfsLastAccessEnabled {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $out = & fsutil behavior query DisableLastAccess 2>&1 | Out-String
        if ($out -match '=\s*(\d+)') {
            $value = [int]$matches[1]
            return ($value -eq 0)
        }
    } catch {
        Write-Verbose "fsutil query failed: $($_.Exception.Message)"
    }
    return $false
}

function Get-StaleItemTouchTime {
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    $candidates = @()
    if ($Item.LastAccessTime) { $candidates += $Item.LastAccessTime }
    if ($Item.LastWriteTime)  { $candidates += $Item.LastWriteTime }
    if ($Item.CreationTime)   { $candidates += $Item.CreationTime }

    $max = $candidates | Sort-Object -Descending | Select-Object -First 1
    if ($max) { $max } else { [datetime]::MinValue }
}

function Invoke-StaleFilesScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [int]$ThresholdDays = 90,

        [int]$MaxDepth = 2,

        [int]$MaxResults = 500
    )

    $cutoff  = (Get-Date).AddDays(-$ThresholdDays)
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($root in $Paths) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        $stack = [System.Collections.Generic.Stack[object]]::new()
        $stack.Push(@{ Path = $root; Depth = 0 })

        while ($stack.Count -gt 0 -and $results.Count -lt $MaxResults) {
            $entry = $stack.Pop()
            $path  = $entry.Path
            $depth = $entry.Depth

            try {
                $items = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue)
            } catch { continue }

            foreach ($item in $items) {
                if ($results.Count -ge $MaxResults) { break }

                $touch = Get-StaleItemTouchTime -Item $item
                if ($touch -ge $cutoff) {
                    if ($item.PSIsContainer -and $depth -lt $MaxDepth) {
                        $stack.Push(@{ Path = $item.FullName; Depth = $depth + 1 })
                    }
                    continue
                }

                $size = 0
                if ($item.PSIsContainer) {
                    try {
                        $size = (Get-ChildItem -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum).Sum
                    } catch { $size = 0 }
                } else {
                    $size = [int64]$item.Length
                }

                $results.Add([pscustomobject]@{
                    Path        = $item.FullName
                    IsContainer = [bool]$item.PSIsContainer
                    Size        = [int64]($size -as [int64])
                    LastTouched = $touch
                    AgeDays     = [int]((Get-Date) - $touch).TotalDays
                    Root        = $root
                }) | Out-Null
            }
        }
    }

    $results | Sort-Object -Property @{Expression='AgeDays';Descending=$true}, @{Expression='Size';Descending=$true}
}

function Move-StaleFilesToQuarantine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths,

        [int]$ThresholdDays = 90,
        [int]$MaxDepth = 2,
        [int]$MaxItems = 25,
        [string]$Label = 'stale-files'
    )

    $items = @(Invoke-StaleFilesScan -Paths $Paths -ThresholdDays $ThresholdDays -MaxDepth $MaxDepth -MaxResults $MaxItems)
    if ($items.Count -eq 0) {
        return [pscustomobject]@{ BatchPath = $null; Total = 0; Moved = 0; Failed = 0; Items = @() }
    }

    $batch = New-QuarantineBatch -Label $Label
    $moved = 0
    $failed = 0
    $results = foreach ($item in $items) {
        try {
            $target = Move-ToQuarantine -Path $item.Path -BatchPath $batch
            if ($target) { $moved++ }
            [pscustomobject]@{ Path = $item.Path; Target = $target; Status = if ($target) { 'moved' } else { 'skipped' } }
        } catch {
            $failed++
            [pscustomobject]@{ Path = $item.Path; Target = $null; Status = 'error'; Error = $_.Exception.Message }
        }
    }

    [pscustomobject]@{
        BatchPath = $batch
        Total     = $items.Count
        Moved     = $moved
        Failed    = $failed
        Items     = @($results)
    }
}

function Register-StaleFilesActions {
    [CmdletBinding()]
    param()

    $userFolders = @(
        (Join-Path $env:USERPROFILE 'Downloads')
        (Join-Path $env:USERPROFILE 'Documents')
        (Join-Path $env:USERPROFILE 'Desktop')
    )

    Register-Action @{
        Id          = 'cleanup.stale-files.scan-user-folders'
        Category    = 'Deep Cleanup'
        Name        = 'Scan user folders for stale files (Downloads / Documents / Desktop)'
        Description = 'Reports files under the user folders that have not been touched within the configured threshold (default 90 days).'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $false
        Context     = @{ Paths = $userFolders; ThresholdDays = 90 }
        Invoke      = {
            param($c)
            $items = Invoke-StaleFilesScan -Paths $c.Paths -ThresholdDays $c.ThresholdDays
            $count = @($items).Count
            $totalBytes = (@($items) | Measure-Object -Property Size -Sum).Sum
            Write-W10Log -Level 'Info' -ActionId 'cleanup.stale-files.scan-user-folders' -Message "scan complete" -Data @{
                count       = $count
                totalBytes  = [int64]($totalBytes -as [int64])
                thresholdDays = $c.ThresholdDays
                lastAccessEnabled = Get-NtfsLastAccessEnabled
            }
            $items
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Scan $($c.Paths.Count) user folders; threshold $($c.ThresholdDays) days"
        }
    }

    Register-Action @{
        Id          = 'cleanup.stale-files.quarantine-user-folders'
        Category    = 'Deep Cleanup'
        Name        = 'Quarantine stale files from user folders'
        Description = 'Moves up to 25 stale files or folders from Downloads, Documents, and Desktop into the 30-day win10tools quarantine.'
        Risk        = 'Avoid'
        Destructive = $true
        NeedsAdmin  = $false
        Context     = @{ Paths = $userFolders; ThresholdDays = 90; MaxDepth = 2; MaxItems = 25; Label = 'stale-user-folders' }
        Invoke      = {
            param($c)
            $result = Move-StaleFilesToQuarantine -Paths $c.Paths -ThresholdDays $c.ThresholdDays -MaxDepth $c.MaxDepth -MaxItems $c.MaxItems -Label $c.Label
            Write-W10Log -Level 'Info' -ActionId 'cleanup.stale-files.quarantine-user-folders' -Message 'stale files quarantined' -Data @{
                total = $result.Total; moved = $result.Moved; failed = $result.Failed; batch = $result.BatchPath
            }
            $result
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Move up to $($c.MaxItems) stale user-folder items to quarantine; threshold $($c.ThresholdDays) days"
        }
    }

    $appDataFolders = @(
        $env:APPDATA
        $env:LOCALAPPDATA
    )

    Register-Action @{
        Id          = 'cleanup.stale-files.scan-appdata'
        Category    = 'Deep Cleanup'
        Name        = 'Scan AppData for stale items'
        Description = 'Reports top-level AppData items older than the threshold. Non-destructive - lists candidates.'
        Risk        = 'Minor'
        Destructive = $false
        NeedsAdmin  = $false
        Context     = @{ Paths = $appDataFolders; ThresholdDays = 90; MaxDepth = 1 }
        Invoke      = {
            param($c)
            $items = Invoke-StaleFilesScan -Paths $c.Paths -ThresholdDays $c.ThresholdDays -MaxDepth $c.MaxDepth
            $count = @($items).Count
            $totalBytes = (@($items) | Measure-Object -Property Size -Sum).Sum
            Write-W10Log -Level 'Info' -ActionId 'cleanup.stale-files.scan-appdata' -Message "scan complete" -Data @{
                count       = $count
                totalBytes  = [int64]($totalBytes -as [int64])
                thresholdDays = $c.ThresholdDays
            }
            $items
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Scan %APPDATA% and %LOCALAPPDATA% (depth $($c.MaxDepth)); threshold $($c.ThresholdDays) days"
        }
    }

    Register-Action @{
        Id          = 'cleanup.stale-files.quarantine-appdata'
        Category    = 'Deep Cleanup'
        Name        = 'Quarantine stale AppData items'
        Description = 'Moves up to 25 stale top-level AppData items into the 30-day win10tools quarantine.'
        Risk        = 'Avoid'
        Destructive = $true
        NeedsAdmin  = $false
        Context     = @{ Paths = $appDataFolders; ThresholdDays = 90; MaxDepth = 1; MaxItems = 25; Label = 'stale-appdata' }
        Invoke      = {
            param($c)
            $result = Move-StaleFilesToQuarantine -Paths $c.Paths -ThresholdDays $c.ThresholdDays -MaxDepth $c.MaxDepth -MaxItems $c.MaxItems -Label $c.Label
            Write-W10Log -Level 'Info' -ActionId 'cleanup.stale-files.quarantine-appdata' -Message 'stale AppData items quarantined' -Data @{
                total = $result.Total; moved = $result.Moved; failed = $result.Failed; batch = $result.BatchPath
            }
            $result
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Move up to $($c.MaxItems) stale AppData items to quarantine; threshold $($c.ThresholdDays) days"
        }
    }
}

Register-Enumerator 'Register-StaleFilesActions'
