BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
    . (Join-Path $script:repoRoot 'src/core/registry.ps1')
    . (Join-Path $script:repoRoot 'src/enumerators/stale-files.ps1')
    $script:logRoot = Join-Path $env:TEMP ("w10t-sf-" + [Guid]::NewGuid().ToString('N'))
    Initialize-W10Logger -Root $script:logRoot -MirrorToConsole $false
}

AfterAll {
    if (Test-Path $script:logRoot) { Remove-Item $script:logRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Invoke-StaleFilesScan' {
    BeforeEach {
        $script:fixture = Join-Path $env:TEMP ("w10t-sf-fixture-" + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $script:fixture -ItemType Directory -Force | Out-Null

        $old = Join-Path $script:fixture 'old.txt'
        'old' | Set-Content $old
        (Get-Item $old).LastWriteTime   = (Get-Date).AddDays(-120)
        (Get-Item $old).CreationTime    = (Get-Date).AddDays(-120)
        (Get-Item $old).LastAccessTime  = (Get-Date).AddDays(-120)

        $new = Join-Path $script:fixture 'new.txt'
        'new' | Set-Content $new

        $oldDir = Join-Path $script:fixture 'old-dir'
        New-Item $oldDir -ItemType Directory | Out-Null
        'x' | Set-Content (Join-Path $oldDir 'payload.bin')
        (Get-Item $oldDir).LastWriteTime  = (Get-Date).AddDays(-200)
        (Get-Item $oldDir).CreationTime   = (Get-Date).AddDays(-200)
        (Get-Item $oldDir).LastAccessTime = (Get-Date).AddDays(-200)
    }

    AfterEach {
        if (Test-Path $script:fixture) { Remove-Item $script:fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'lists only items older than the threshold' {
        $items = @(Invoke-StaleFilesScan -Paths @($script:fixture) -ThresholdDays 90 -MaxDepth 0)
        $items.Count                                     | Should -BeGreaterOrEqual 2
        ($items | ForEach-Object { $_.Path })            | Should -Contain (Join-Path $script:fixture 'old.txt')
        ($items | ForEach-Object { $_.Path })            | Should -Not -Contain (Join-Path $script:fixture 'new.txt')
    }

    It 'tags files vs directories correctly' {
        $items = @(Invoke-StaleFilesScan -Paths @($script:fixture) -ThresholdDays 90 -MaxDepth 0)
        $dirItem = $items | Where-Object { $_.Path -like '*old-dir*' } | Select-Object -First 1
        $dirItem.IsContainer | Should -BeTrue
    }

    It 'is a no-op when the path is missing' {
        $items = @(Invoke-StaleFilesScan -Paths @('C:\absolutely\nonexistent\here') -ThresholdDays 1)
        $items.Count | Should -Be 0
    }

    It 'sorts results by age desc, size desc' {
        $items = @(Invoke-StaleFilesScan -Paths @($script:fixture) -ThresholdDays 90 -MaxDepth 0)
        if ($items.Count -ge 2) {
            $items[0].AgeDays | Should -BeGreaterOrEqual $items[1].AgeDays
        }
    }
}

Describe 'Get-NtfsLastAccessEnabled' {
    It 'returns a boolean' {
        $r = Get-NtfsLastAccessEnabled
        $r -is [bool] | Should -BeTrue
    }
}

Describe 'Register-StaleFilesActions' {
    BeforeEach { Clear-Actions }

    It 'registers both scan actions' {
        Register-StaleFilesActions
        $ids = @(Get-Actions -Category 'Deep Cleanup' | ForEach-Object { $_.Id })
        $ids | Should -Contain 'cleanup.stale-files.scan-user-folders'
        $ids | Should -Contain 'cleanup.stale-files.scan-appdata'
    }

    It 'classifies scans as non-destructive' {
        Register-StaleFilesActions
        Get-Actions -Category 'Deep Cleanup' | ForEach-Object { $_.Destructive | Should -BeFalse }
    }

    It 'registers itself as an enumerator' {
        Get-EnumeratorList | Should -Contain 'Register-StaleFilesActions'
    }
}
