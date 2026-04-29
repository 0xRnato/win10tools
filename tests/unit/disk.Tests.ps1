BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/core/deletion.ps1')
    . (Join-Path $script:repoRoot 'src/actions/disk.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-disk-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Register-DiskActions' {
    BeforeEach { Clear-Actions }

    It 'registers multiple Disk actions' {
        Register-DiskActions
        @(Get-Actions -Category 'Disk').Count | Should -BeGreaterThan 5
    }

    It 'includes the expected core ids' {
        Register-DiskActions
        $ids = @(Get-Actions -Category 'Disk' | ForEach-Object { $_.Id })
        $ids | Should -Contain 'disk.clear-user-temp'
        $ids | Should -Contain 'disk.clear-system-temp'
        $ids | Should -Contain 'disk.empty-recycle-bin'
        $ids | Should -Contain 'disk.clear-wu-cache'
        $ids | Should -Contain 'disk.run-cleanmgr'
    }

    It 'registers one action per supported browser' {
        Register-DiskActions
        $browserIds = @(Get-Actions -IdPattern 'disk.clear-browser-cache-*' | ForEach-Object { $_.Id })
        $browserIds | Should -Contain 'disk.clear-browser-cache-chrome'
        $browserIds | Should -Contain 'disk.clear-browser-cache-edge'
        $browserIds | Should -Contain 'disk.clear-browser-cache-firefox'
        $browserIds | Should -Contain 'disk.clear-browser-cache-brave'
    }

    It 'marks every Disk action as Destructive' {
        Register-DiskActions
        Get-Actions -Category 'Disk' | ForEach-Object { $_.Destructive | Should -BeTrue }
    }

    It 'emits dry run summaries prefixed with [DISK]' {
        Register-DiskActions
        Get-Actions -Category 'Disk' | ForEach-Object {
            (& $_.DryRunSummary $_.Context) | Should -Match '\[DISK\]'
        }
    }

    It 'user-temp action uses %TEMP% path' {
        Register-DiskActions
        (Get-Action -Id 'disk.clear-user-temp').Context.Path | Should -Be $env:TEMP
    }

    It 'registers itself as enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-DiskActions'
    }
}

Describe 'Invoke-DiskPathClear' {
    BeforeEach {
        $script:tmp = Join-Path $env:TEMP ("w10t-diskclear-" + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $script:tmp -ItemType Directory -Force | Out-Null
        'a' | Set-Content (Join-Path $script:tmp 'a.txt')
        'b' | Set-Content (Join-Path $script:tmp 'b.txt')
        New-Item -Path (Join-Path $script:tmp 'sub') -ItemType Directory | Out-Null
        'c' | Set-Content (Join-Path $script:tmp 'sub/c.txt')
    }

    AfterEach {
        if (Test-Path $script:tmp) { Remove-Item $script:tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'deletes every child item under a path' {
        Set-DeletionMode -Mode Direct
        Invoke-DiskPathClear -Path $script:tmp
        @(Get-ChildItem -LiteralPath $script:tmp -Force).Count | Should -Be 0
    }

    It 'is a no-op on a missing path' {
        { Invoke-DiskPathClear -Path 'C:\absolutely\nowhere\here' } | Should -Not -Throw
    }
}
