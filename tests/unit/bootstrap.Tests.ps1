BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/bootstrap.ps1')
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
}

Describe 'Get-W10BootstrapZipUrl' {
    It 'defaults to the 0xRnato/win10tools main archive URL' {
        Get-W10BootstrapZipUrl |
            Should -Be 'https://github.com/0xRnato/win10tools/archive/refs/heads/main.zip'
    }

    It 'honors Owner, Repo, and Branch overrides' {
        Get-W10BootstrapZipUrl -Owner 'acme' -Repo 'tool' -Branch 'develop' |
            Should -Be 'https://github.com/acme/tool/archive/refs/heads/develop.zip'
    }
}

Describe 'New-W10BootstrapTargetDir' {
    BeforeEach {
        $script:sandbox = Join-Path $env:TEMP ("w10t-bs-sandbox-" + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $script:sandbox -ItemType Directory -Force | Out-Null
    }
    AfterEach {
        if (Test-Path $script:sandbox) { Remove-Item $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'creates a timestamped child directory under Root' {
        $dir = New-W10BootstrapTargetDir -Root $script:sandbox
        Test-Path $dir | Should -BeTrue
        (Split-Path -Leaf $dir) | Should -Match '^win10tools-\d{8}-\d{6}$'
    }
}

Describe 'Find-W10ExtractedRepoRoot' {
    BeforeEach {
        $script:sandbox = Join-Path $env:TEMP ("w10t-bs-find-" + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $script:sandbox -ItemType Directory -Force | Out-Null
    }
    AfterEach {
        if (Test-Path $script:sandbox) { Remove-Item $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'returns the win10tools-<branch> directory that contains run.ps1' {
        $inner = Join-Path $script:sandbox 'win10tools-main'
        New-Item -Path $inner -ItemType Directory -Force | Out-Null
        'param()' | Set-Content (Join-Path $inner 'run.ps1')

        (Find-W10ExtractedRepoRoot -TargetRoot $script:sandbox) | Should -Be $inner
    }

    It 'throws when the extracted directory is missing run.ps1' {
        $inner = Join-Path $script:sandbox 'win10tools-missing'
        New-Item -Path $inner -ItemType Directory -Force | Out-Null
        { Find-W10ExtractedRepoRoot -TargetRoot $script:sandbox } | Should -Throw -ErrorId '*'
    }

    It 'throws when no win10tools-* directory is present' {
        $other = Join-Path $script:sandbox 'something-else'
        New-Item -Path $other -ItemType Directory -Force | Out-Null
        { Find-W10ExtractedRepoRoot -TargetRoot $script:sandbox } | Should -Throw
    }

    It 'throws when TargetRoot does not exist' {
        { Find-W10ExtractedRepoRoot -TargetRoot 'C:\this\does\not\exist\anywhere' } | Should -Throw
    }
}

Describe 'Invoke-W10Bootstrap' {
    BeforeEach {
        $script:sandbox = Join-Path $env:TEMP ("w10t-bs-invoke-" + [Guid]::NewGuid().ToString('N'))
        New-Item -Path $script:sandbox -ItemType Directory -Force | Out-Null
    }
    AfterEach {
        if (Test-Path $script:sandbox) { Remove-Item $script:sandbox -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'downloads the zip, expands it, and reports the run.ps1 path when -DryRun is set' {
        Mock -CommandName Invoke-WebRequest -MockWith {
            param($OutFile)
            $source = Join-Path $env:TEMP ("w10t-bs-src-" + [Guid]::NewGuid().ToString('N'))
            $inner  = Join-Path $source 'win10tools-main'
            New-Item -Path $inner -ItemType Directory -Force | Out-Null
            'param()' | Set-Content (Join-Path $inner 'run.ps1')
            [System.IO.Compression.ZipFile]::CreateFromDirectory($source, $OutFile)
            Remove-Item $source -Recurse -Force
        }

        $result = Invoke-W10Bootstrap -TargetRoot $script:sandbox -DryRun -ZipUrl 'https://example.com/fake.zip'
        $result.Executed | Should -BeFalse
        $result.RepoRoot | Should -Match 'win10tools-main$'
        (Split-Path -Leaf $result.RunPath) | Should -Be 'run.ps1'
    }

    It 'propagates failure when Invoke-WebRequest throws' {
        Mock -CommandName Invoke-WebRequest -MockWith { throw '404 not found' }
        { Invoke-W10Bootstrap -TargetRoot $script:sandbox -DryRun -ZipUrl 'https://example.com/x.zip' } |
            Should -Throw
    }
}
