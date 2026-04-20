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

    It 'registers four maintenance actions' {
        Register-MaintenanceActions
        @(Get-Actions -Category 'Maintenance').Count | Should -Be 4
    }

    It 'includes sfc, dism, and restore-point ids' {
        Register-MaintenanceActions
        $ids = @(Get-Actions -Category 'Maintenance' | ForEach-Object { $_.Id })
        $ids | Should -Contain 'maintenance.sfc-scannow'
        $ids | Should -Contain 'maintenance.dism-check-health'
        $ids | Should -Contain 'maintenance.dism-restore-health'
        $ids | Should -Contain 'maintenance.create-restore-point'
    }

    It 'classifies every maintenance action as Safe' {
        Register-MaintenanceActions
        Get-Actions -Category 'Maintenance' | ForEach-Object { $_.Risk | Should -Be 'Safe' }
    }

    It 'requires admin for every maintenance action' {
        Register-MaintenanceActions
        Get-Actions -Category 'Maintenance' | ForEach-Object { $_.NeedsAdmin | Should -BeTrue }
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-MaintenanceActions'
    }
}
