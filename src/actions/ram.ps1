function Register-RamActions {
    [CmdletBinding()]
    param()

    Register-Action @{
        Id          = 'ram.trim-working-sets'
        Category    = 'RAM'
        Name        = 'Trim working sets (all processes)'
        Description = 'Calls psapi!EmptyWorkingSet on every accessible process. OS re-pages if needed. Free RAM jumps up; standby list grows.'
        Risk        = 'Safe'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $sig = @'
[DllImport("psapi.dll")]
public static extern int EmptyWorkingSet(IntPtr hProcess);
'@
            if (-not ('Win10Tools.Psapi' -as [type])) {
                Add-Type -MemberDefinition $sig -Name Psapi -Namespace Win10Tools -PassThru | Out-Null
            }

            $trimmed = 0
            $failed  = 0
            foreach ($p in Get-Process -ErrorAction SilentlyContinue) {
                try {
                    $null = [Win10Tools.Psapi]::EmptyWorkingSet($p.Handle)
                    $trimmed++
                } catch { $failed++ }
            }

            Write-W10Log -Level 'Info' -ActionId 'ram.trim-working-sets' -Message "trimmed $trimmed processes ($failed skipped)"
        }
        DryRunSummary = { '[RAM] EmptyWorkingSet on every accessible process' }
    }

    Register-Action @{
        Id          = 'ram.clear-standby-list'
        Category    = 'RAM'
        Name        = 'Purge standby list'
        Description = 'Purges the Memory Manager standby list. Frees cached pages immediately; kernel re-fills as demand dictates.'
        Risk        = 'Minor'
        Destructive = $false
        NeedsAdmin  = $true
        Invoke      = {
            $sig = @'
[DllImport("ntdll.dll")]
public static extern uint NtSetSystemInformation(int SystemInformationClass, ref int SystemInformation, int SystemInformationLength);
'@
            if (-not ('Win10Tools.Ntdll' -as [type])) {
                Add-Type -MemberDefinition $sig -Name Ntdll -Namespace Win10Tools -PassThru | Out-Null
            }

            $cmd = 4   # MemoryPurgeStandbyList
            $rc  = [Win10Tools.Ntdll]::NtSetSystemInformation(80, [ref]$cmd, 4)
            if ($rc -ne 0) {
                throw "NtSetSystemInformation returned 0x$($rc.ToString('X'))"
            }

            Write-W10Log -Level 'Info' -ActionId 'ram.clear-standby-list' -Message 'standby list purged'
        }
        DryRunSummary = { '[RAM] NtSetSystemInformation(SystemMemoryListInformation, MemoryPurgeStandbyList)' }
    }
}

Register-Enumerator 'Register-RamActions'
