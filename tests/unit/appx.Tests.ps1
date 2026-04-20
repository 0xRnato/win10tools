BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/core/elevation.ps1')
    . (Join-Path $script:repoRoot 'src/core/risk-table.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/appx.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-appxtests-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-AppxFriendlyName' {
    It 'strips publisher prefix and splits camelCase' {
        Get-AppxFriendlyName -Name 'Microsoft.XboxGameOverlay' | Should -Be 'Xbox Game Overlay'
    }
    It 'keeps single-segment names' {
        Get-AppxFriendlyName -Name 'SimpleApp' | Should -Be 'Simple App'
    }
    It 'falls back to full name when empty' {
        Get-AppxFriendlyName -Name 'NoDots' | Should -Be 'No Dots'
    }
}

Describe 'ConvertTo-ActionIdFragment' {
    It 'lowercases and hyphenates' {
        ConvertTo-ActionIdFragment -Value 'Microsoft.XboxApp' | Should -Be 'microsoft-xboxapp'
    }
    It 'collapses repeated separators' {
        ConvertTo-ActionIdFragment -Value 'foo!!.bar' | Should -Be 'foo-bar'
    }
    It 'trims leading and trailing hyphens' {
        ConvertTo-ActionIdFragment -Value '.Weird.' | Should -Be 'weird'
    }
}

Describe 'Register-AppxActions' {
    BeforeEach {
        Clear-Actions
    }

    It 'registers one action per installed package (user scope)' {
        $count = Register-AppxActions
        $count | Should -BeGreaterThan 0
        (Get-Actions -Category 'Debloat').Count | Should -Be $count
    }

    It 'propagates risk labels from risk-table' {
        Register-AppxActions
        $withKnownAvoid = Get-Actions -Category 'Debloat' | Where-Object {
            $_.Context.Name -like 'Microsoft.VCLibs*' -or
            $_.Context.Name -like 'Microsoft.NET.*'   -or
            $_.Context.Name -like 'Microsoft.WindowsStore'
        }
        if ($withKnownAvoid) {
            $withKnownAvoid[0].Risk | Should -Be 'Avoid'
        }
    }

    It 'marks every action as Destructive and NeedsAdmin' {
        Register-AppxActions
        $actions = Get-Actions -Category 'Debloat'
        $actions | ForEach-Object {
            $_.Destructive | Should -BeTrue
            $_.NeedsAdmin  | Should -BeTrue
        }
    }

    It 'produces Check and Invoke scriptblocks for every action' {
        Register-AppxActions
        $actions = Get-Actions -Category 'Debloat'
        $actions | ForEach-Object {
            $_.Check  | Should -BeOfType [scriptblock]
            $_.Invoke | Should -BeOfType [scriptblock]
        }
    }

    It 'registers itself as an enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-AppxActions'
    }
}
