function Get-StartupApprovedBytes {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([bool]$Enabled)

    $bytes = New-Object byte[] 12
    $bytes[0] = if ($Enabled) { 0x02 } else { 0x03 }
    $bytes
}

function Get-RunKeyEntries {
    [CmdletBinding()]
    param()

    $runKeys = @(
        @{ Hive = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';          Approved = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';          Scope = 'User'    }
        @{ Hive = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';          Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';          Scope = 'Machine' }
        @{ Hive = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32';    Scope = 'Machine' }
    )

    $entries = [System.Collections.Generic.List[object]]::new()

    foreach ($r in $runKeys) {
        if (-not (Test-Path -LiteralPath $r.Hive)) { continue }
        try {
            $props = Get-ItemProperty -LiteralPath $r.Hive -ErrorAction Stop
        } catch { continue }

        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -match '^PS') { continue }
            if ([string]::IsNullOrEmpty($p.Value)) { continue }

            $enabled = $true
            if (Test-Path -LiteralPath $r.Approved) {
                try {
                    $ap = Get-ItemProperty -LiteralPath $r.Approved -Name $p.Name -ErrorAction SilentlyContinue
                    if ($ap -and $ap.($p.Name) -is [byte[]]) {
                        $enabled = ($ap.($p.Name)[0] -eq 0x02)
                    }
                } catch {
                    Write-Verbose "startup-approved probe: $($_.Exception.Message)"
                }
            }

            $entries.Add([pscustomobject]@{
                Kind     = 'RunKey'
                Scope    = $r.Scope
                Hive     = $r.Hive
                Approved = $r.Approved
                Path     = $null
                Name     = $p.Name
                Command  = [string]$p.Value
                Enabled  = $enabled
            }) | Out-Null
        }
    }

    $entries
}

function Get-StartupFolderEntries {
    [CmdletBinding()]
    param()

    $folders = @(
        @{ Path = (Join-Path $env:APPDATA    'Microsoft\Windows\Start Menu\Programs\Startup'); Scope = 'User'    }
        @{ Path = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); Scope = 'Machine' }
    )

    $entries = [System.Collections.Generic.List[object]]::new()

    foreach ($f in $folders) {
        if (-not (Test-Path -LiteralPath $f.Path)) { continue }
        Get-ChildItem -LiteralPath $f.Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $disabled = ($_.Name -like '*.w10t-disabled')
            $entries.Add([pscustomobject]@{
                Kind     = 'StartupFolder'
                Scope    = $f.Scope
                Hive     = $null
                Approved = $null
                Path     = $_.FullName
                Name     = $_.Name
                Command  = $null
                Enabled  = -not $disabled
            }) | Out-Null
        }
    }

    $entries
}

function Get-StartupScheduledTasks {
    [CmdletBinding()]
    param()

    $entries = [System.Collections.Generic.List[object]]::new()
    try {
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue)
    } catch {
        return $entries
    }

    foreach ($t in $tasks) {
        if ($t.TaskPath -like '\Microsoft\Windows\*') { continue }

        $triggers = @($t.Triggers | Where-Object {
            $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger'
        })
        if ($triggers.Count -eq 0) { continue }

        $entries.Add([pscustomobject]@{
            Kind     = 'ScheduledTask'
            Scope    = if ($t.Principal.RunLevel -eq 'Highest') { 'Machine' } else { 'User' }
            Hive     = $null
            Approved = $null
            Path     = $t.TaskPath + $t.TaskName
            Name     = $t.TaskName
            Command  = $null
            Enabled  = ($t.State -ne 'Disabled')
        }) | Out-Null
    }

    $entries
}

