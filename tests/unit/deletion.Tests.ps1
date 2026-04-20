BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/deletion.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-dlogs-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Deletion mode' {
    It 'defaults to RecycleBin' {
        Set-DeletionMode -Mode RecycleBin
        Get-DeletionMode | Should -Be 'RecycleBin'
    }

    It 'switches to Direct and back' {
        Set-DeletionMode -Mode Direct
        Get-DeletionMode | Should -Be 'Direct'
        Set-DeletionMode -Mode RecycleBin
        Get-DeletionMode | Should -Be 'RecycleBin'
    }

    It 'rejects an invalid mode' {
        { Set-DeletionMode -Mode 'Nuke' } | Should -Throw
    }
}

Describe 'Remove-ItemSafely' {
    BeforeEach {
        $script:tmp = Join-Path $env:TEMP ("w10t-d-" + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $script:tmp -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        if (Test-Path $script:tmp) { Remove-Item $script:tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Direct-deletes a file' {
        $f = Join-Path $script:tmp 'a.txt'
        'x' | Set-Content $f
        $r = Remove-ItemSafely -Path $f -Mode Direct
        $r.removed | Should -BeTrue
        Test-Path $f | Should -BeFalse
    }

    It 'Direct-deletes a directory recursively' {
        $d = Join-Path $script:tmp 'sub'
        New-Item $d -ItemType Directory | Out-Null
        'x' | Set-Content (Join-Path $d 'y.txt')
        $r = Remove-ItemSafely -Path $d -Mode Direct
        $r.removed | Should -BeTrue
        Test-Path $d | Should -BeFalse
    }

    It 'RecycleBin mode removes the source file' {
        $f = Join-Path $script:tmp 'rb.txt'
        'x' | Set-Content $f
        $r = Remove-ItemSafely -Path $f -Mode RecycleBin
        $r.removed | Should -BeTrue
        Test-Path $f | Should -BeFalse
    }

    It 'returns not-found for missing paths' {
        $r = Remove-ItemSafely -Path (Join-Path $script:tmp 'never.txt') -Mode Direct
        $r.removed | Should -BeFalse
        $r.reason  | Should -Be 'not-found'
    }

    It 'honours the Auto mode via Set-DeletionMode' {
        Set-DeletionMode -Mode Direct
        $f = Join-Path $script:tmp 'auto.txt'
        'x' | Set-Content $f
        $r = Remove-ItemSafely -Path $f -Mode Auto
        $r.mode | Should -Be 'Direct'
        Set-DeletionMode -Mode RecycleBin
    }
}
