BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/actions/hardware.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-hw-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Register-HardwareActions' {
    BeforeEach { Clear-Actions }

    It 'registers all hardware actions' {
        Register-HardwareActions
        @(Get-Actions -Category 'Hardware').Count | Should -Be 7
    }

    It 'includes the expected ids' {
        Register-HardwareActions
        $ids = @(Get-Actions -Category 'Hardware' | ForEach-Object { $_.Id })
        $ids | Should -Contain 'hardware.smart-report'
        $ids | Should -Contain 'hardware.schedule-memory-test'
        $ids | Should -Contain 'hardware.schedule-chkdsk'
        $ids | Should -Contain 'hardware.battery-report'
        $ids | Should -Contain 'hardware.system-info'
        $ids | Should -Contain 'hardware.event-log-triage'
        $ids | Should -Contain 'hardware.cpu-temperature'
    }

    It 'flags reboot-requiring actions as NeedsReboot' {
        Register-HardwareActions
        (Get-Action -Id 'hardware.schedule-memory-test').NeedsReboot | Should -BeTrue
        (Get-Action -Id 'hardware.schedule-chkdsk').NeedsReboot      | Should -BeTrue
    }

    It 'flags scheduling actions as Destructive' {
        Register-HardwareActions
        (Get-Action -Id 'hardware.schedule-memory-test').Destructive | Should -BeTrue
        (Get-Action -Id 'hardware.schedule-chkdsk').Destructive      | Should -BeTrue
    }

    It 'keeps pure read-only actions non-destructive' {
        Register-HardwareActions
        foreach ($id in 'hardware.smart-report', 'hardware.battery-report', 'hardware.system-info', 'hardware.event-log-triage', 'hardware.cpu-temperature') {
            (Get-Action -Id $id).Destructive | Should -BeFalse
        }
    }

    It 'emits dry run summaries prefixed with [HARDWARE]' {
        Register-HardwareActions
        Get-Actions -Category 'Hardware' | ForEach-Object {
            (& $_.DryRunSummary $_.Context) | Should -Match '\[HARDWARE\]'
        }
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-HardwareActions'
    }
}