function Register-StartupActions {
    [CmdletBinding()]
    param()

    $all = @()
    $all += @(Get-RunKeyEntries)
    $all += @(Get-StartupFolderEntries)
    $all += @(Get-StartupScheduledTasks)

    foreach ($e in $all) {
        $idFrag = ($e.Kind.ToLower() + '-' + $e.Scope.ToLower() + '-' + (Get-NormalizedAppName $e.Name))

        $ctx = @{
            Kind     = $e.Kind
            Scope    = $e.Scope
            Name     = $e.Name
            Hive     = $e.Hive
            Approved = $e.Approved
            Path     = $e.Path
            Command  = $e.Command
        }

        try {
            Register-Action @{
                Id          = "startup.disable.$idFrag"
                Category    = 'Startup'
                Name        = "Disable $($e.Kind) [$($e.Scope)]: $($e.Name)"
                Description = "Disables the startup entry '$($e.Name)' (source: $($e.Kind)). Revertable."
                Risk        = 'Minor'
                Destructive = $true
                NeedsAdmin  = ($e.Scope -eq 'Machine')
                Context     = $ctx
                Check       = {
                    param($c)
                    switch ($c.Kind) {
                        'RunKey' {
                            if (-not (Test-Path -LiteralPath $c.Approved)) { return $false }
                            $ap = Get-ItemProperty -LiteralPath $c.Approved -Name $c.Name -ErrorAction SilentlyContinue
                            if (-not $ap) { return $false }
                            return ($ap.($c.Name)[0] -eq 0x03)
                        }
                        'StartupFolder' {
                            -not (Test-Path -LiteralPath $c.Path)
                        }
                        'ScheduledTask' {
                            try {
                                $t = Get-ScheduledTask -TaskPath ($c.Path -replace [regex]::Escape($c.Name) + '$', '') -TaskName $c.Name -ErrorAction SilentlyContinue
                                if (-not $t) { return $false }
                                return ($t.State -eq 'Disabled')
                            } catch { return $false }
                        }
                        default { return $false }
                    }
                }
                Invoke      = {
                    param($c)
                    switch ($c.Kind) {
                        'RunKey' {
                            if (-not (Test-Path -LiteralPath $c.Approved)) {
                                New-Item -Path $c.Approved -Force | Out-Null
                            }
                            $disabledBytes = Get-StartupApprovedBytes -Enabled $false
                            Set-ItemProperty -LiteralPath $c.Approved -Name $c.Name -Value $disabledBytes -Type Binary -Force
                        }
                        'StartupFolder' {
                            if (Test-Path -LiteralPath $c.Path) {
                                $disabled = $c.Path + '.w10t-disabled'
                                Move-Item -LiteralPath $c.Path -Destination $disabled -Force
                            }
                        }
                        'ScheduledTask' {
                            Disable-ScheduledTask -TaskPath ($c.Path -replace [regex]::Escape($c.Name) + '$', '') -TaskName $c.Name -ErrorAction Stop | Out-Null
                        }
                    }
                }
                Revert      = {
                    param($c)
                    switch ($c.Kind) {
                        'RunKey' {
                            if (-not (Test-Path -LiteralPath $c.Approved)) { return }
                            $enabledBytes = Get-StartupApprovedBytes -Enabled $true
                            Set-ItemProperty -LiteralPath $c.Approved -Name $c.Name -Value $enabledBytes -Type Binary -Force
                        }
                        'StartupFolder' {
                            $disabled = $c.Path + '.w10t-disabled'
                            if (Test-Path -LiteralPath $disabled) {
                                Move-Item -LiteralPath $disabled -Destination $c.Path -Force
                            }
                        }
                        'ScheduledTask' {
                            Enable-ScheduledTask -TaskPath ($c.Path -replace [regex]::Escape($c.Name) + '$', '') -TaskName $c.Name -ErrorAction Stop | Out-Null
                        }
                    }
                }
                DryRunSummary = {
                    param($c)
                    "[STARTUP] Disable $($c.Kind) [$($c.Scope)] $($c.Name)"
                }
            }
        } catch {
            Write-W10Log -Level 'Warn' -Message 'startup action register failed' -Data @{ name = $e.Name; error = $_.Exception.Message }
        }
    }
}

Register-Enumerator 'Register-StartupActions'
