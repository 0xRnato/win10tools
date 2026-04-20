BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/elevation.ps1')
    . (Join-Path $script:repoRoot 'src/core/restore-point.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-rplogs-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Restore point helpers' {
    It 'Test-RestorePointEnabled returns a boolean' {
        $r = Test-RestorePointEnabled
        $r -is [bool] | Should -BeTrue
    }

    It 'New-AutoRestorePoint returns false when not admin' {
        if (Test-IsAdmin) {
            Set-ItResult -Skipped -Because 'only meaningful when not admin'
            return
        }
        New-AutoRestorePoint -Description 'pester test' | Should -BeFalse
    }

    It 'Get-LatestRestorePoint returns null or an object with CreationTime' {
        $r = Get-LatestRestorePoint
        if ($null -ne $r) {
            $r.PSObject.Properties.Name | Should -Contain 'CreationTime'
        } else {
            $r | Should -BeNullOrEmpty
        }
    }
}
