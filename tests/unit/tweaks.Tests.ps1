BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/actions/tweaks.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-tweaks-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Register-TweakActions' {
    BeforeEach { Clear-Actions }

    It 'registers actions in the Tweaks category' {
        Register-TweakActions
        @(Get-Actions -Category 'Tweaks').Count | Should -BeGreaterThan 10
    }

    It 'includes the expected core tweak ids' {
        Register-TweakActions
        $ids = @(Get-Actions -Category 'Tweaks' | ForEach-Object { $_.Id })
        $ids | Should -Contain 'tweaks.power.ultimate-performance'
        $ids | Should -Contain 'tweaks.network.flush-dns'
        $ids | Should -Contain 'tweaks.network.reset-winsock'
        $ids | Should -Contain 'tweaks.network.dns-cloudflare'
        $ids | Should -Contain 'tweaks.network.dns-google'
        $ids | Should -Contain 'tweaks.explorer.dark-mode-apps'
        $ids | Should -Contain 'tweaks.taskbar.hide-search'
    }

    It 'flags reset-winsock as NeedsReboot' {
        Register-TweakActions
        (Get-Action -Id 'tweaks.network.reset-winsock').NeedsReboot | Should -BeTrue
    }

    It 'emits DryRunSummary prefixed with [TWEAKS]' {
        Register-TweakActions
        Get-Actions -Category 'Tweaks' | ForEach-Object {
            (& $_.DryRunSummary $_.Context) | Should -Match '\[TWEAKS\]'
        }
    }

    It 'DNS tweak actions provide a Revert scriptblock' {
        Register-TweakActions
        Get-Actions -IdPattern 'tweaks.network.dns-*' | ForEach-Object {
            $_.Revert | Should -BeOfType [scriptblock]
        }
    }

    It 'explorer tweaks provide a Revert scriptblock' {
        Register-TweakActions
        Get-Actions -IdPattern 'tweaks.explorer.*' | ForEach-Object {
            $_.Revert | Should -BeOfType [scriptblock]
        }
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-TweakActions'
    }
}
