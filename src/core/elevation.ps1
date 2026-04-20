function Test-IsAdmin {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    [CmdletBinding()]
    param(
        [string]$Message = 'This action requires Administrator rights.'
    )

    if (-not (Test-IsAdmin)) {
        throw $Message
    }
}

function Invoke-Elevate {
    [CmdletBinding()]
    param(
        [string]$ScriptPath,
        [string[]]$ArgumentList,
        [string]$BootstrapUrl
    )

    if (Test-IsAdmin) { return }

    $psExe = (Get-Process -Id $PID).Path
    if (-not $psExe) { $psExe = 'powershell.exe' }

    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass')

    if ($ScriptPath -and (Test-Path -LiteralPath $ScriptPath)) {
        $args += @('-File', $ScriptPath)
        if ($ArgumentList) { $args += $ArgumentList }
    }
    elseif ($BootstrapUrl) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(
            "iwr -useb '$BootstrapUrl' | iex"
        ))
        $args += @('-EncodedCommand', $encoded)
    }
    else {
        throw 'Cannot elevate: no ScriptPath and no BootstrapUrl provided.'
    }

    Start-Process -FilePath $psExe -ArgumentList $args -Verb RunAs | Out-Null
    exit 0
}
