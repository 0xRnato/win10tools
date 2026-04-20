function Get-ActionDryRun {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Action
    )

    if ($Action.DryRunSummary -is [scriptblock]) {
        try {
            $summary = & $Action.DryRunSummary $Action.Context
            if ($summary) { return [string]$summary }
        } catch {
            Write-W10Log -Level 'Warn' -Message "DryRunSummary threw" -ActionId $Action.Id -Data @{ error = $_.Exception.Message }
        }
    }

    $flags = @()
    if ($Action.Destructive) { $flags += 'destructive' }
    if ($Action.NeedsReboot) { $flags += 'needs-reboot' }
    if ($Action.NeedsAdmin)  { $flags += 'needs-admin' }
    $tail = if ($flags.Count) { ' [' + ($flags -join ', ') + ']' } else { '' }

    "[$($Action.Risk.ToUpper())] $($Action.Category) / $($Action.Name)$tail"
}

function Invoke-Action {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Action,

        [switch]$DryRun,
        [switch]$SkipCheck
    )

    $result = [ordered]@{
        actionId = $Action.Id
        status   = 'pending'
        skipped  = $false
        error    = $null
        duration = $null
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if ($DryRun) {
            Write-W10Log -Level 'Info' -ActionId $Action.Id -Message "dry-run: $(Get-ActionDryRun $Action)"
            $result.status = 'dry-run'
            return [pscustomobject]$result
        }

        if ($Action.NeedsAdmin -and -not (Test-IsAdmin)) {
            throw "Action requires Administrator rights"
        }

        if (-not $SkipCheck -and $Action.Check -is [scriptblock]) {
            $alreadyApplied = $false
            try {
                $alreadyApplied = [bool](& $Action.Check $Action.Context)
            } catch {
                Write-W10Log -Level 'Warn' -ActionId $Action.Id -Message "Check threw" -Data @{ error = $_.Exception.Message }
            }

            if ($alreadyApplied) {
                $result.status  = 'skipped'
                $result.skipped = $true
                Write-W10Log -Level 'Info' -ActionId $Action.Id -Message 'already applied - skipped'
                return [pscustomobject]$result
            }
        }

        Write-W10Log -Level 'Info' -ActionId $Action.Id -Message "invoking: $($Action.Name)"
        & $Action.Invoke $Action.Context
        $result.status = 'applied'
        Write-W10Log -Level 'Info' -ActionId $Action.Id -Message 'applied'
    }
    catch {
        $result.status = 'error'
        $result.error  = $_.Exception.Message
        Write-W10Log -Level 'Error' -ActionId $Action.Id -Message 'invoke failed' -Data @{ error = $_.Exception.Message }
    }
    finally {
        $sw.Stop()
        $result.duration = [int]$sw.Elapsed.TotalMilliseconds
    }

    [pscustomobject]$result
}

function Invoke-ActionRevert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Action
    )

    if ($Action.Revert -isnot [scriptblock]) {
        throw "Action '$($Action.Id)' has no Revert scriptblock"
    }

    try {
        Write-W10Log -Level 'Info' -ActionId $Action.Id -Message 'reverting'
        & $Action.Revert $Action.Context
        Write-W10Log -Level 'Info' -ActionId $Action.Id -Message 'reverted'
        return $true
    } catch {
        Write-W10Log -Level 'Error' -ActionId $Action.Id -Message 'revert failed' -Data @{ error = $_.Exception.Message }
        return $false
    }
}

function Invoke-ActionBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable[]]$Actions,

        [switch]$DryRun,
        [switch]$SkipRestorePoint
    )

    $results = @()
    $hasDestructive = $Actions | Where-Object { $_.Destructive } | Select-Object -First 1

    if (-not $DryRun -and $hasDestructive -and -not $SkipRestorePoint) {
        if (Get-Command New-AutoRestorePoint -ErrorAction SilentlyContinue) {
            try {
                New-AutoRestorePoint -Description "win10tools: batch $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            } catch {
                Write-W10Log -Level 'Warn' -Message 'restore point creation failed; continuing' -Data @{ error = $_.Exception.Message }
            }
        }
    }

    foreach ($a in $Actions) {
        $results += Invoke-Action -Action $a -DryRun:$DryRun
    }

    $appliedIds   = @($results | Where-Object { $_.status -eq 'applied' } | ForEach-Object { $_.actionId })
    $rebootNeeded = [bool](@($Actions | Where-Object { $_.NeedsReboot -and ($_.Id -in $appliedIds) }).Count)

    $summary = [ordered]@{
        total       = @($results).Count
        applied     = @($results | Where-Object { $_.status -eq 'applied' }).Count
        skipped     = @($results | Where-Object { $_.status -eq 'skipped' }).Count
        dryRun      = @($results | Where-Object { $_.status -eq 'dry-run' }).Count
        errors      = @($results | Where-Object { $_.status -eq 'error' }).Count
        needsReboot = $rebootNeeded
    }

    Write-W10Log -Level 'Info' -Message 'batch complete' -Data $summary

    [pscustomobject]@{
        summary = [pscustomobject]$summary
        results = $results
    }
}
