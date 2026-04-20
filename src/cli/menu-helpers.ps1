function Get-RiskConsoleColor {
    [CmdletBinding()]
    [OutputType([System.ConsoleColor])]
    param(
        [Parameter(Mandatory)]
        [string]$Risk
    )

    switch ($Risk) {
        'Safe'  { [System.ConsoleColor]::Green  }
        'Minor' { [System.ConsoleColor]::Yellow }
        'Avoid' { [System.ConsoleColor]::Red    }
        default { [System.ConsoleColor]::Gray   }
    }
}

function Format-CategoryHeader {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RowsByCategory
    )

    $stats = Measure-RowSelection -RowsByCategory $RowsByCategory
    $lines = @(
        ''
        '=== win10tools ==='
        ("session: $(Get-W10SessionId)   admin: $(Test-IsAdmin)   selected: $($stats.Total)   AVOID selected: $($stats.Avoid)")
        ''
    )
    $lines
}

function Format-CategoryList {
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RowsByCategory
    )

    $index = 0
    $names = @($RowsByCategory.Keys | Sort-Object)
    foreach ($name in $names) {
        $index++
        $rows     = $RowsByCategory[$name]
        $selected = @($rows | Where-Object { $_.Selected }).Count
        $suffix   = if ($selected -gt 0) { " [$selected]" } else { '' }

        [pscustomobject]@{
            Index    = $index
            Category = $name
            Total    = $rows.Count
            Selected = $selected
            Display  = "  {0,2}) {1,-15} ({2} actions){3}" -f $index, $name, $rows.Count, $suffix
        }
    }
}

function Format-ActionListLine {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][pscustomobject]$Row
    )

    $mark = if ($Row.Selected) { 'x' } else { ' ' }
    $risk = $Row.Risk.ToUpper().PadRight(5)
    $flagPart = if ($Row.Flags) { "  [$($Row.Flags)]" } else { '' }
    $display  = "  [{0}] #{1,-3} {2}  {3}{4}" -f $mark, $Index, $risk, $Row.Name, $flagPart

    [pscustomobject]@{
        Index   = $Index
        Row     = $Row
        Display = $display
        Color   = Get-RiskConsoleColor -Risk $Row.Risk
    }
}

function ConvertFrom-SelectionInput {
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$SelectionText
    )

    if ([string]::IsNullOrWhiteSpace($SelectionText)) { return @() }

    $result = [System.Collections.Generic.HashSet[int]]::new()

    foreach ($chunk in ($SelectionText -split '[,\s]+')) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }

        if ($chunk -match '^(\d+)-(\d+)$') {
            $start = [int]$matches[1]
            $end   = [int]$matches[2]
            if ($end -lt $start) {
                $tmp = $start; $start = $end; $end = $tmp
            }
            for ($i = $start; $i -le $end; $i++) { [void]$result.Add($i) }
            continue
        }

        if ($chunk -match '^\d+$') {
            [void]$result.Add([int]$chunk)
            continue
        }
    }

    @($result | Sort-Object)
}

function Switch-RowSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]]$Rows,

        [Parameter(Mandatory)]
        [int[]]$Indices
    )

    foreach ($i in $Indices) {
        if ($i -lt 1 -or $i -gt $Rows.Count) { continue }
        $Rows[$i - 1].Selected = -not $Rows[$i - 1].Selected
    }
}

function Set-RowsSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject[]]$Rows,

        [Parameter(Mandatory)]
        [bool]$Selected,

        [ValidateSet('All', 'Safe', 'Minor', 'Avoid')]
        [string]$Filter = 'All'
    )

    foreach ($r in $Rows) {
        if ($Filter -eq 'All' -or $r.Risk -eq $Filter) {
            $r.Selected = $Selected
        }
    }
}
