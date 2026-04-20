BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:logRoot  = Join-Path $env:TEMP ("w10t-reg-logs-" + [Guid]::NewGuid().ToString('N'))
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Register-Action' {
    BeforeEach { Clear-Actions }

    It 'registers a valid action' {
        Register-Action @{
            Id='test.a'; Category='Test'; Name='A'; Description='x'; Risk='Safe'
            Invoke={ 'ok' }
        }
        Get-ActionCount | Should -Be 1
    }

    It 'throws when required keys are missing' {
        { Register-Action @{ Id='test.b'; Category='Test' } } | Should -Throw
    }

    It 'throws on invalid Risk value' {
        { Register-Action @{
            Id='test.c'; Category='Test'; Name='C'; Description='x'; Risk='Nuke'
            Invoke={ }
        } } | Should -Throw
    }

    It 'throws on duplicate Id' {
        Register-Action @{ Id='test.d'; Category='Test'; Name='D'; Description='x'; Risk='Safe'; Invoke={ } }
        {
            Register-Action @{ Id='test.d'; Category='Test'; Name='D2'; Description='x'; Risk='Safe'; Invoke={ } }
        } | Should -Throw
    }

    It 'throws when Invoke is not a scriptblock' {
        { Register-Action @{
            Id='test.e'; Category='Test'; Name='E'; Description='x'; Risk='Safe'
            Invoke='not-a-scriptblock'
        } } | Should -Throw
    }

    It 'defaults NeedsAdmin to true' {
        Register-Action @{ Id='test.f'; Category='Test'; Name='F'; Description='x'; Risk='Safe'; Invoke={ } }
        (Get-Action -Id 'test.f').NeedsAdmin | Should -BeTrue
    }

    It 'accepts NeedsAdmin=false' {
        Register-Action @{ Id='test.g'; Category='Test'; Name='G'; Description='x'; Risk='Safe'; Invoke={ }; NeedsAdmin=$false }
        (Get-Action -Id 'test.g').NeedsAdmin | Should -BeFalse
    }

    It 'defaults Destructive to false' {
        Register-Action @{ Id='test.h'; Category='Test'; Name='H'; Description='x'; Risk='Safe'; Invoke={ } }
        (Get-Action -Id 'test.h').Destructive | Should -BeFalse
    }

    It 'preserves Context payload' {
        Register-Action @{
            Id='test.i'; Category='Test'; Name='I'; Description='x'; Risk='Safe'
            Context = @{ payload = 42 }
            Invoke={ }
        }
        (Get-Action -Id 'test.i').Context.payload | Should -Be 42
    }
}

Describe 'Get-Actions filtering' {
    BeforeEach {
        Clear-Actions
        Register-Action @{ Id='a.1'; Category='A'; Name='a1'; Description='x'; Risk='Safe';  Invoke={ } }
        Register-Action @{ Id='a.2'; Category='A'; Name='a2'; Description='x'; Risk='Minor'; Invoke={ } }
        Register-Action @{ Id='b.1'; Category='B'; Name='b1'; Description='x'; Risk='Safe';  Invoke={ } }
        Register-Action @{ Id='c.1'; Category='C'; Name='c1'; Description='x'; Risk='Avoid'; Invoke={ } }
    }

    It 'filters by Category' {
        @(Get-Actions -Category 'A').Count | Should -Be 2
    }

    It 'filters by Risk' {
        @(Get-Actions -Risk 'Safe').Count  | Should -Be 2
        @(Get-Actions -Risk 'Avoid').Count | Should -Be 1
    }

    It 'filters by IdPattern wildcard' {
        @(Get-Actions -IdPattern 'a.*').Count | Should -Be 2
    }

    It 'combines filters' {
        @(Get-Actions -Category 'A' -Risk 'Safe').Count | Should -Be 1
    }

    It 'returns unique sorted categories' {
        Get-ActionCategories | Should -Be @('A', 'B', 'C')
    }

    It 'returns correct total count' {
        Get-ActionCount | Should -Be 4
    }
}

Describe 'Get-Action lookup' {
    BeforeEach {
        Clear-Actions
        Register-Action @{ Id='q.1'; Category='Q'; Name='q1'; Description='x'; Risk='Safe'; Invoke={ } }
    }

    It 'returns action by id' {
        (Get-Action -Id 'q.1').Id | Should -Be 'q.1'
    }

    It 'throws on unknown id' {
        { Get-Action -Id 'nope' } | Should -Throw
    }
}

Describe 'Clear-Actions' {
    It 'wipes registry and id set' {
        Register-Action @{ Id='z.1'; Category='Z'; Name='z'; Description='x'; Risk='Safe'; Invoke={ } }
        Clear-Actions
        Get-ActionCount | Should -Be 0
        { Register-Action @{ Id='z.1'; Category='Z'; Name='z2'; Description='x'; Risk='Safe'; Invoke={ } } } | Should -Not -Throw
    }
}

Describe 'Enumerator registry' {
    BeforeEach {
        Clear-Enumerators
        Clear-Actions
    }

    It 'registers an enumerator function name' {
        Register-Enumerator 'My-Enum'
        Get-EnumeratorList | Should -Contain 'My-Enum'
    }

    It 'deduplicates repeated registrations' {
        Register-Enumerator 'My-Enum'
        Register-Enumerator 'My-Enum'
        (Get-EnumeratorList).Count | Should -Be 1
    }

    It 'invokes every enumerator that exists' {
        function global:Test-EnumA { Register-Action @{ Id='pe.a'; Category='P'; Name='a'; Description='x'; Risk='Safe'; Invoke={ } } }
        function global:Test-EnumB { Register-Action @{ Id='pe.b'; Category='P'; Name='b'; Description='x'; Risk='Safe'; Invoke={ } } }
        try {
            Register-Enumerator 'Test-EnumA'
            Register-Enumerator 'Test-EnumB'
            Invoke-AllEnumerators
            Get-ActionCount | Should -Be 2
        } finally {
            Remove-Item function:\Test-EnumA -ErrorAction SilentlyContinue
            Remove-Item function:\Test-EnumB -ErrorAction SilentlyContinue
        }
    }

    It 'logs a warning when an enumerator is missing but does not throw' {
        Register-Enumerator 'Does-Not-Exist'
        { Invoke-AllEnumerators } | Should -Not -Throw
    }

    It 'continues past an enumerator that throws' {
        function global:Test-EnumBroken { throw 'boom' }
        function global:Test-EnumFine   { Register-Action @{ Id='pf.ok'; Category='P'; Name='ok'; Description='x'; Risk='Safe'; Invoke={ } } }
        try {
            Register-Enumerator 'Test-EnumBroken'
            Register-Enumerator 'Test-EnumFine'
            { Invoke-AllEnumerators } | Should -Not -Throw
            Get-ActionCount | Should -Be 1
        } finally {
            Remove-Item function:\Test-EnumBroken -ErrorAction SilentlyContinue
            Remove-Item function:\Test-EnumFine   -ErrorAction SilentlyContinue
        }
    }
}
