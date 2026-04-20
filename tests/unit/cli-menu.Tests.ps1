BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/core/runner.ps1')
    . (Join-Path $script:repoRoot 'src/core/elevation.ps1')
    . (Join-Path $script:repoRoot 'src/ui/main-window-helpers.ps1')
    . (Join-Path $script:repoRoot 'src/cli/menu-helpers.ps1')

    $script:logRoot = Join-Path $env:TEMP ("w10t-cli-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false

    function New-CliRow {
        param(
            [string]$Id,
            [string]$Risk = 'Safe',
            [bool]$Selected = $false,
            [string]$Category = 'Test'
        )
        $action = @{
            Id=$Id; Category=$Category; Name="n-$Id"; Description="d-$Id"; Risk=$Risk
            Destructive=$false; NeedsReboot=$false; NeedsAdmin=$false
            Context=@{}; Invoke={}; Check=$null; Revert=$null
            DryRunSummary={ "[$Category] n-$Id" }
        }
        $row = $action | ConvertTo-ActionRow
        $row.Selected = $Selected
        $row
    }
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-RiskConsoleColor' {
    It 'maps Safe to Green' {
        Get-RiskConsoleColor -Risk 'Safe'  | Should -Be ([System.ConsoleColor]::Green)
    }
    It 'maps Minor to Yellow' {
        Get-RiskConsoleColor -Risk 'Minor' | Should -Be ([System.ConsoleColor]::Yellow)
    }
    It 'maps Avoid to Red' {
        Get-RiskConsoleColor -Risk 'Avoid' | Should -Be ([System.ConsoleColor]::Red)
    }
    It 'falls back to Gray for unknown values' {
        Get-RiskConsoleColor -Risk 'Mystery' | Should -Be ([System.ConsoleColor]::Gray)
    }
}

Describe 'ConvertFrom-SelectionInput' {
    It 'parses single numbers' {
        ConvertFrom-SelectionInput -SelectionText '3' | Should -Be @(3)
    }
    It 'parses comma-separated lists' {
        ConvertFrom-SelectionInput -SelectionText '1,2,5' | Should -Be @(1, 2, 5)
    }
    It 'expands ranges' {
        ConvertFrom-SelectionInput -SelectionText '3-6' | Should -Be @(3, 4, 5, 6)
    }
    It 'mixes singles and ranges' {
        ConvertFrom-SelectionInput -SelectionText '1,3-5,7' | Should -Be @(1, 3, 4, 5, 7)
    }
    It 'deduplicates repeated entries' {
        ConvertFrom-SelectionInput -SelectionText '1,1,1' | Should -Be @(1)
    }
    It 'returns empty array for whitespace input' {
        $r = @(ConvertFrom-SelectionInput -SelectionText '   ')
        $r.Count | Should -Be 0
    }
    It 'ignores non-numeric noise' {
        ConvertFrom-SelectionInput -SelectionText '2,abc,5' | Should -Be @(2, 5)
    }
}

Describe 'Switch-RowSelection' {
    It 'flips the selection state for the provided 1-based indices' {
        $rows = @(
            New-CliRow -Id 'r.1'
            New-CliRow -Id 'r.2'
            New-CliRow -Id 'r.3'
        )
        Switch-RowSelection -Rows $rows -Indices @(1, 3)
        $rows[0].Selected | Should -BeTrue
        $rows[1].Selected | Should -BeFalse
        $rows[2].Selected | Should -BeTrue
    }

    It 'ignores out-of-range indices' {
        $rows = @((New-CliRow -Id 'only'))
        { Switch-RowSelection -Rows $rows -Indices @(0, 5, -1) } | Should -Not -Throw
        $rows[0].Selected | Should -BeFalse
    }

    It 'toggling twice returns to original state' {
        $rows = @((New-CliRow -Id 't.1'))
        Switch-RowSelection -Rows $rows -Indices @(1)
        Switch-RowSelection -Rows $rows -Indices @(1)
        $rows[0].Selected | Should -BeFalse
    }
}

Describe 'Set-RowsSelection' {
    It 'turns all rows on when Filter is All' {
        $rows = @(
            New-CliRow -Id 'a' -Risk 'Safe'
            New-CliRow -Id 'b' -Risk 'Avoid'
        )
        Set-RowsSelection -Rows $rows -Selected $true -Filter 'All'
        $rows | ForEach-Object { $_.Selected | Should -BeTrue }
    }

    It 'only affects rows matching the filter' {
        $rows = @(
            New-CliRow -Id 'a' -Risk 'Safe'
            New-CliRow -Id 'b' -Risk 'Avoid'
            New-CliRow -Id 'c' -Risk 'Safe'
        )
        Set-RowsSelection -Rows $rows -Selected $true -Filter 'Safe'
        $rows[0].Selected | Should -BeTrue
        $rows[1].Selected | Should -BeFalse
        $rows[2].Selected | Should -BeTrue
    }

    It 'can also turn everything off' {
        $rows = @(
            New-CliRow -Id 'a' -Selected $true
            New-CliRow -Id 'b' -Selected $true
        )
        Set-RowsSelection -Rows $rows -Selected $false -Filter 'All'
        $rows | ForEach-Object { $_.Selected | Should -BeFalse }
    }
}

Describe 'Format-CategoryList' {
    It 'emits one entry per category with 1-based index and total count' {
        $map = @{
            Debloat = @((New-CliRow -Id 'a'), (New-CliRow -Id 'b'))
            RAM     = @((New-CliRow -Id 'c'))
        }
        $entries = @(Format-CategoryList -RowsByCategory $map)
        $entries.Count | Should -Be 2
        $entries[0].Index | Should -Be 1
        ($entries | ForEach-Object { $_.Category }) | Should -Contain 'Debloat'
        ($entries | ForEach-Object { $_.Category }) | Should -Contain 'RAM'
    }

    It 'shows the per-category selected count when non-zero' {
        $map = @{
            Debloat = @(
                (New-CliRow -Id 'a' -Selected $true)
                (New-CliRow -Id 'b')
            )
        }
        $entry = @(Format-CategoryList -RowsByCategory $map)[0]
        $entry.Selected | Should -Be 1
        $entry.Display | Should -Match '\[1\]'
    }
}

Describe 'Format-ActionListLine' {
    It 'formats a selected row with [x]' {
        $row = New-CliRow -Id 'sel' -Selected $true
        $line = Format-ActionListLine -Index 5 -Row $row
        $line.Display | Should -Match '\[x\]'
        $line.Display | Should -Match '#5'
    }

    It 'formats an unselected row with [ ]' {
        $row = New-CliRow -Id 'unsel' -Selected $false
        $line = Format-ActionListLine -Index 1 -Row $row
        $line.Display | Should -Match '\[ \]'
    }

    It 'uppercases the risk tag' {
        $row = New-CliRow -Id 'risk' -Risk 'Avoid'
        $line = Format-ActionListLine -Index 1 -Row $row
        $line.Display | Should -Match 'AVOID'
        $line.Color   | Should -Be ([System.ConsoleColor]::Red)
    }
}
