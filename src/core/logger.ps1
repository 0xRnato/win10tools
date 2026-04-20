$script:W10LogRoot      = Join-Path $env:LOCALAPPDATA 'win10tools\logs'
$script:W10LogInitDone  = $false
$script:W10LogMirror    = $true
$script:W10SessionId    = [Guid]::NewGuid().ToString('N').Substring(0, 8)

function Initialize-W10Logger {
    [CmdletBinding()]
    param(
        [string]$Root,
        [bool]$MirrorToConsole = $true
    )

    if ($Root) { $script:W10LogRoot = $Root }
    $script:W10LogMirror = $MirrorToConsole

    if (-not (Test-Path -LiteralPath $script:W10LogRoot)) {
        New-Item -Path $script:W10LogRoot -ItemType Directory -Force | Out-Null
    }

    $script:W10LogInitDone = $true
    Write-W10Log -Level 'Info' -Message "logger initialised" -Data @{
        sessionId = $script:W10SessionId
        root      = $script:W10LogRoot
        pid       = $PID
        user      = $env:USERNAME
        host      = $env:COMPUTERNAME
        psVersion = $PSVersionTable.PSVersion.ToString()
    }
}

function Get-W10LogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not $script:W10LogInitDone) { Initialize-W10Logger }
    Join-Path $script:W10LogRoot ((Get-Date -Format 'yyyy-MM-dd') + '.log')
}

function Write-W10Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$ActionId,
        [hashtable]$Data
    )

    if (-not $script:W10LogInitDone) { Initialize-W10Logger }

    $entry = [ordered]@{
        ts        = (Get-Date).ToString('o')
        session   = $script:W10SessionId
        level     = $Level
        msg       = $Message
    }

    if ($ActionId) { $entry.actionId = $ActionId }
    if ($Data)     { $entry.data     = $Data }

    $json = $entry | ConvertTo-Json -Compress -Depth 5

    $path = Get-W10LogPath
    Add-Content -LiteralPath $path -Value $json -Encoding UTF8

    if ($script:W10LogMirror) {
        $prefix = switch ($Level) {
            'Debug' { '[dbg]' }
            'Info'  { '[inf]' }
            'Warn'  { '[wrn]' }
            'Error' { '[err]' }
        }
        $line = "$prefix $Message"
        switch ($Level) {
            'Debug' { Write-Verbose $line }
            'Info'  { Write-Host    $line }
            'Warn'  { Write-Warning $Message }
            'Error' { Write-Host    $line -ForegroundColor Red }
        }
    }
}

function Get-W10SessionId { $script:W10SessionId }
