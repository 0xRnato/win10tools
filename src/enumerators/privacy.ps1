function Get-PrivacyTogglesDefinition {
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param()

    @(
        @{
            Id          = 'telemetry-minimum'
            Name        = 'Limit telemetry to minimum (security/required only)'
            Description = 'Sets AllowTelemetry=1 (basic). Home/Pro cannot set 0; this is the lowest allowed.'
            RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
            ValueName    = 'AllowTelemetry'
            OffValue     = 1
            ValueKind    = 'DWord'
            NeedsAdmin   = $true
            Risk         = 'Safe'
        }
        @{
            Id          = 'advertising-id'
            Name        = 'Disable advertising ID'
            Description = 'Stops apps from using your advertising ID.'
            RegistryPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
            ValueName    = 'Enabled'
            OffValue     = 0
            ValueKind    = 'DWord'
            NeedsAdmin   = $false
            Risk         = 'Safe'
        }
        @{
            Id          = 'activity-history'
            Name        = 'Disable Timeline / activity history upload'
            Description = 'Stops Windows from uploading activity history to Microsoft.'
            RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
            ValueName    = 'UploadUserActivities'
            OffValue     = 0
            ValueKind    = 'DWord'
            NeedsAdmin   = $true
            Risk         = 'Safe'
        }
        @{
            Id          = 'activity-feed'
            Name        = 'Disable activity feed publishing'
            Description = 'Stops apps from publishing activities to your Microsoft account.'
            RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
            ValueName    = 'PublishUserActivities'
            OffValue     = 0
            ValueKind    = 'DWord'
            NeedsAdmin   = $true
            Risk         = 'Safe'
        }
        @{
            Id          = 'tailored-experiences'
            Name        = 'Disable tailored experiences'
            Description = 'Stops Microsoft from tailoring suggestions based on diagnostic data.'
            RegistryPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy'
            ValueName    = 'TailoredExperiencesWithDiagnosticDataEnabled'
            OffValue     = 0
            ValueKind    = 'DWord'
            NeedsAdmin   = $false
            Risk         = 'Safe'
        }
        @{
            Id          = 'typing-insights'
            Name        = 'Disable typing insights / diagnostics'
            Description = 'Stops the typing-personalization data collection.'
            RegistryPath = 'HKCU:\SOFTWARE\Microsoft\Input\TIPC'
            ValueName    = 'Enabled'
            OffValue     = 0
            ValueKind    = 'DWord'
            NeedsAdmin   = $false
            Risk         = 'Safe'
        }
        @{
            Id          = 'inking-personalization'
            Name        = 'Disable inking and typing personalization (implicit collection)'
            Description = 'Restricts implicit ink and text collection for personalization.'
            RegistryPath = 'HKCU:\SOFTWARE\Microsoft\InputPersonalization'
            ValueName    = 'RestrictImplicitInkCollection'
            OffValue     = 1
            ValueKind    = 'DWord'
            NeedsAdmin   = $false
            Risk         = 'Safe'
        }
        @{
            Id          = 'speech-cloud'
            Name        = 'Disable online speech recognition'
            Description = 'Stops sending voice to Microsoft cloud for speech recognition.'
            RegistryPath = 'HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy'
            ValueName    = 'HasAccepted'
            OffValue     = 0
            ValueKind    = 'DWord'
            NeedsAdmin   = $false
            Risk         = 'Safe'
        }
        @{
            Id          = 'feedback-frequency'
            Name        = 'Never ask for feedback'
            Description = 'Disables the Windows feedback popup.'
            RegistryPath = 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules'
            ValueName    = 'NumberOfSIUFInPeriod'
            OffValue     = 0
            ValueKind    = 'DWord'
            NeedsAdmin   = $false
            Risk         = 'Safe'
        }
        @{
            Id          = 'cortana'
            Name        = 'Disable Cortana'
            Description = 'Sets AllowCortana=0 via policy. Start menu search still works.'
            RegistryPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
            ValueName    = 'AllowCortana'
            OffValue     = 0
            ValueKind    = 'DWord'
            NeedsAdmin   = $true
            Risk         = 'Minor'
        }
        @{
            Id          = 'location-tracking'
            Name        = 'Disable system-wide location access'
            Description = 'Denies all apps access to device location services.'
            RegistryPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
            ValueName    = 'Value'
            OffValue     = 'Deny'
            ValueKind    = 'String'
            NeedsAdmin   = $true
            Risk         = 'Minor'
        }
    )
}

function Register-PrivacyActions {
    [CmdletBinding()]
    param()

    foreach ($t in Get-PrivacyTogglesDefinition) {
        $ctx = @{
            Id           = $t.Id
            RegistryPath = $t.RegistryPath
            ValueName    = $t.ValueName
            OffValue     = $t.OffValue
            ValueKind    = $t.ValueKind
            PreviousValue = $null
        }

        try {
            $existing = Get-ItemProperty -LiteralPath $t.RegistryPath -Name $t.ValueName -ErrorAction SilentlyContinue
            if ($existing) { $ctx.PreviousValue = $existing.($t.ValueName) }
        } catch {
            Write-Verbose "privacy read $($t.Id): $($_.Exception.Message)"
        }

        Register-Action @{
            Id          = "privacy.$($t.Id)"
            Category    = 'Privacy'
            Name        = $t.Name
            Description = $t.Description
            Risk        = $t.Risk
            Destructive = $true
            NeedsAdmin  = $t.NeedsAdmin
            Context     = $ctx
            Check       = {
                param($c)
                $cur = Get-ItemProperty -LiteralPath $c.RegistryPath -Name $c.ValueName -ErrorAction SilentlyContinue
                if (-not $cur) { return $false }
                $cur.($c.ValueName) -eq $c.OffValue
            }
            Invoke      = {
                param($c)
                if (-not (Test-Path -LiteralPath $c.RegistryPath)) {
                    New-Item -Path $c.RegistryPath -Force | Out-Null
                }
                Set-ItemProperty -LiteralPath $c.RegistryPath -Name $c.ValueName -Value $c.OffValue -Type $c.ValueKind -Force
            }
            Revert      = {
                param($c)
                if ($null -ne $c.PreviousValue) {
                    Set-ItemProperty -LiteralPath $c.RegistryPath -Name $c.ValueName -Value $c.PreviousValue -Type $c.ValueKind -Force
                } else {
                    Remove-ItemProperty -LiteralPath $c.RegistryPath -Name $c.ValueName -ErrorAction SilentlyContinue
                }
            }
            DryRunSummary = {
                param($c)
                "[PRIVACY] Set $($c.RegistryPath)\$($c.ValueName) = $($c.OffValue) ($($c.ValueKind))"
            }
        }
    }
}

Register-Enumerator 'Register-PrivacyActions'
