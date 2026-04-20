BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/stale-apps.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/leftover.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-leftover-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-NormalizedAppName' {
    It 'lowercases and strips punctuation' {
        Get-NormalizedAppName 'Google.Chrome!'      | Should -Be 'googlechrome'
        Get-NormalizedAppName '7-Zip 23.01 (x64)'    | Should -Be '7zip2301x64'
    }
}

Describe 'Test-PathLooksOrphan' {
    It 'returns none when the installed index contains an exact match' {
        $v = Test-PathLooksOrphan -Name 'SomeApp' -InstalledNames @('SomeApp', 'Other')
        $v.Confidence | Should -Be 'none'
    }

    It 'returns none when the installed name is a substring' {
        $v = Test-PathLooksOrphan -Name 'SomeApp Portable' -InstalledNames @('SomeApp')
        $v.Confidence | Should -Be 'none'
    }

    It 'returns Medium when the publisher matches loosely' {
        $v = Test-PathLooksOrphan -Name 'PuzzleThing' -InstalledNames @('Unrelated') -InstalledPublishers @('Puzzle Studios')
        $v.Confidence | Should -Be 'Medium'
    }

    It 'returns High when nothing matches' {
        $v = Test-PathLooksOrphan -Name 'ZZZ-Orphaned-XYZ' -InstalledNames @('Chrome', 'Firefox') -InstalledPublishers @('Google', 'Mozilla')
        $v.Confidence | Should -Be 'High'
    }
}

Describe 'Invoke-LeftoverScan' {
    It 'returns a collection without throwing at User scope' {
        { Invoke-LeftoverScan -Scope 'User' } | Should -Not -Throw
    }

    It 'returns a collection without throwing at Machine scope' {
        { Invoke-LeftoverScan -Scope 'Machine' } | Should -Not -Throw
    }
}

Describe 'Register-LeftoverActions' {
    BeforeEach { Clear-Actions }

    It 'registers both scope-specific actions' {
        Register-LeftoverActions
        $ids = @(Get-Actions -Category 'Deep Cleanup' | ForEach-Object { $_.Id })
        $ids | Should -Contain 'cleanup.leftover.scan-user'
        $ids | Should -Contain 'cleanup.leftover.scan-machine'
    }

    It 'marks machine-scope action as NeedsAdmin' {
        Register-LeftoverActions
        (Get-Action -Id 'cleanup.leftover.scan-machine').NeedsAdmin | Should -BeTrue
        (Get-Action -Id 'cleanup.leftover.scan-user').NeedsAdmin    | Should -BeFalse
    }

    It 'registers itself as an enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-LeftoverActions'
    }
}
