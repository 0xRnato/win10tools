BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/actions/apps.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-apps-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-WingetManifest' {
    It 'returns a hashtable with named categories' {
        $m = Get-WingetManifest
        $m -is [hashtable] | Should -BeTrue
        $m.Keys           | Should -Contain 'dev'
        $m.Keys           | Should -Contain 'media'
        $m.Keys           | Should -Contain 'utils'
    }

    It 'every category is a non-empty string array' {
        $m = Get-WingetManifest
        foreach ($key in $m.Keys) {
            @($m[$key]).Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Test-WingetAvailable' {
    It 'returns a boolean' {
        $r = Test-WingetAvailable
        $r -is [bool] | Should -BeTrue
    }
}

Describe 'Register-AppsActions' {
    BeforeEach { Clear-Actions }

    It 'registers one action per manifest category plus export' {
        Register-AppsActions
        $m = Get-WingetManifest
        $expected = @($m.Keys).Count + 1
        @(Get-Actions -Category 'Apps').Count | Should -Be $expected
    }

    It 'marks bulk-install actions as Destructive and NeedsAdmin' {
        Register-AppsActions
        $bulk = @(Get-Actions -IdPattern 'apps.bulk-install.*')
        $bulk | ForEach-Object {
            $_.Destructive | Should -BeTrue
            $_.NeedsAdmin  | Should -BeTrue
        }
    }

    It 'marks export-installed as Safe and non-destructive' {
        Register-AppsActions
        $a = Get-Action -Id 'apps.export-installed'
        $a.Risk        | Should -Be 'Safe'
        $a.Destructive | Should -BeFalse
        $a.NeedsAdmin  | Should -BeFalse
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-AppsActions'
    }
}
