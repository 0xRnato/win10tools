function Get-NormalizedAppName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Value)

    $n = $Value.ToLowerInvariant()
    $n = $n -replace '[^a-z0-9]', ''
    $n
}

function Test-PathLooksOrphan {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$InstalledNames,

        [string[]]$InstalledPublishers = @()
    )

    $nNorm = Get-NormalizedAppName $Name

    foreach ($installed in $InstalledNames) {
        $iNorm = Get-NormalizedAppName $installed
        if ($iNorm -eq $nNorm) {
            return @{ Confidence = 'none'; Match = $installed }
        }
        if ($nNorm.Length -ge 4 -and ($iNorm.Contains($nNorm) -or $nNorm.Contains($iNorm))) {
            return @{ Confidence = 'none'; Match = $installed }
        }
    }

    foreach ($pub in $InstalledPublishers) {
        $firstWord = ($pub -split '[\s.,;:()]+')[0]
        if (-not $firstWord) { continue }
        $fwNorm = Get-NormalizedAppName $firstWord
        if ($fwNorm.Length -ge 4 -and $nNorm.Contains($fwNorm)) {
            return @{ Confidence = 'Medium'; Match = $pub }
        }
    }

    @{ Confidence = 'High'; Match = $null }
}

function Invoke-LeftoverScan {
    [CmdletBinding()]
    param(
        [ValidateSet('User', 'Machine', 'All')]
        [string]$Scope = 'All'
    )

    $index = Get-InstalledProgramIndex
    $installedNames      = @($index | ForEach-Object { $_.Name }      | Sort-Object -Unique)
    $installedPublishers = @($index | ForEach-Object { $_.Publisher } | Where-Object { $_ } | Sort-Object -Unique)

    $roots = @()
    if ($Scope -in 'User', 'All') {
        $roots += @(
            @{ Path = $env:APPDATA;                                 Kind = 'user-appdata'        }
            @{ Path = $env:LOCALAPPDATA;                            Kind = 'user-localappdata'   }
            @{ Path = (Join-Path $env:LOCALAPPDATA 'Programs');     Kind = 'user-programs'       }
        )
    }
    if ($Scope -in 'Machine', 'All') {
        $roots += @(
            @{ Path = $env:ProgramData;                             Kind = 'programdata'         }
            @{ Path = $env:ProgramFiles;                            Kind = 'program-files'       }
            @{ Path = ${env:ProgramFiles(x86)};                     Kind = 'program-files-x86'   }
        )
    }

    $candidates = [System.Collections.Generic.List[object]]::new()

    foreach ($r in $roots) {
        $path = $r.Path
        if (-not $path -or -not (Test-Path -LiteralPath $path)) { continue }

        Get-ChildItem -LiteralPath $path -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $verdict = Test-PathLooksOrphan -Name $_.Name -InstalledNames $installedNames -InstalledPublishers $installedPublishers
            if ($verdict.Confidence -eq 'none') { return }

            $size = 0
            try {
                $size = (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
            } catch { $size = 0 }

            $candidates.Add([pscustomobject]@{
                Path        = $_.FullName
                Name        = $_.Name
                Kind        = $r.Kind
                Confidence  = $verdict.Confidence
                Size        = [int64]($size -as [int64])
                Created     = $_.CreationTime
                LastWritten = $_.LastWriteTime
            }) | Out-Null
        }
    }

    $shortcutRoots = @()
    if ($Scope -in 'User', 'All') {
        $shortcutRoots += @(
            (Join-Path $env:USERPROFILE 'Desktop')
            (Join-Path $env:APPDATA    'Microsoft\Windows\Start Menu\Programs')
        )
    }
    if ($Scope -in 'Machine', 'All') {
        $shortcutRoots += @(
            (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs')
        )
    }

    foreach ($sr in $shortcutRoots) {
        if (-not (Test-Path -LiteralPath $sr)) { continue }
        Get-ChildItem -LiteralPath $sr -Filter '*.lnk' -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $sh = New-Object -ComObject WScript.Shell
                $lnk = $sh.CreateShortcut($_.FullName)
                $target = $lnk.TargetPath
                if (-not $target) { return }
                if (Test-Path -LiteralPath $target) { return }

                $candidates.Add([pscustomobject]@{
                    Path       = $_.FullName
                    Name       = $_.BaseName
                    Kind       = 'shortcut-dead-target'
                    Confidence = 'High'
                    Size       = [int64]$_.Length
                    Target     = $target
                }) | Out-Null
            } catch {
                Write-Verbose "shortcut inspect: $($_.FullName) - $($_.Exception.Message)"
            }
        }
    }

    $candidates | Sort-Object -Property @{Expression='Confidence';Descending=$false}, @{Expression='Size';Descending=$true}
}

