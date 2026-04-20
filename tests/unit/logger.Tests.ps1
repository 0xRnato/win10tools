BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/logger.ps1')
}

Describe 'Logger' {
    BeforeEach {
        $script:testRoot = Join-Path $env:TEMP ("w10t-log-" + [Guid]::NewGuid().ToString('N'))
        Initialize-W10Logger -Root $script:testRoot -MirrorToConsole $false
    }

    AfterEach {
        if (Test-Path $script:testRoot) { Remove-Item $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'creates the log root directory' {
        Test-Path $script:testRoot | Should -BeTrue
    }

    It 'returns the daily log path' {
        $expected = Join-Path $script:testRoot ((Get-Date -Format 'yyyy-MM-dd') + '.log')
        Get-W10LogPath | Should -Be $expected
    }

    It 'appends a line when writing a log entry' {
        Write-W10Log -Level 'Info' -Message 'hello'
        (Get-Content (Get-W10LogPath)).Count | Should -BeGreaterOrEqual 1
    }

    It 'emits valid JSONL with expected fields' {
        Write-W10Log -Level 'Info' -Message 'hi' -ActionId 'x.1' -Data @{ key = 'value' }
        $last = (Get-Content (Get-W10LogPath))[-1] | ConvertFrom-Json
        $last.msg      | Should -Be 'hi'
        $last.actionId | Should -Be 'x.1'
        $last.level    | Should -Be 'Info'
        $last.data.key | Should -Be 'value'
        $last.session  | Should -Not -BeNullOrEmpty
        $last.ts       | Should -Not -BeNullOrEmpty
    }

    It 'omits actionId and data when not supplied' {
        Write-W10Log -Level 'Info' -Message 'plain'
        $last = (Get-Content (Get-W10LogPath))[-1] | ConvertFrom-Json
        $last.PSObject.Properties.Name | Should -Not -Contain 'actionId'
        $last.PSObject.Properties.Name | Should -Not -Contain 'data'
    }

    It 'rejects an invalid Level value' {
        { Write-W10Log -Level 'Bogus' -Message 'x' } | Should -Throw
    }

    It 'exposes a stable session id during the session' {
        $first  = Get-W10SessionId
        $second = Get-W10SessionId
        $first | Should -Be $second
        $first.Length | Should -BeGreaterThan 0
    }
}
