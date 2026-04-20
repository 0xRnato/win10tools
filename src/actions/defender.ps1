function Register-DefenderActions {
    [CmdletBinding()]
    param()

    Register-Action @{
        Id          = 'defender.quick-scan'
        Category    = 'Defender'
        Name        = 'Run Defender Quick Scan'
        Description = 'Kicks off Windows Defender Quick Scan. Takes a few minutes.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            Start-MpScan -ScanType QuickScan -ErrorAction Stop
            Write-W10Log -Level 'Info' -ActionId 'defender.quick-scan' -Message 'quick scan completed'
        }
        DryRunSummary = { '[DEFENDER] Start-MpScan -ScanType QuickScan' }
    }

    Register-Action @{
        Id          = 'defender.full-scan'
        Category    = 'Defender'
        Name        = 'Run Defender Full Scan (long)'
        Description = 'Kicks off Windows Defender Full Scan. Can take hours on spinning rust.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            Start-MpScan -ScanType FullScan -ErrorAction Stop
            Write-W10Log -Level 'Info' -ActionId 'defender.full-scan' -Message 'full scan completed'
        }
        DryRunSummary = { '[DEFENDER] Start-MpScan -ScanType FullScan' }
    }

    Register-Action @{
        Id          = 'defender.update-signatures'
        Category    = 'Defender'
        Name        = 'Update Defender signatures'
        Description = 'Fetches the latest definitions via Update-MpSignature.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            Update-MpSignature -ErrorAction Stop
            Write-W10Log -Level 'Info' -ActionId 'defender.update-signatures' -Message 'signatures updated'
        }
        DryRunSummary = { '[DEFENDER] Update-MpSignature' }
    }

    Register-Action @{
        Id          = 'defender.show-status'
        Category    = 'Defender'
        Name        = 'Show Defender status'
        Description = 'Prints Get-MpComputerStatus + Get-MpPreference key values.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $false
        Invoke      = {
            try {
                $cs = Get-MpComputerStatus -ErrorAction Stop
                $data = @{
                    RealTimeProtectionEnabled       = $cs.RealTimeProtectionEnabled
                    IoavProtectionEnabled           = $cs.IoavProtectionEnabled
                    BehaviorMonitorEnabled          = $cs.BehaviorMonitorEnabled
                    TamperProtectionEnabled         = $cs.IsTamperProtected
                    AntispywareSignatureAgeDays     = $cs.AntispywareSignatureAge
                    AntivirusSignatureAgeDays       = $cs.AntivirusSignatureAge
                    QuickScanStartTime              = $cs.QuickScanStartTime
                    FullScanStartTime               = $cs.FullScanStartTime
                }
                Write-W10Log -Level 'Info' -ActionId 'defender.show-status' -Message 'status report' -Data $data
            } catch {
                Write-W10Log -Level 'Warn' -ActionId 'defender.show-status' -Message 'Get-MpComputerStatus failed' -Data @{ error = $_.Exception.Message }
                throw
            }
        }
        DryRunSummary = { '[DEFENDER] Get-MpComputerStatus summary' }
    }

    Register-Action @{
        Id          = 'defender.show-threat-history'
        Category    = 'Defender'
        Name        = 'Show Defender threat history'
        Description = 'Prints recent Get-MpThreatDetection events.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $false
        Invoke      = {
            $threats = @(Get-MpThreatDetection -ErrorAction SilentlyContinue)
            Write-W10Log -Level 'Info' -ActionId 'defender.show-threat-history' -Message "found $($threats.Count) threat detections" -Data @{
                count = $threats.Count
                latest = if ($threats.Count -gt 0) { $threats[0].InitialDetectionTime } else { $null }
            }
        }
        DryRunSummary = { '[DEFENDER] Get-MpThreatDetection summary' }
    }
}

Register-Enumerator 'Register-DefenderActions'
