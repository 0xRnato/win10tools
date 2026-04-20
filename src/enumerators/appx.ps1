function Get-AppxFriendlyName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $leaf = ($Name -split '\.')[-1]
    $leaf = $leaf -creplace '([a-z])([A-Z])', '$1 $2'
    if ($leaf) { $leaf } else { $Name }
}

function ConvertTo-ActionIdFragment {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $clean = ($Value -replace '[^a-zA-Z0-9]', '-').ToLower()
    $clean = $clean -replace '-+', '-'
    $clean.Trim('-')
}

function Register-AppxActions {
    [CmdletBinding()]
    param()

    $installed = @()
    try {
        if (Test-IsAdmin) {
            $installed = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
        } else {
            $installed = @(Get-AppxPackage -ErrorAction Stop)
        }
    } catch {
        Write-W10Log -Level 'Warn' -Message 'Get-AppxPackage failed' -Data @{ error = $_.Exception.Message }
    }

    $installed = @($installed | Group-Object -Property Name | ForEach-Object { $_.Group[0] })

    $provisioned = @()
    if (Test-IsAdmin) {
        try {
            $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
        } catch {
            Write-W10Log -Level 'Warn' -Message 'Get-AppxProvisionedPackage failed' -Data @{ error = $_.Exception.Message }
        }
    }

    $provByName = @{}
    foreach ($p in $provisioned) {
        if ($p.DisplayName) { $provByName[$p.DisplayName] = $p }
    }

    $installedNames = @{}
    foreach ($pkg in $installed) { $installedNames[$pkg.Name] = $true }

    $registered = 0

    foreach ($pkg in $installed) {
        $name     = $pkg.Name
        $friendly = Get-AppxFriendlyName -Name $name
        $risk     = Get-AppxRisk -Name $name
        $prov     = $provByName[$name]
        $idFrag   = ConvertTo-ActionIdFragment -Value $name

        $ctx = @{
            Name             = $name
            PackageFullName  = $pkg.PackageFullName
            Publisher        = $pkg.Publisher
            Version          = $pkg.Version
            HasProvisioned   = [bool]$prov
            ProvisionedName  = if ($prov) { $prov.PackageName } else { $null }
        }

        try {
            Register-Action @{
                Id          = "debloat.appx.$idFrag"
                Category    = 'Debloat'
                Name        = "Remove: $friendly"
                Description = "$name ($($pkg.Version)) - $($pkg.Publisher)"
                Risk        = $risk
                Destructive = $true
                NeedsReboot = $false
                NeedsAdmin  = $true
                Context     = $ctx
                Check       = {
                    param($c)
                    $stillInstalled   = [bool](Get-AppxPackage -Name $c.Name -ErrorAction SilentlyContinue)
                    $stillProvisioned = $false
                    if ($c.HasProvisioned) {
                        $stillProvisioned = [bool](Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                            Where-Object { $_.DisplayName -eq $c.Name })
                    }
                    -not ($stillInstalled -or $stillProvisioned)
                }
                Invoke      = {
                    param($c)
                    $errs = @()
                    try {
                        $pkgs = @(Get-AppxPackage -AllUsers -Name $c.Name -ErrorAction SilentlyContinue)
                        if (-not $pkgs) {
                            $pkgs = @(Get-AppxPackage -Name $c.Name -ErrorAction SilentlyContinue)
                        }
                        foreach ($p in $pkgs) {
                            try { $p | Remove-AppxPackage -AllUsers -ErrorAction Stop }
                            catch { $errs += "installed '$($p.PackageFullName)': $($_.Exception.Message)" }
                        }
                    } catch {
                        $errs += "enumerate installed '$($c.Name)': $($_.Exception.Message)"
                    }

                    if ($c.HasProvisioned -and $c.ProvisionedName) {
                        try {
                            Remove-AppxProvisionedPackage -Online -PackageName $c.ProvisionedName -ErrorAction Stop | Out-Null
                        } catch {
                            $errs += "provisioned '$($c.ProvisionedName)': $($_.Exception.Message)"
                        }
                    }

                    if ($errs.Count -gt 0) { throw ($errs -join ' | ') }
                }
                DryRunSummary = {
                    param($c)
                    $src = @('installed')
                    if ($c.HasProvisioned) { $src += 'provisioned' }
                    "[APPX] $($c.Name) v$($c.Version) [$(($src) -join ',')]"
                }
            }
            $registered++
        } catch {
            Write-W10Log -Level 'Warn' -Message 'appx action register failed' -Data @{
                name  = $name
                error = $_.Exception.Message
            }
        }
    }

    foreach ($p in $provisioned) {
        if (-not $p.DisplayName)                { continue }
        if ($installedNames.ContainsKey($p.DisplayName)) { continue }

        $name     = $p.DisplayName
        $friendly = Get-AppxFriendlyName -Name $name
        $risk     = Get-AppxRisk -Name $name
        $idFrag   = ConvertTo-ActionIdFragment -Value $name

        $ctx = @{
            Name            = $name
            ProvisionedName = $p.PackageName
            Version         = $p.Version
            Publisher       = $p.PublisherId
            Provisioned     = $true
            HasProvisioned  = $true
        }

        try {
            Register-Action @{
                Id          = "debloat.appx.prov.$idFrag"
                Category    = 'Debloat'
                Name        = "Remove (provisioned only): $friendly"
                Description = "$name ($($p.Version)) - provisioned only"
                Risk        = $risk
                Destructive = $true
                NeedsReboot = $false
                NeedsAdmin  = $true
                Context     = $ctx
                Check       = {
                    param($c)
                    -not (Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -eq $c.Name })
                }
                Invoke      = {
                    param($c)
                    Remove-AppxProvisionedPackage -Online -PackageName $c.ProvisionedName -ErrorAction Stop | Out-Null
                }
                DryRunSummary = {
                    param($c)
                    "[APPX-PROV] $($c.Name) v$($c.Version)"
                }
            }
            $registered++
        } catch {
            Write-W10Log -Level 'Warn' -Message 'appx provisioned action register failed' -Data @{
                name  = $name
                error = $_.Exception.Message
            }
        }
    }

    Write-W10Log -Level 'Info' -Message 'appx actions registered' -Data @{ count = $registered }
    $registered
}

Register-Enumerator 'Register-AppxActions'