function Move-LeftoverResidueToQuarantine {
    [CmdletBinding()]
    param(
        [ValidateSet('User', 'Machine', 'All')]
        [string]$Scope = 'User',

        [ValidateSet('High', 'Medium')]
        [string]$MinimumConfidence = 'High',

        [int]$MaxItems = 25
    )

    $items = @(Invoke-LeftoverScan -Scope $Scope | Where-Object {
        $_.Confidence -eq 'High' -or ($MinimumConfidence -eq 'Medium' -and $_.Confidence -eq 'Medium')
    } | Select-Object -First $MaxItems)

    if ($items.Count -eq 0) {
        return [pscustomobject]@{ BatchPath = $null; Total = 0; Moved = 0; Failed = 0; Items = @() }
    }

    $batch = New-QuarantineBatch -Label "leftover-$($Scope.ToLowerInvariant())"
    $moved = 0
    $failed = 0
    $results = foreach ($item in $items) {
        try {
            $target = Move-ToQuarantine -Path $item.Path -BatchPath $batch
            if ($target) { $moved++ }
            [pscustomobject]@{ Path = $item.Path; Target = $target; Status = if ($target) { 'moved' } else { 'skipped' }; Confidence = $item.Confidence }
        } catch {
            $failed++
            [pscustomobject]@{ Path = $item.Path; Target = $null; Status = 'error'; Confidence = $item.Confidence; Error = $_.Exception.Message }
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

function Register-LeftoverActions {
    [CmdletBinding()]
    param()

    Register-Action @{
        Id          = 'cleanup.leftover.scan-user'
        Category    = 'Deep Cleanup'
        Name        = 'Scan user scope for leftover residue'
        Description = 'Scans %APPDATA%, %LOCALAPPDATA%, and user Start-menu shortcuts for items that look orphaned from uninstalled programs.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $false
        Context     = @{ Scope = 'User' }
        Invoke      = {
            param($c)
            $items  = Invoke-LeftoverScan -Scope $c.Scope
            $total  = @($items).Count
            $high   = @($items | Where-Object { $_.Confidence -eq 'High'   }).Count
            $medium = @($items | Where-Object { $_.Confidence -eq 'Medium' }).Count
            Write-W10Log -Level 'Info' -ActionId 'cleanup.leftover.scan-user' -Message 'leftover scan' -Data @{
                total  = $total
                high   = $high
                medium = $medium
                scope  = $c.Scope
            }
            $items
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Scan user scope ($($c.Scope)) for orphaned AppData folders and dead shortcuts"
        }
    }

    Register-Action @{
        Id          = 'cleanup.leftover.quarantine-user'
        Category    = 'Deep Cleanup'
        Name        = 'Quarantine high-confidence user leftovers'
        Description = 'Moves up to 25 high-confidence orphaned user-scope residue items into the 30-day win10tools quarantine.'
        Risk        = 'Minor'
        Destructive = $true
        NeedsAdmin  = $false
        Context     = @{ Scope = 'User'; MinimumConfidence = 'High'; MaxItems = 25 }
        Invoke      = {
            param($c)
            $result = Move-LeftoverResidueToQuarantine -Scope $c.Scope -MinimumConfidence $c.MinimumConfidence -MaxItems $c.MaxItems
            Write-W10Log -Level 'Info' -ActionId 'cleanup.leftover.quarantine-user' -Message 'leftover residue quarantined' -Data @{
                total = $result.Total; moved = $result.Moved; failed = $result.Failed; batch = $result.BatchPath
            }
            $result
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Move up to $($c.MaxItems) high-confidence user leftovers to quarantine"
        }
    }

    Register-Action @{
        Id          = 'cleanup.leftover.scan-machine'
        Category    = 'Deep Cleanup'
        Name        = 'Scan machine scope for leftover residue'
        Description = 'Scans %PROGRAMDATA%, %PROGRAMFILES%, %PROGRAMFILES(X86)%, and machine Start-menu shortcuts for orphaned items.'
        Risk        = 'Minor'
        Destructive = $false
        NeedsAdmin  = $true
        Context     = @{ Scope = 'Machine' }
        Invoke      = {
            param($c)
            $items  = Invoke-LeftoverScan -Scope $c.Scope
            $total  = @($items).Count
            $high   = @($items | Where-Object { $_.Confidence -eq 'High'   }).Count
            $medium = @($items | Where-Object { $_.Confidence -eq 'Medium' }).Count
            Write-W10Log -Level 'Info' -ActionId 'cleanup.leftover.scan-machine' -Message 'leftover scan' -Data @{
                total  = $total
                high   = $high
                medium = $medium
                scope  = $c.Scope
            }
            $items
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Scan machine scope ($($c.Scope)) for orphaned residue"
        }
    }

    Register-Action @{
        Id          = 'cleanup.leftover.quarantine-machine'
        Category    = 'Deep Cleanup'
        Name        = 'Quarantine high-confidence machine leftovers'
        Description = 'Moves up to 25 high-confidence machine-scope residue items into the 30-day win10tools quarantine.'
        Risk        = 'Avoid'
        Destructive = $true
        NeedsAdmin  = $true
        Context     = @{ Scope = 'Machine'; MinimumConfidence = 'High'; MaxItems = 25 }
        Invoke      = {
            param($c)
            $result = Move-LeftoverResidueToQuarantine -Scope $c.Scope -MinimumConfidence $c.MinimumConfidence -MaxItems $c.MaxItems
            Write-W10Log -Level 'Info' -ActionId 'cleanup.leftover.quarantine-machine' -Message 'machine leftover residue quarantined' -Data @{
                total = $result.Total; moved = $result.Moved; failed = $result.Failed; batch = $result.BatchPath
            }
            $result
        }
        DryRunSummary = {
            param($c)
            "[DEEP-CLEAN] Move up to $($c.MaxItems) high-confidence machine leftovers to quarantine"
        }
    }
}

Register-Enumerator 'Register-LeftoverActions'
