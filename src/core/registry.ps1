$script:Win10ToolsActions = [System.Collections.Generic.List[hashtable]]::new()
$script:Win10ToolsActionIds = [System.Collections.Generic.HashSet[string]]::new()

$script:ValidRisks = @('Safe', 'Minor', 'Avoid')
$script:RequiredKeys = @('Id', 'Category', 'Name', 'Description', 'Risk', 'Invoke')

function Register-Action {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [hashtable]$Action
    )

    process {
        foreach ($key in $script:RequiredKeys) {
            if (-not $Action.ContainsKey($key)) {
                throw "Action missing required key '$key': $($Action | ConvertTo-Json -Compress -Depth 2)"
            }
        }

        if ($Action.Risk -notin $script:ValidRisks) {
            throw "Action '$($Action.Id)' has invalid Risk '$($Action.Risk)'. Must be one of: $($script:ValidRisks -join ', ')"
        }

        if ($Action.Invoke -isnot [scriptblock]) {
            throw "Action '$($Action.Id)' Invoke must be a scriptblock"
        }

        if ($Action.ContainsKey('Check') -and $Action.Check -and $Action.Check -isnot [scriptblock]) {
            throw "Action '$($Action.Id)' Check must be a scriptblock or `$null"
        }

        if ($Action.ContainsKey('Revert') -and $Action.Revert -and $Action.Revert -isnot [scriptblock]) {
            throw "Action '$($Action.Id)' Revert must be a scriptblock or `$null"
        }

        if (-not $script:Win10ToolsActionIds.Add($Action.Id)) {
            throw "Duplicate action Id '$($Action.Id)' - already registered"
        }

        $normalised = @{
            Id             = $Action.Id
            Category       = $Action.Category
            Name           = $Action.Name
            Description    = $Action.Description
            Risk           = $Action.Risk
            Destructive    = if ($Action.ContainsKey('Destructive'))   { [bool]$Action.Destructive }   else { $false }
            NeedsReboot    = if ($Action.ContainsKey('NeedsReboot'))   { [bool]$Action.NeedsReboot }   else { $false }
            NeedsAdmin     = if ($Action.ContainsKey('NeedsAdmin'))    { [bool]$Action.NeedsAdmin }    else { $true }
            Context        = if ($Action.ContainsKey('Context'))       { $Action.Context }             else { @{} }
            Check          = if ($Action.ContainsKey('Check'))         { $Action.Check }               else { $null }
            Invoke         = $Action.Invoke
            Revert         = if ($Action.ContainsKey('Revert'))        { $Action.Revert }              else { $null }
            DryRunSummary  = if ($Action.ContainsKey('DryRunSummary')) { $Action.DryRunSummary }       else { $null }
        }

        $script:Win10ToolsActions.Add($normalised) | Out-Null
    }
}

function Get-Actions {
    [CmdletBinding()]
    param(
        [string]$Category,
        [ValidateSet('Safe', 'Minor', 'Avoid')]
        [string]$Risk,
        [string]$IdPattern
    )

    $result = $script:Win10ToolsActions.ToArray()

    if ($Category)  { $result = @($result | Where-Object { $_.Category -eq $Category }) }
    if ($Risk)      { $result = @($result | Where-Object { $_.Risk     -eq $Risk }) }
    if ($IdPattern) { $result = @($result | Where-Object { $_.Id    -like $IdPattern }) }

    foreach ($r in $result) { $r }
}

function Get-Action {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $match = $script:Win10ToolsActions | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $match) {
        throw "No action registered with Id '$Id'"
    }
    $match
}

function Get-ActionCategories {
    $script:Win10ToolsActions | ForEach-Object { $_.Category } | Sort-Object -Unique
}

function Clear-Actions {
    $script:Win10ToolsActions.Clear()
    $script:Win10ToolsActionIds.Clear()
}

function Get-ActionCount {
    $script:Win10ToolsActions.Count
}

$script:Win10ToolsEnumerators = [System.Collections.Generic.List[string]]::new()

function Register-Enumerator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FunctionName
    )

    if (-not $script:Win10ToolsEnumerators.Contains($FunctionName)) {
        $script:Win10ToolsEnumerators.Add($FunctionName) | Out-Null
    }
}

function Get-EnumeratorList { @($script:Win10ToolsEnumerators.ToArray()) }

function Clear-Enumerators { $script:Win10ToolsEnumerators.Clear() }

function Invoke-AllEnumerators {
    [CmdletBinding()]
    param()

    foreach ($name in $script:Win10ToolsEnumerators) {
        $fn = Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue
        if (-not $fn) {
            Write-W10Log -Level 'Warn' -Message 'enumerator not found' -Data @{ name = $name }
            continue
        }
        try {
            & $fn
        } catch {
            Write-W10Log -Level 'Warn' -Message 'enumerator threw' -Data @{ name = $name; error = $_.Exception.Message }
        }
    }
}
