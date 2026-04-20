BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:runPath  = Join-Path $script:repoRoot 'run.ps1'
}

Describe 'run.ps1 loader' -Tag 'Integration' {
    It 'exits 0 when invoked with -SkipElevation' {
        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:runPath, '-SkipElevation') `
            -Wait -PassThru -WindowStyle Hidden
        $proc.ExitCode | Should -Be 0
    }

    It 'writes at least one log entry for the current day' {
        $logRoot = Join-Path $env:LOCALAPPDATA 'win10tools\logs'
        $today   = Join-Path $logRoot ((Get-Date -Format 'yyyy-MM-dd') + '.log')
        Test-Path $today | Should -BeTrue
        (Get-Content $today).Count | Should -BeGreaterThan 0
    }

    It 'also accepts -Cli flag' {
        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:runPath, '-SkipElevation', '-Cli') `
            -Wait -PassThru -WindowStyle Hidden
        $proc.ExitCode | Should -Be 0
    }
}
