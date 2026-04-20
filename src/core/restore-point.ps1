function Test-RestorePointEnabled {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try {
        $status = Get-CimInstance -Namespace 'root/default' -ClassName SystemRestoreConfig -ErrorAction Stop
        return [bool]$status
    } catch {
        try {
            $null = Get-ComputerRestorePoint -ErrorAction Stop
            return $true
        } catch {
            return $false
        }
    }
}

function Enable-RestorePointProtection {
    [CmdletBinding()]
    param([string]$Drive = 'C:\')

    if (-not (Test-IsAdmin)) {
        throw 'Enabling System Restore requires Administrator rights.'
    }

    try {
        Enable-ComputerRestore -Drive $Drive -ErrorAction Stop
        Write-W10Log -Level 'Info' -Message 'System Restore enabled' -Data @{ drive = $Drive }
        return $true
    } catch {
        Write-W10Log -Level 'Warn' -Message 'failed to enable System Restore' -Data @{ drive = $Drive; error = $_.Exception.Message }
        return $false
    }
}

function New-AutoRestorePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Description,
        [ValidateSet('APPLICATION_INSTALL', 'APPLICATION_UNINSTALL', 'DEVICE_DRIVER_INSTALL', 'MODIFY_SETTINGS', 'CANCELLED_OPERATION')]
        [string]$RestorePointType = 'MODIFY_SETTINGS',
        [switch]$IgnoreRateLimit
    )

    if (-not (Test-IsAdmin)) {
        Write-W10Log -Level 'Warn' -Message 'restore point skipped - not admin' -Data @{ description = $Description }
        return $false
    }

    $rateLimitKey  = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $rateLimitName = 'SystemRestorePointCreationFrequency'
    $originalValue = $null

    if ($IgnoreRateLimit) {
        try {
            if (Test-Path $rateLimitKey) {
                $item = Get-ItemProperty -Path $rateLimitKey -Name $rateLimitName -ErrorAction SilentlyContinue
                if ($item) { $originalValue = $item.$rateLimitName }
            } else {
                New-Item -Path $rateLimitKey -Force | Out-Null
            }
            Set-ItemProperty -Path $rateLimitKey -Name $rateLimitName -Value 0 -Type DWord -Force
        } catch {
            Write-W10Log -Level 'Warn' -Message 'could not override rate limit' -Data @{ error = $_.Exception.Message }
        }
    }

    try {
        Checkpoint-Computer -Description $Description -RestorePointType $RestorePointType -ErrorAction Stop
        Write-W10Log -Level 'Info' -Message 'restore point created' -Data @{ description = $Description; type = $RestorePointType }
        return $true
    } catch {
        $msg = $_.Exception.Message
        if ($msg -match 'within the specified interval' -or $msg -match '0x80070016') {
            Write-W10Log -Level 'Info' -Message 'restore point skipped by Windows rate limit' -Data @{ description = $Description }
            return $false
        }
        Write-W10Log -Level 'Error' -Message 'restore point creation failed' -Data @{ description = $Description; error = $msg }
        return $false
    } finally {
        if ($IgnoreRateLimit) {
            try {
                if ($null -ne $originalValue) {
                    Set-ItemProperty -Path $rateLimitKey -Name $rateLimitName -Value $originalValue -Type DWord -Force
                } else {
                    Remove-ItemProperty -Path $rateLimitKey -Name $rateLimitName -ErrorAction SilentlyContinue
                }
            } catch {
                Write-W10Log -Level 'Warn' -Message 'failed to restore rate limit value' -Data @{ error = $_.Exception.Message }
            }
        }
    }
}

function Get-LatestRestorePoint {
    [CmdletBinding()]
    param()

    try {
        Get-ComputerRestorePoint -ErrorAction Stop |
            Sort-Object CreationTime -Descending |
            Select-Object -First 1
    } catch {
        $null
    }
}
