function Register-TweakActions {
    [CmdletBinding()]
    param()

    Register-Action @{
        Id          = 'tweaks.power.ultimate-performance'
        Category    = 'Tweaks'
        Name        = 'Import and activate Ultimate Performance power plan'
        Description = 'Duplicates the Ultimate Performance plan and sets it active.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $ultimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
            & powercfg /duplicatescheme $ultimateGuid | Out-Null
            $out = & powercfg /list 2>&1 | Out-String
            $match = [regex]::Match($out, '([0-9a-f\-]{36})\s+\(Ultimate Performance\)')
            if ($match.Success) {
                & powercfg /setactive $match.Groups[1].Value | Out-Null
                Write-W10Log -Level 'Info' -ActionId 'tweaks.power.ultimate-performance' -Message 'power plan activated' -Data @{ guid = $match.Groups[1].Value }
            } else {
                Write-W10Log -Level 'Warn' -ActionId 'tweaks.power.ultimate-performance' -Message 'could not find Ultimate Performance after duplicate'
            }
        }
        DryRunSummary = { '[TWEAKS] powercfg /duplicatescheme <UltimatePerf> + /setactive' }
    }

    Register-Action @{
        Id          = 'tweaks.network.flush-dns'
        Category    = 'Tweaks'
        Name        = 'Flush DNS resolver cache'
        Description = 'Runs ipconfig /flushdns.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            & ipconfig /flushdns | Out-Null
            Write-W10Log -Level 'Info' -ActionId 'tweaks.network.flush-dns' -Message 'dns cache flushed'
        }
        DryRunSummary = { '[TWEAKS] ipconfig /flushdns' }
    }

    Register-Action @{
        Id          = 'tweaks.network.reset-winsock'
        Category    = 'Tweaks'
        Name        = 'Reset Winsock catalog'
        Description = 'Runs netsh winsock reset. Requires a reboot to complete.'
        Risk        = 'Minor'
        Destructive = $true
        NeedsReboot = $true
        NeedsAdmin  = $true
        Invoke      = {
            & netsh winsock reset | Out-Null
            Write-W10Log -Level 'Info' -ActionId 'tweaks.network.reset-winsock' -Message 'winsock reset; reboot required'
        }
        DryRunSummary = { '[TWEAKS] netsh winsock reset (reboot needed)' }
    }

    $dnsDefs = @(
        @{ Id='cloudflare'; Name='Cloudflare';     Primary='1.1.1.1';    Secondary='1.0.0.1' }
        @{ Id='google';     Name='Google';         Primary='8.8.8.8';    Secondary='8.8.4.4' }
        @{ Id='adguard';    Name='AdGuard';        Primary='94.140.14.14'; Secondary='94.140.15.15' }
        @{ Id='quad9';      Name='Quad9';          Primary='9.9.9.9';    Secondary='149.112.112.112' }
    )

    foreach ($d in $dnsDefs) {
        Register-Action @{
            Id          = "tweaks.network.dns-$($d.Id)"
            Category    = 'Tweaks'
            Name        = "Set DNS to $($d.Name) ($($d.Primary))"
            Description = "Sets DNS servers on the active IPv4 interface to $($d.Primary) and $($d.Secondary). Revertable by setting DNS back to DHCP."
            Risk        = 'Minor'
            Destructive = $true
            NeedsAdmin  = $true
            Context     = @{ Primary = $d.Primary; Secondary = $d.Secondary }
            Invoke      = {
                param($c)
                $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                    Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
                if (-not $adapter) { throw 'no active physical adapter found' }

                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @($c.Primary, $c.Secondary) -ErrorAction Stop
                Write-W10Log -Level 'Info' -ActionId "tweaks.network.dns" -Message 'DNS servers set' -Data @{
                    interface = $adapter.Name
                    primary   = $c.Primary
                    secondary = $c.Secondary
                }
            }
            Revert      = {
                $adapter = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                    Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
                if (-not $adapter) { return }
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
            }
            DryRunSummary = {
                param($c)
                "[TWEAKS] Set DNS on active adapter to $($c.Primary) / $($c.Secondary)"
            }
        }
    }

    $explorerTweaks = @(
        @{
            Id          = 'explorer.show-file-extensions'
            Name        = 'Show known file extensions'
            Description = 'Unhides file extensions in Explorer.'
            Path        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Value       = 'HideFileExt'
            OffValue    = 0
            OnValue     = 1
        }
        @{
            Id          = 'explorer.show-hidden-files'
            Name        = 'Show hidden files'
            Description = 'Shows files marked hidden in Explorer.'
            Path        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Value       = 'Hidden'
            OffValue    = 1
            OnValue     = 2
        }
        @{
            Id          = 'explorer.dark-mode-apps'
            Name        = 'Dark mode for apps'
            Description = 'Sets AppsUseLightTheme=0.'
            Path        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            Value       = 'AppsUseLightTheme'
            OffValue    = 0
            OnValue     = 1
        }
        @{
            Id          = 'explorer.dark-mode-system'
            Name        = 'Dark mode for Windows system UI'
            Description = 'Sets SystemUsesLightTheme=0.'
            Path        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            Value       = 'SystemUsesLightTheme'
            OffValue    = 0
            OnValue     = 1
        }
        @{
            Id          = 'taskbar.hide-search'
            Name        = 'Hide the taskbar search box (icon only)'
            Description = 'Sets SearchboxTaskbarMode=1 (icon) instead of 2 (box).'
            Path        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'
            Value       = 'SearchboxTaskbarMode'
            OffValue    = 1
            OnValue     = 2
        }
        @{
            Id          = 'taskbar.hide-task-view'
            Name        = 'Hide Task View button on taskbar'
            Description = 'Sets ShowTaskViewButton=0.'
            Path        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Value       = 'ShowTaskViewButton'
            OffValue    = 0
            OnValue     = 1
        }
        @{
            Id          = 'taskbar.hide-people'
            Name        = 'Hide People button on taskbar'
            Description = 'Sets PeopleBand=0.'
            Path        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People'
            Value       = 'PeopleBand'
            OffValue    = 0
            OnValue     = 1
        }
    )

    foreach ($t in $explorerTweaks) {
        $previous = $null
        try {
            $cur = Get-ItemProperty -LiteralPath $t.Path -Name $t.Value -ErrorAction SilentlyContinue
            if ($cur) { $previous = $cur.($t.Value) }
        } catch {
            Write-Verbose "tweak read $($t.Id): $($_.Exception.Message)"
        }

        $ctx = @{
            Path          = $t.Path
            Value         = $t.Value
            OffValue      = $t.OffValue
            OnValue       = $t.OnValue
            PreviousValue = $previous
        }

        Register-Action @{
            Id          = "tweaks.$($t.Id)"
            Category    = 'Tweaks'
            Name        = $t.Name
            Description = $t.Description
            Risk        = 'Safe'
            Destructive = $true
            NeedsAdmin  = $false
            Context     = $ctx
            Check       = {
                param($c)
                $cur = Get-ItemProperty -LiteralPath $c.Path -Name $c.Value -ErrorAction SilentlyContinue
                if (-not $cur) { return $false }
                $cur.($c.Value) -eq $c.OffValue
            }
            Invoke      = {
                param($c)
                if (-not (Test-Path -LiteralPath $c.Path)) {
                    New-Item -Path $c.Path -Force | Out-Null
                }
                Set-ItemProperty -LiteralPath $c.Path -Name $c.Value -Value $c.OffValue -Type DWord -Force
            }
            Revert      = {
                param($c)
                if ($null -ne $c.PreviousValue) {
                    Set-ItemProperty -LiteralPath $c.Path -Name $c.Value -Value $c.PreviousValue -Type DWord -Force
                } else {
                    Set-ItemProperty -LiteralPath $c.Path -Name $c.Value -Value $c.OnValue -Type DWord -Force
                }
            }
            DryRunSummary = {
                param($c)
                "[TWEAKS] Set $($c.Path)\$($c.Value) = $($c.OffValue)"
            }
        }
    }
}

Register-Enumerator 'Register-TweakActions'
