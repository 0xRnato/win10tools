BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/leftover.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/startup.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-startup-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-StartupApprovedBytes' {
    It 'returns enabled bytes starting with 0x02' {
        $b = Get-StartupApprovedBytes -Enabled $true
        $b.Length | Should -Be 12
        $b[0]     | Should -Be 0x02
    }

    It 'returns disabled bytes starting with 0x03' {
        $b = Get-StartupApprovedBytes -Enabled $false
        $b.Length | Should -Be 12
        $b[0]     | Should -Be 0x03
    }
}

Describe 'Get-RunKeyEntries' {
    It 'returns a collection without throwing' {
        { Get-RunKeyEntries } | Should -Not -Throw
    }

    It 'tags returned items with Kind=RunKey' {
        $entries = @(Get-RunKeyEntries)
        if ($entries.Count -gt 0) {
            $entries | ForEach-Object { $_.Kind | Should -Be 'RunKey' }
        }
    }
}

Describe 'Get-StartupFolderEntries' {
    It 'returns a collection without throwing' {
        { Get-StartupFolderEntries } | Should -Not -Throw
    }
}

Describe 'Get-StartupScheduledTasks' {
    It 'returns a collection without throwing' {
        { Get-StartupScheduledTasks } | Should -Not -Throw
    }
}

Describe 'Register-StartupActions' {
    BeforeEach { Clear-Actions }

    It 'registers without throwing' {
        { Register-StartupActions } | Should -Not -Throw
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-StartupActions'
    }

    It 'places registered actions in the Startup category' {
        Register-StartupActions
        $actions = @(Get-Actions -Category 'Startup')
        if ($actions.Count -gt 0) {
            $actions | ForEach-Object { $_.Category | Should -Be 'Startup' }
        }
    }
}
