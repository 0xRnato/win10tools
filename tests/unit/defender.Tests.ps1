BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/actions/defender.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-def-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Register-DefenderActions' {
    BeforeEach { Clear-Actions }

    It 'registers all Defender actions' {
        Register-DefenderActions
        @(Get-Actions -Category 'Defender').Count | Should -Be 5
    }

    It 'includes scan, update, status, and history ids' {
        Register-DefenderActions
        $ids = @(Get-Actions -Category 'Defender' | ForEach-Object { $_.Id })
        $ids | Should -Contain 'defender.quick-scan'
        $ids | Should -Contain 'defender.full-scan'
        $ids | Should -Contain 'defender.update-signatures'
        $ids | Should -Contain 'defender.show-status'
        $ids | Should -Contain 'defender.show-threat-history'
    }

    It 'marks no Defender action as Destructive' {
        Register-DefenderActions
        Get-Actions -Category 'Defender' | ForEach-Object { $_.Destructive | Should -BeFalse }
    }

    It 'classifies every Defender action as Safe' {
        Register-DefenderActions
        Get-Actions -Category 'Defender' | ForEach-Object { $_.Risk | Should -Be 'Safe' }
    }

    It 'makes read-only info actions available to non-admin' {
        Register-DefenderActions
        (Get-Action -Id 'defender.show-status').NeedsAdmin          | Should -BeFalse
        (Get-Action -Id 'defender.show-threat-history').NeedsAdmin  | Should -BeFalse
    }

    It 'requires admin for scan and update actions' {
        Register-DefenderActions
        (Get-Action -Id 'defender.quick-scan').NeedsAdmin         | Should -BeTrue
        (Get-Action -Id 'defender.full-scan').NeedsAdmin          | Should -BeTrue
        (Get-Action -Id 'defender.update-signatures').NeedsAdmin  | Should -BeTrue
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-DefenderActions'
    }
}
