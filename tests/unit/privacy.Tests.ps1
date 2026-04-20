BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/privacy.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-priv-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-PrivacyTogglesDefinition' {
    It 'returns a non-empty array of toggles' {
        $defs = @(Get-PrivacyTogglesDefinition)
        $defs.Count | Should -BeGreaterThan 5
    }

    It 'every toggle has the required fields' {
        $defs = @(Get-PrivacyTogglesDefinition)
        foreach ($d in $defs) {
            $d.Id           | Should -Not -BeNullOrEmpty
            $d.Name         | Should -Not -BeNullOrEmpty
            $d.RegistryPath | Should -Not -BeNullOrEmpty
            $d.ValueName    | Should -Not -BeNullOrEmpty
            $d.ValueKind    | Should -BeIn @('DWord', 'String', 'Binary', 'QWord', 'MultiString')
        }
    }
}

Describe 'Register-PrivacyActions' {
    BeforeEach { Clear-Actions }

    It 'registers actions in the Privacy category' {
        Register-PrivacyActions
        @(Get-Actions -Category 'Privacy').Count | Should -BeGreaterThan 5
    }

    It 'every Privacy action has a Revert scriptblock' {
        Register-PrivacyActions
        Get-Actions -Category 'Privacy' | ForEach-Object {
            $_.Revert | Should -BeOfType [scriptblock]
        }
    }

    It 'every Privacy action is Destructive' {
        Register-PrivacyActions
        Get-Actions -Category 'Privacy' | ForEach-Object {
            $_.Destructive | Should -BeTrue
        }
    }

    It 'every Privacy action produces a DryRunSummary' {
        Register-PrivacyActions
        Get-Actions -Category 'Privacy' | ForEach-Object {
            (& $_.DryRunSummary $_.Context) | Should -Match '\[PRIVACY\]'
        }
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-PrivacyActions'
    }
}
