$script:W10TweakableServices = @(
    @{
        Name        = 'DiagTrack'
        Description = 'Connected User Experiences and Telemetry. Sends diagnostic data to Microsoft.'
        SafeToStop  = $true
        Risk        = 'Safe'
    }
    @{
        Name        = 'dmwappushservice'
        Description = 'WAP Push Message Routing. Handles push-to-install messages; unused on most desktops.'
        SafeToStop  = $true
        Risk        = 'Safe'
    }
    @{
        Name        = 'RetailDemo'
        Description = 'RetailDemo service. Only useful on retail display models.'
        SafeToStop  = $true
        Risk        = 'Safe'
    }
    @{
        Name        = 'MapsBroker'
        Description = 'Downloaded Maps Manager. Only needed if you use the Maps UWP app offline.'
        SafeToStop  = $true
        Risk        = 'Minor'
    }
    @{
        Name        = 'WbioSrvc'
        Description = 'Windows Biometric Service. Disable only if you do not use fingerprint/face login.'
        SafeToStop  = $false
        Risk        = 'Minor'
    }
    @{
        Name        = 'PcaSvc'
        Description = 'Program Compatibility Assistant. Popup when legacy apps fail; disabling is cosmetic.'
        SafeToStop  = $true
        Risk        = 'Minor'
    }
    @{
        Name        = 'Fax'
        Description = 'Fax service. Almost always unused on consumer machines.'
        SafeToStop  = $true
        Risk        = 'Safe'
    }
)

function Register-ServicesActions {
    [CmdletBinding()]
    param()

    foreach ($svc in $script:W10TweakableServices) {
        $svcObj = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if (-not $svcObj) { continue }

        $currentStart = $null
        try {
            $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($svc.Name)'" -ErrorAction SilentlyContinue
            if ($cim) { $currentStart = $cim.StartMode }
        } catch {
            Write-Verbose "CIM query for service $($svc.Name): $($_.Exception.Message)"
        }

        $ctx = @{
            Name          = $svc.Name
            Description   = $svc.Description
            PreviousStart = $currentStart
        }

        Register-Action @{
            Id          = "services.disable.$(Get-NormalizedAppName $svc.Name)"
            Category    = 'Services'
            Name        = "Disable service: $($svc.Name)"
            Description = $svc.Description
            Risk        = $svc.Risk
            Destructive = $true
            NeedsAdmin  = $true
            Context     = $ctx
            Check       = {
                param($c)
                $s = Get-Service -Name $c.Name -ErrorAction SilentlyContinue
                if (-not $s) { return $true }
                try {
                    $cim = Get-CimInstance -ClassName Win32_Service -Filter "Name='$($c.Name)'" -ErrorAction Stop
                    return ($cim.StartMode -eq 'Disabled' -and $s.Status -eq 'Stopped')
                } catch { return $false }
            }
            Invoke      = {
                param($c)
                $s = Get-Service -Name $c.Name -ErrorAction SilentlyContinue
                if ($s -and $s.Status -eq 'Running') {
                    try { Stop-Service -Name $c.Name -Force -ErrorAction Stop } catch {
                        Write-W10Log -Level 'Warn' -ActionId "services.disable.$(Get-NormalizedAppName $c.Name)" -Message 'stop failed (may require reboot)' -Data @{ error = $_.Exception.Message }
                    }
                }
                Set-Service -Name $c.Name -StartupType Disabled -ErrorAction Stop
            }
            Revert      = {
                param($c)
                $target = if ($c.PreviousStart) { $c.PreviousStart } else { 'Manual' }
                $pwshMode = switch ($target) {
                    'Auto'     { 'Automatic' }
                    'Manual'   { 'Manual' }
                    'Disabled' { 'Disabled' }
                    default    { 'Manual' }
                }
                Set-Service -Name $c.Name -StartupType $pwshMode -ErrorAction Stop
            }
            DryRunSummary = {
                param($c)
                "[SERVICES] Disable '$($c.Name)' (was StartMode=$($c.PreviousStart))"
            }
        }
    }
}

Register-Enumerator 'Register-ServicesActions'
