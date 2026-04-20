BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/quarantine.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-qlogs-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Quarantine' {
    BeforeEach {
        $script:qroot = Join-Path $env:TEMP ("w10t-q-" + [Guid]::NewGuid().ToString('N'))
        Set-QuarantineRoot $script:qroot
    }

    AfterEach {
        if (Test-Path $script:qroot) { Remove-Item $script:qroot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'creates a batch directory' {
        $b = New-QuarantineBatch -Label 'smoke'
        Test-Path $b | Should -BeTrue
        $b | Should -BeLike "$script:qroot*"
    }

    It 'moves a file and preserves drive subdir' {
        $b = New-QuarantineBatch
        $src = Join-Path $env:TEMP ("w10t-src-" + [Guid]::NewGuid().ToString('N') + '.txt')
        'hi' | Set-Content -LiteralPath $src
        $dest = Move-ToQuarantine -Path $src -BatchPath $b
        Test-Path $dest | Should -BeTrue
        Test-Path $src  | Should -BeFalse
    }

    It 'returns null when source is missing' {
        $b = New-QuarantineBatch
        $result = Move-ToQuarantine -Path 'C:\definitely\does\not\exist.txt' -BatchPath $b
        $result | Should -BeNullOrEmpty
    }

    It 'uses RelativeName when provided' {
        $b = New-QuarantineBatch
        $src = Join-Path $env:TEMP ("w10t-rel-" + [Guid]::NewGuid().ToString('N') + '.txt')
        'hi' | Set-Content -LiteralPath $src
        $dest = Move-ToQuarantine -Path $src -BatchPath $b -RelativeName 'nested/name.txt'
        $dest | Should -BeLike "*nested*name.txt"
        Test-Path $dest | Should -BeTrue
    }

    It 'exports a registry key to .reg with content' {
        $key = 'HKCU:\Software\win10tools-pester'
        if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
        try {
            Set-ItemProperty -Path $key -Name 'token' -Value 'pester-value'
            $b = New-QuarantineBatch
            $f = Export-RegistryKeyToQuarantine -RegistryPath $key -BatchPath $b
            Test-Path $f         | Should -BeTrue
            (Get-Item $f).Length | Should -BeGreaterThan 0
        } finally {
            Remove-Item $key -Force -ErrorAction SilentlyContinue
        }
    }

    It 'removes batches older than MaxDays and keeps fresh ones' {
        $oldBatch = New-QuarantineBatch -Label 'old'
        $newBatch = New-QuarantineBatch -Label 'new'
        (Get-Item $oldBatch).CreationTime = (Get-Date).AddDays(-40)
        $removed = Remove-OldQuarantine -MaxDays 30
        $removed | Should -BeGreaterOrEqual 1
        Test-Path $oldBatch | Should -BeFalse
        Test-Path $newBatch | Should -BeTrue
    }
}
