$script:W10WingetManifest = @{
    dev     = @(
        'Microsoft.PowerToys'
        'Git.Git'
        'Microsoft.VisualStudioCode'
        'Microsoft.WindowsTerminal'
        'Docker.DockerDesktop'
    )
    media   = @(
        'VideoLAN.VLC'
        'OBSProject.OBSStudio'
        'HandBrake.HandBrake'
    )
    utils   = @(
        '7zip.7zip'
        'Notepad++.Notepad++'
        'voidtools.Everything'
        'ShareX.ShareX'
    )
    browser = @(
        'Mozilla.Firefox'
        'BraveSoftware.BraveBrowser'
    )
    runtime = @(
        'Microsoft.DotNet.SDK.8'
        'OpenJS.NodeJS.LTS'
        'Python.Python.3.12'
    )
}

function Get-WingetManifest { $script:W10WingetManifest }

function Test-WingetAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $null = Get-Command -Name 'winget' -CommandType Application -ErrorAction SilentlyContinue
    $?
}

function Register-AppsActions {
    [CmdletBinding()]
    param()

    foreach ($category in $script:W10WingetManifest.Keys) {
        $pkgs = @($script:W10WingetManifest[$category])

        Register-Action @{
            Id          = "apps.bulk-install.$category"
            Category    = 'Apps'
            Name        = "Install $category apps ($($pkgs.Count)) via winget"
            Description = "Runs winget install for each package in the '$category' category: $($pkgs -join ', ')"
            Risk        = 'Minor'
            Destructive = $true
            NeedsAdmin  = $true
            Context     = @{ Category = $category; Packages = $pkgs }
            Invoke      = {
                param($c)
                if (-not (Test-WingetAvailable)) {
                    throw "winget is not available on this machine"
                }

                $success = 0
                $failed  = 0
                foreach ($pkg in $c.Packages) {
                    try {
                        $wingetArgs = @('install', '--id', $pkg, '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
                        $proc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -WindowStyle Hidden
                        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq -1978335189) {
                            $success++
                        } else {
                            $failed++
                            Write-W10Log -Level 'Warn' -Message 'winget install non-zero' -Data @{ package = $pkg; exit = $proc.ExitCode }
                        }
                    } catch {
                        $failed++
                        Write-W10Log -Level 'Warn' -Message 'winget install threw' -Data @{ package = $pkg; error = $_.Exception.Message }
                    }
                }

                Write-W10Log -Level 'Info' -ActionId "apps.bulk-install.$($c.Category)" -Message "bulk install done" -Data @{
                    category = $c.Category
                    success  = $success
                    failed   = $failed
                    total    = @($c.Packages).Count
                }
            }
            Revert      = {
                param($c)
                if (-not (Test-WingetAvailable)) {
                    throw "winget is not available on this machine"
                }
                $removed = 0
                $failed  = 0
                foreach ($pkg in $c.Packages) {
                    try {
                        $wingetArgs = @('uninstall', '--id', $pkg, '--silent', '--accept-source-agreements', '--disable-interactivity')
                        $proc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -WindowStyle Hidden
                        if ($proc.ExitCode -eq 0) { $removed++ } else { $failed++ }
                    } catch {
                        $failed++
                        Write-W10Log -Level 'Warn' -Message 'winget uninstall threw' -Data @{ package = $pkg; error = $_.Exception.Message }
                    }
                }
                Write-W10Log -Level 'Info' -ActionId "apps.bulk-install.$($c.Category)" -Message 'bulk uninstall (revert) done' -Data @{
                    category = $c.Category
                    removed  = $removed
                    failed   = $failed
                }
            }
            DryRunSummary = {
                param($c)
                "[APPS] winget install ($($c.Category)): $($c.Packages -join ', ')"
            }
        }
    }

    Register-Action @{
        Id          = 'apps.export-installed'
        Category    = 'Apps'
        Name        = 'Export installed apps list (winget export)'
        Description = 'Writes winget export JSON to %TEMP% for backup / replay.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $false
        Invoke      = {
            if (-not (Test-WingetAvailable)) {
                throw "winget is not available on this machine"
            }

            $out = Join-Path $env:TEMP ('winget-export-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
            $proc = Start-Process -FilePath 'winget' -ArgumentList @('export', '-o', $out, '--accept-source-agreements') -Wait -PassThru -WindowStyle Hidden
            if ($proc.ExitCode -ne 0) {
                throw "winget export returned exit code $($proc.ExitCode)"
            }
            Write-W10Log -Level 'Info' -ActionId 'apps.export-installed' -Message 'exported' -Data @{ path = $out }
        }
        DryRunSummary = { '[APPS] winget export -o <tmp>.json' }
    }
}

Register-Enumerator 'Register-AppsActions'
