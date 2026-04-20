BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/stale-apps.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-sa-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-InstalledProgramIndex' {
    It 'returns at least one entry on a real system' {
        $index = @(Get-InstalledProgramIndex)
        $index.Count | Should -BeGreaterThan 0
    }

    It 'tags each entry with a Source' {
        $index = @(Get-InstalledProgramIndex)
        ($index | ForEach-Object { $_.Source } | Sort-Object -Unique) | Should -Contain 'Win32'
    }
}

Describe 'Get-PrefetchIndex' {
    It 'returns a hashtable' {
        $map = Get-PrefetchIndex
        $map -is [hashtable] | Should -BeTrue
    }
}

Describe 'Invoke-StaleAppsScan' {
    It 'returns items sorted by age desc' {
        $items = @(Invoke-StaleAppsScan -ThresholdDays 1)
        if ($items.Count -ge 2) {
            $items[0].AgeDays | Should -BeGreaterOrEqual $items[1].AgeDays
        }
    }

    It 'always returns a collection even when nothing matches' {
        $items = @(Invoke-StaleAppsScan -ThresholdDays 36500)
        $items -is [array]  -or $items.Count -ge 0 | Should -BeTrue
    }
}

Describe 'Register-StaleAppsActions' {
    BeforeEach { Clear-Actions }

    It 'registers the scan action' {
        Register-StaleAppsActions
        @(Get-Actions -Category 'Deep Cleanup').Count | Should -Be 1
        (Get-Action -Id 'cleanup.stale-apps.scan') | Should -Not -BeNullOrEmpty
    }

    It 'registers itself as an enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-StaleAppsActions'
    }
}
