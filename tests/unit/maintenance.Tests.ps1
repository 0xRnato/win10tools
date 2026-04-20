BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/core/elevation.ps1')
    . (Join-Path $script:repoRoot 'src/core/restore-point.ps1')
    . (Join-Path $script:repoRoot 'src/actions/maintenance.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-maint-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Register-MaintenanceActions' {
    BeforeEach { Clear-Actions }

    It 'registers five maintenance actions' {
        Register-MaintenanceActions
        @(Get-Actions -Category 'Maintenance').Count | Should -Be 5
    }

    It 'includes sfc, dism, restore-point, and quarantine-cleanup ids' {
        Register-MaintenanceActions
        $ids = @(Get-Actions -Category 'Maintenance' | ForEach-Object { $_.Id })
        $ids | Should -Contain 'maintenance.sfc-scannow'
        $ids | Should -Contain 'maintenance.dism-check-health'
        $ids | Should -Contain 'maintenance.dism-restore-health'
        $ids | Should -Contain 'maintenance.create-restore-point'
        $ids | Should -Contain 'maintenance.schedule-quarantine-cleanup'
    }

    It 'quarantine-cleanup action is Safe, Destructive, and provides Revert' {
        Register-MaintenanceActions
        $a = Get-Action -Id 'maintenance.schedule-quarantine-cleanup'
        $a.Risk        | Should -Be 'Safe'
        $a.Destructive | Should -BeTrue
        $a.Revert      | Should -BeOfType [scriptblock]
        $a.Context.TaskName | Should -Be 'win10tools-quarantine-cleanup'
    }

    It 'classifies every maintenance action as Safe' {
        Register-MaintenanceActions
        Get-Actions -Category 'Maintenance' | ForEach-Object { $_.Risk | Should -Be 'Safe' }
    }

    It 'quarantine-cleanup DryRunSummary mentions Register-ScheduledTask' {
        Register-MaintenanceActions
        $a = Get-Action -Id 'maintenance.schedule-quarantine-cleanup'
        (& $a.DryRunSummary $a.Context) | Should -Match 'Register-ScheduledTask'
    }

    It 'requires admin for every maintenance action' {
        Register-MaintenanceActions
        Get-Actions -Category 'Maintenance' | ForEach-Object { $_.NeedsAdmin | Should -BeTrue }
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-MaintenanceActions'
    }
}
