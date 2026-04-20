BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/leftover.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/services.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-svc-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Register-ServicesActions' {
    BeforeEach { Clear-Actions }

    It 'registers without throwing' {
        { Register-ServicesActions } | Should -Not -Throw
    }

    It 'only surfaces curated tweakable services' {
        Register-ServicesActions
        $names = @(Get-Actions -Category 'Services' | ForEach-Object { $_.Context.Name })
        foreach ($n in $names) {
            $n | Should -BeIn @('DiagTrack', 'dmwappushservice', 'RetailDemo', 'MapsBroker', 'WbioSrvc', 'PcaSvc', 'Fax')
        }
    }

    It 'flags every services action as Destructive and NeedsAdmin' {
        Register-ServicesActions
        Get-Actions -Category 'Services' | ForEach-Object {
            $_.Destructive | Should -BeTrue
            $_.NeedsAdmin  | Should -BeTrue
        }
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-ServicesActions'
    }

    It 'produces a DryRunSummary prefixed with [SERVICES]' {
        Register-ServicesActions
        $actions = @(Get-Actions -Category 'Services')
        if ($actions.Count -gt 0) {
            (& $actions[0].DryRunSummary $actions[0].Context) | Should -Match '\[SERVICES\]'
        }
    }
}
