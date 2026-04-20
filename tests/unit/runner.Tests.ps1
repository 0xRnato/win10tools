BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/core/elevation.ps1')
    . (Join-Path $script:repoRoot 'src/core/runner.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-runner-logs-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-ActionDryRun' {
    It 'formats risk, category, and name' {
        $a = @{
            Id='x.1'; Category='Test'; Name='Hello'; Risk='Safe'
            Destructive=$false; NeedsReboot=$false; NeedsAdmin=$false
        }
        $s = Get-ActionDryRun -Action $a
        $s | Should -Match 'SAFE'
        $s | Should -Match 'Test / Hello'
    }

    It 'uses custom DryRunSummary when present' {
        $a = @{
            Id='x.2'; Category='T'; Name='H'; Risk='Safe'
            Destructive=$false; NeedsReboot=$false; NeedsAdmin=$false
            Context=@{}
            DryRunSummary={ 'custom-summary' }
        }
        Get-ActionDryRun -Action $a | Should -Be 'custom-summary'
    }

    It 'includes destructive and needs-reboot flags' {
        $a = @{
            Id='x.3'; Category='T'; Name='H'; Risk='Avoid'
            Destructive=$true; NeedsReboot=$true; NeedsAdmin=$true
        }
        $s = Get-ActionDryRun -Action $a
        $s | Should -Match 'destructive'
        $s | Should -Match 'needs-reboot'
        $s | Should -Match 'AVOID'
    }
}

Describe 'Invoke-Action' {
    It 'returns dry-run without running Invoke' {
        $a = @{
            Id='d.1'; Category='T'; Name='dr'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}
            Invoke={ throw 'should not be called during dry run' }
        }
        $r = Invoke-Action -Action $a -DryRun
        $r.status | Should -Be 'dry-run'
        $r.error  | Should -BeNullOrEmpty
    }

    It 'returns applied on Invoke success' {
        $a = @{
            Id='d.2'; Category='T'; Name='ok'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}
            Invoke={ 42 | Out-Null }
        }
        (Invoke-Action -Action $a).status | Should -Be 'applied'
    }

    It 'skips when Check returns true' {
        $a = @{
            Id='d.3'; Category='T'; Name='sk'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}
            Check={ $true }
            Invoke={ throw 'should have been skipped' }
        }
        $r = Invoke-Action -Action $a
        $r.status  | Should -Be 'skipped'
        $r.skipped | Should -BeTrue
    }

    It 'runs Invoke when Check returns false' {
        $a = @{
            Id='d.4'; Category='T'; Name='run'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}
            Check={ $false }
            Invoke={ }
        }
        (Invoke-Action -Action $a).status | Should -Be 'applied'
    }

    It 'returns error with message when Invoke throws' {
        $a = @{
            Id='d.5'; Category='T'; Name='err'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}
            Invoke={ throw 'boom' }
        }
        $r = Invoke-Action -Action $a
        $r.status | Should -Be 'error'
        $r.error  | Should -Match 'boom'
    }

    It 'records duration in milliseconds' {
        $a = @{
            Id='d.6'; Category='T'; Name='dur'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}
            Invoke={ }
        }
        (Invoke-Action -Action $a).duration | Should -BeGreaterOrEqual 0
    }

    It 'blocks NeedsAdmin action when not elevated' {
        if (Test-IsAdmin) {
            Set-ItResult -Skipped -Because 'only meaningful when not admin'
            return
        }
        $a = @{
            Id='d.7'; Category='T'; Name='adminreq'; Risk='Safe'; NeedsAdmin=$true
            Context=@{}
            Invoke={ }
        }
        $r = Invoke-Action -Action $a
        $r.status | Should -Be 'error'
        $r.error  | Should -Match 'Administrator'
    }
}

Describe 'Invoke-ActionBatch' {
    BeforeEach { Clear-Actions }

    It 'aggregates summary counts across applied, skipped, and errors' {
        $a1 = @{ Id='b.1'; Category='T'; Name='1'; Description='x'; Risk='Safe'; NeedsAdmin=$false; Context=@{}; Invoke={ } }
        $a2 = @{ Id='b.2'; Category='T'; Name='2'; Description='x'; Risk='Safe'; NeedsAdmin=$false; Context=@{}; Check={ $true }; Invoke={ throw } }
        $a3 = @{ Id='b.3'; Category='T'; Name='3'; Description='x'; Risk='Safe'; NeedsAdmin=$false; Context=@{}; Invoke={ throw 'nope' } }
        Register-Action $a1
        Register-Action $a2
        Register-Action $a3

        $actions = @((Get-Action -Id 'b.1'), (Get-Action -Id 'b.2'), (Get-Action -Id 'b.3'))
        $r = Invoke-ActionBatch -Actions $actions -SkipRestorePoint

        $r.summary.total   | Should -Be 3
        $r.summary.applied | Should -Be 1
        $r.summary.skipped | Should -Be 1
        $r.summary.errors  | Should -Be 1
    }

    It 'honours DryRun for every action in the batch' {
        $a1 = @{ Id='b.4'; Category='T'; Name='4'; Description='x'; Risk='Safe'; NeedsAdmin=$false; Context=@{}; Invoke={ throw 'nope' } }
        Register-Action $a1
        $r = Invoke-ActionBatch -Actions @((Get-Action -Id 'b.4')) -DryRun -SkipRestorePoint
        $r.summary.dryRun | Should -Be 1
        $r.summary.errors | Should -Be 0
    }

    It 'flags needsReboot when any applied action requires it' {
        $a = @{
            Id='b.5'; Category='T'; Name='5'; Description='x'; Risk='Safe'; NeedsAdmin=$false; NeedsReboot=$true; Context=@{}; Invoke={ }
        }
        Register-Action $a
        $r = Invoke-ActionBatch -Actions @((Get-Action -Id 'b.5')) -SkipRestorePoint
        $r.summary.needsReboot | Should -BeTrue
    }
}

Describe 'Invoke-ActionRevert' {
    It 'runs the Revert scriptblock and returns true' {
        $a = @{
            Id='r.1'; Category='T'; Name='r'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}; Invoke={ }; Revert={ }
        }
        Invoke-ActionRevert -Action $a | Should -BeTrue
    }

    It 'returns false when Revert throws' {
        $a = @{
            Id='r.2'; Category='T'; Name='r'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}; Invoke={ }; Revert={ throw 'bad' }
        }
        Invoke-ActionRevert -Action $a | Should -BeFalse
    }

    It 'throws when action has no Revert scriptblock' {
        $a = @{
            Id='r.3'; Category='T'; Name='r'; Risk='Safe'; NeedsAdmin=$false
            Context=@{}; Invoke={ }; Revert=$null
        }
        { Invoke-ActionRevert -Action $a } | Should -Throw
    }
}
