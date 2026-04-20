function ConvertTo-ActionRow {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [hashtable]$Action
    )

    process {
        $flags = @()
        if ($Action.Destructive) { $flags += 'destructive' }
        if ($Action.NeedsReboot) { $flags += 'reboot' }
        if ($Action.NeedsAdmin)  { $flags += 'admin' }

        [pscustomobject]@{
            Selected    = $false
            Id          = [string]$Action.Id
            Name        = [string]$Action.Name
            Risk        = [string]$Action.Risk
            Category    = [string]$Action.Category
            Flags       = ($flags -join ', ')
            Description = [string]$Action.Description
            ActionRef   = $Action
        }
    }
}

function Get-SelectedRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RowsByCategory
    )

    $selected = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $RowsByCategory.Keys) {
        foreach ($row in $RowsByCategory[$key]) {
            if ($row.Selected) {
                $selected.Add($row) | Out-Null
            }
        }
    }
    $selected
}

function Measure-RowSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RowsByCategory
    )

    $total = 0
    $avoid = 0
    $destructive = 0
    foreach ($key in $RowsByCategory.Keys) {
        foreach ($row in $RowsByCategory[$key]) {
            if ($row.Selected) {
                $total++
                if ($row.Risk -eq 'Avoid')      { $avoid++ }
                if ($row.ActionRef.Destructive) { $destructive++ }
            }
        }
    }

    [pscustomobject]@{
        Total       = $total
        Avoid       = $avoid
        Destructive = $destructive
    }
}

function Format-DryRunReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$SelectedRows
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("=== Dry Run ===") | Out-Null
    $lines.Add("Selected actions: $($SelectedRows.Count)") | Out-Null
    $lines.Add("") | Out-Null

    foreach ($row in $SelectedRows) {
        $summary = Get-ActionDryRun -Action $row.ActionRef
        $lines.Add("[$($row.Risk.ToUpper())] $summary") | Out-Null
    }

    $lines -join [Environment]::NewLine
}

function Format-RunReport {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $BatchResult
    )

    $s = $BatchResult.summary
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("=== Run complete ===") | Out-Null
    $lines.Add("Total:       $($s.total)") | Out-Null
    $lines.Add("Applied:     $($s.applied)") | Out-Null
    $lines.Add("Skipped:     $($s.skipped)") | Out-Null
    $lines.Add("Errors:      $($s.errors)") | Out-Null
    $lines.Add("Dry-run:     $($s.dryRun)") | Out-Null
    $lines.Add("Reboot?      $($s.needsReboot)") | Out-Null
    $lines.Add("") | Out-Null

    foreach ($r in $BatchResult.results) {
        $err = if ($r.error) { " - $($r.error)" } else { '' }
        $lines.Add("[$($r.status)] $($r.actionId) (${($r.duration)}ms)$err") | Out-Null
    }

    $lines -join [Environment]::NewLine
}

function Update-DeepCleanupThreshold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ThresholdDays
    )

    foreach ($action in (Get-Actions -Category 'Deep Cleanup')) {
        if ($action.Context -and $action.Context.ContainsKey('ThresholdDays')) {
            $action.Context.ThresholdDays = $ThresholdDays
        }
    }
}
