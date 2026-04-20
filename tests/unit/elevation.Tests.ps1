BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/elevation.ps1')
}

Describe 'Elevation' {
    It 'Test-IsAdmin returns a boolean' {
        $r = Test-IsAdmin
        $r -is [bool] | Should -BeTrue
    }

    It 'Assert-Admin throws iff not admin' {
        if (Test-IsAdmin) {
            { Assert-Admin } | Should -Not -Throw
        } else {
            { Assert-Admin } | Should -Throw
        }
    }

    It 'Invoke-Elevate is a no-op when already admin' {
        if (-not (Test-IsAdmin)) {
            Set-ItResult -Skipped -Because 'requires admin'
            return
        }
        { Invoke-Elevate -ScriptPath 'C:\nonexistent.ps1' } | Should -Not -Throw
    }

    It 'Invoke-Elevate throws when non-admin and no target given' {
        if (Test-IsAdmin) {
            Set-ItResult -Skipped -Because 'only meaningful when not admin'
            return
        }
        { Invoke-Elevate } | Should -Throw
    }
}
