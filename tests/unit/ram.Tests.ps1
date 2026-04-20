BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/actions/ram.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-ram-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Register-RamActions' {
    BeforeEach { Clear-Actions }

    It 'registers both RAM actions' {
        Register-RamActions
        @(Get-Actions -Category 'RAM').Count | Should -Be 2
    }

    It 'emits a dry-run summary prefixed with [RAM]' {
        Register-RamActions
        Get-Actions -Category 'RAM' | ForEach-Object {
            (& $_.DryRunSummary $_.Context) | Should -Match '\[RAM\]'
        }
    }

    It 'flags every action as NeedsAdmin' {
        Register-RamActions
        Get-Actions -Category 'RAM' | ForEach-Object { $_.NeedsAdmin | Should -BeTrue }
    }

    It 'classifies trim-working-sets as Safe' {
        Register-RamActions
        (Get-Action -Id 'ram.trim-working-sets').Risk | Should -Be 'Safe'
    }

    It 'classifies clear-standby-list as Minor' {
        Register-RamActions
        (Get-Action -Id 'ram.clear-standby-list').Risk | Should -Be 'Minor'
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-RamActions'
    }
}
