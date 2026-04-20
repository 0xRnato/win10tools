BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/core/runner.ps1')
    . (Join-Path $script:repoRoot 'src/core/elevation.ps1')
    . (Join-Path $script:repoRoot 'src/ui/main-window-helpers.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-ui-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false

    function New-TestAction {
        param(
            [string]$Id,
            [string]$Name,
            [string]$Risk = 'Safe',
            [bool]$Destructive = $false,
            [bool]$NeedsReboot = $false,
            [bool]$NeedsAdmin  = $false,
            [string]$Category  = 'Test',
            [hashtable]$Context = @{}
        )

        @{
            Id=$Id; Category=$Category; Name=$Name
            Description="desc $Id"; Risk=$Risk
            Destructive=$Destructive; NeedsReboot=$NeedsReboot; NeedsAdmin=$NeedsAdmin
            Context=$Context
            Invoke={}; Check=$null; Revert=$null; DryRunSummary={ "[$($args[0].Category)] $($args[0].Name)" }
        }
    }
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'ConvertTo-ActionRow' {
    It 'projects an action into a row object with Selected=false' {
        $row = New-TestAction -Id 'x.1' -Name 'A' | ConvertTo-ActionRow
        $row.Id       | Should -Be 'x.1'
        $row.Name     | Should -Be 'A'
        $row.Risk     | Should -Be 'Safe'
        $row.Selected | Should -BeFalse
    }

    It 'concatenates flags destructive/reboot/admin' {
        $row = New-TestAction -Id 'x.2' -Name 'B' -Destructive $true -NeedsReboot $true -NeedsAdmin $true | ConvertTo-ActionRow
        $row.Flags | Should -Match 'destructive'
        $row.Flags | Should -Match 'reboot'
        $row.Flags | Should -Match 'admin'
    }

    It 'keeps a reference to the original action in ActionRef' {
        $action = New-TestAction -Id 'x.3' -Name 'C'
        $row = $action | ConvertTo-ActionRow
        $row.ActionRef.Id | Should -Be 'x.3'
    }
}

Describe 'Measure-RowSelection' {
    It 'counts total, avoid, and destructive selected rows' {
        $r1 = New-TestAction -Id 'm.1' -Name '1' -Risk 'Safe'                      | ConvertTo-ActionRow
        $r2 = New-TestAction -Id 'm.2' -Name '2' -Risk 'Avoid' -Destructive $true  | ConvertTo-ActionRow
        $r3 = New-TestAction -Id 'm.3' -Name '3' -Risk 'Minor' -Destructive $true  | ConvertTo-ActionRow
        $r1.Selected = $true
        $r2.Selected = $true

        $map = @{ Test = @($r1, $r2, $r3) }
        $stats = Measure-RowSelection -RowsByCategory $map

        $stats.Total       | Should -Be 2
        $stats.Avoid       | Should -Be 1
        $stats.Destructive | Should -Be 1
    }

    It 'returns zeros when nothing selected' {
        $r1 = New-TestAction -Id 'e.1' -Name 'e' | ConvertTo-ActionRow
        $map = @{ Test = @($r1) }
        (Measure-RowSelection -RowsByCategory $map).Total | Should -Be 0
    }
}

Describe 'Get-SelectedRows' {
    It 'returns only selected rows across categories' {
        $a = New-TestAction -Id 's.1' -Name '1' | ConvertTo-ActionRow
        $b = New-TestAction -Id 's.2' -Name '2' | ConvertTo-ActionRow
        $c = New-TestAction -Id 's.3' -Name '3' | ConvertTo-ActionRow
        $a.Selected = $true
        $c.Selected = $true

        $map = @{
            A = @($a, $b)
            B = @($c)
        }

        $selected = @(Get-SelectedRows -RowsByCategory $map)
        $selected.Count | Should -Be 2
        ($selected | ForEach-Object { $_.Id }) | Should -Contain 's.1'
        ($selected | ForEach-Object { $_.Id }) | Should -Contain 's.3'
    }
}

Describe 'Format-DryRunReport' {
    It 'renders a header and one entry per row' {
        $r1 = New-TestAction -Id 'd.1' -Name 'A' -Risk 'Safe'  | ConvertTo-ActionRow
        $r2 = New-TestAction -Id 'd.2' -Name 'B' -Risk 'Avoid' | ConvertTo-ActionRow
        $report = Format-DryRunReport -SelectedRows @($r1, $r2)
        $report | Should -Match 'Dry Run'
        $report | Should -Match 'SAFE'
        $report | Should -Match 'AVOID'
    }

    It 'handles an empty selection without throwing' {
        { Format-DryRunReport -SelectedRows @() } | Should -Not -Throw
    }
}

Describe 'Format-RunReport' {
    It 'formats the batch summary and per-action outcomes' {
        $batch = [pscustomobject]@{
            summary = [pscustomobject]@{
                total=3; applied=1; skipped=1; dryRun=0; errors=1; needsReboot=$false
            }
            results = @(
                [pscustomobject]@{ actionId='r.1'; status='applied'; skipped=$false; error=$null;  duration=12  }
                [pscustomobject]@{ actionId='r.2'; status='skipped'; skipped=$true;  error=$null;  duration=3   }
                [pscustomobject]@{ actionId='r.3'; status='error';   skipped=$false; error='boom'; duration=5   }
            )
        }
        $report = Format-RunReport -BatchResult $batch
        $report | Should -Match 'Run complete'
        $report | Should -Match 'Applied:\s+1'
        $report | Should -Match 'Errors:\s+1'
        $report | Should -Match 'r\.1'
        $report | Should -Match 'boom'
    }
}

Describe 'Update-DeepCleanupThreshold' {
    It 'patches ThresholdDays in Deep Cleanup actions that carry it' {
        Clear-Actions
        Register-Action @{
            Id='cleanup.test.stale'; Category='Deep Cleanup'; Name='stale'; Description='x'
            Risk='Safe'; Invoke={}
            Context=@{ ThresholdDays = 90 }
        }
        Update-DeepCleanupThreshold -ThresholdDays 180
        (Get-Action -Id 'cleanup.test.stale').Context.ThresholdDays | Should -Be 180
    }

    It 'skips actions without ThresholdDays in Context' {
        Clear-Actions
        Register-Action @{
            Id='cleanup.test.other'; Category='Deep Cleanup'; Name='other'; Description='x'
            Risk='Safe'; Invoke={}
            Context=@{ SomethingElse = 'x' }
        }
        { Update-DeepCleanupThreshold -ThresholdDays 45 } | Should -Not -Throw
    }
}
