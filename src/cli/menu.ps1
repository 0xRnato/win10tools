$script:W10CliDir = $PSScriptRoot
if (-not $script:W10CliDir) {
    $script:W10CliDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

. (Join-Path $script:W10CliDir 'menu-helpers.ps1')
$script:W10CliLastDryRunSignature = $null

$script:W10CliHelperDir = Join-Path (Split-Path -Parent $script:W10CliDir) 'ui'
if (Test-Path (Join-Path $script:W10CliHelperDir 'main-window-helpers.ps1')) {
    . (Join-Path $script:W10CliHelperDir 'main-window-helpers.ps1')
}

function Write-ColorLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [System.ConsoleColor]$Color = [System.ConsoleColor]::Gray
    )
    Write-Host $Text -ForegroundColor $Color
}

function Show-CliHelp {
    [CmdletBinding()]
    param()

    $lines = @(
        ''
        '=== win10tools CLI help ==='
        ''
        'Top menu commands:'
        '  <number>   enter the category at that position'
        '  D          dry-run every selected action (preview only)'
        '  R          run every selected action (with restore point + AVOID confirm)'
        '  C          clear all selections'
        '  ?          show this help'
        '  Q          quit'
        ''
        'Category screen commands:'
        '  <number>            toggle selection for that action (1-based)'
        '  <a>,<b>             toggle multiple (comma-separated)'
        '  <a>-<b>             toggle a range'
        '  A                   mark every Safe action in the category'
        '  N                   clear selections in the category'
        '  I <number>          show full details of an action'
        '  D                   dry-run every selected action'
        '  R                   run every selected action'
        '  B                   back to the top menu'
        '  ?                   show this help'
        '  Q                   quit'
        ''
        'Risk colors:  SAFE = green   MINOR = yellow   AVOID = red'
        'AVOID batches must be confirmed by typing CONFIRM literally.'
        ''
    )
    $lines | ForEach-Object { Write-Host $_ }
    Read-Host 'Press Enter to continue' | Out-Null
}

function Read-AvoidConfirmCli {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Rows
    )

    Write-Host ''
    Write-ColorLine -Text 'WARNING: selected actions include AVOID items:' -Color Red
    foreach ($row in $Rows) {
        Write-ColorLine -Text ("  - [" + $row.Category + "] " + $row.Name) -Color Red
    }
    Write-Host 'These historically cause random bugs. Type CONFIRM to proceed, anything else to cancel.'
    $answer = Read-Host 'Confirm'
    $answer -ceq 'CONFIRM'
}

function Show-TopMenu {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RowsByCategory
    )

    Format-CategoryHeader -RowsByCategory $RowsByCategory | ForEach-Object { Write-Host $_ }

    foreach ($line in Format-CategoryList -RowsByCategory $RowsByCategory) {
        Write-Host $line.Display
    }

    Write-Host ''
    Write-Host '  [D] Dry Run selected   [R] Run selected   [C] Clear all   [?] Help   [Q] Quit'
    Write-Host ''
    Read-Host 'Pick category number or command'
}

function Show-CategoryScreen {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CategoryName,

        [Parameter(Mandatory)]
        [pscustomobject[]]$Rows
    )

    $loop = $true
    while ($loop) {
        Write-Host ''
        Write-ColorLine -Text "=== $CategoryName ===" -Color Cyan
        Write-Host ''

        for ($i = 1; $i -le $Rows.Count; $i++) {
            $line = Format-ActionListLine -Index $i -Row $Rows[$i - 1]
            Write-ColorLine -Text $line.Display -Color $line.Color
        }

        Write-Host ''
        Write-Host '  [#,#-#] toggle indices   [A] toggle all Safe   [N] none   [B] back'
        Write-Host '  [I #]  info on action    [D] Dry Run selected   [R] Run selected'
        Write-Host '  [?]    help              [Q] quit'
        Write-Host ''
        $userInput = Read-Host 'Pick'
        if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

        $cmd = $userInput.Trim().ToUpper()
        switch -Regex ($cmd) {
            '^B$' { $loop = $false; break }
            '^Q$' { return 'QUIT' }
            '^\?$' { Show-CliHelp; break }
            '^A$' {
                Set-RowsSelection -Rows $Rows -Selected $true -Filter 'Safe'
                break
            }
            '^N$' {
                Set-RowsSelection -Rows $Rows -Selected $false
                break
            }
            '^D$' { return 'DRY' }
            '^R$' { return 'RUN' }
            '^I\s+(\d+)$' {
                $idx = [int]$matches[1]
                if ($idx -ge 1 -and $idx -le $Rows.Count) {
                    $action = $Rows[$idx - 1].ActionRef
                    Write-Host ''
                    Write-ColorLine -Text ("Id:          " + $action.Id) -Color White
                    Write-ColorLine -Text ("Name:        " + $action.Name) -Color White
                    Write-ColorLine -Text ("Risk:        " + $action.Risk) -Color (Get-RiskConsoleColor -Risk $action.Risk)
                    Write-ColorLine -Text ("Destructive: " + $action.Destructive) -Color Gray
                    Write-ColorLine -Text ("NeedsReboot: " + $action.NeedsReboot) -Color Gray
                    Write-ColorLine -Text ("NeedsAdmin:  " + $action.NeedsAdmin) -Color Gray
                    Write-ColorLine -Text ("Description: " + $action.Description) -Color Gray
                    Write-ColorLine -Text ("DryRun:      " + (Get-ActionDryRun -Action $action)) -Color DarkGray
                    Write-Host ''
                    Read-Host 'Press Enter to continue'
                }
                break
            }
            default {
                $indices = ConvertFrom-SelectionInput -SelectionText $userInput
                if ($indices.Count -eq 0) {
                    Write-ColorLine -Text 'Unrecognised input.' -Color DarkYellow
                    continue
                }
                Switch-RowSelection -Rows $Rows -Indices $indices
            }
        }
    }

    return 'BACK'
}

function Invoke-CliDryRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RowsByCategory
    )

    $selected = @(Get-SelectedRows -RowsByCategory $RowsByCategory)
    if ($selected.Count -eq 0) {
        Write-ColorLine -Text 'Nothing selected.' -Color DarkYellow
        return
    }
    $report = Format-DryRunReport -SelectedRows $selected
    $script:W10CliLastDryRunSignature = Get-SelectionSignature -Rows $selected
    Write-Host ''
    Write-Host $report
    Write-Host ''
    Read-Host 'Press Enter to continue'
}

function Invoke-CliRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RowsByCategory
    )

    $selected = @(Get-SelectedRows -RowsByCategory $RowsByCategory)
    if ($selected.Count -eq 0) {
        Write-ColorLine -Text 'Nothing selected.' -Color DarkYellow
        return
    }

    $currentSignature = Get-SelectionSignature -Rows $selected
    if ((Test-DryRunRequired -SelectedRows $selected) -and $script:W10CliLastDryRunSignature -ne $currentSignature) {
        Write-ColorLine -Text 'Dry Run required. Preview the current selection before running it.' -Color DarkYellow
        Read-Host 'Press Enter to continue'
        return
    }

    $avoidRows = @($selected | Where-Object { $_.Risk -eq 'Avoid' })
    if ($avoidRows.Count -gt 0) {
        if (-not (Read-AvoidConfirmCli -Rows $avoidRows)) {
            Write-ColorLine -Text 'Cancelled at AVOID confirmation.' -Color DarkYellow
            return
        }
    }

    Write-ColorLine -Text "Running $($selected.Count) actions..." -Color Cyan
    $actions = @($selected | ForEach-Object { $_.ActionRef })
    $batch = Invoke-ActionBatch -Actions $actions
    Write-Host ''
    Write-Host (Format-RunReport -BatchResult $batch)
    Write-Host ''
    Read-Host 'Press Enter to continue'
}

function Show-CliMenu {
    [CmdletBinding()]
    param()

    $categories = Get-ActionCategories
    if (-not $categories -or $categories.Count -eq 0) {
        Write-ColorLine -Text 'No actions registered. Did enumerators fail?' -Color Red
        return
    }

    $rowsByCategory = @{}
    foreach ($cat in $categories) {
        $rowsByCategory[$cat] = @(Get-Actions -Category $cat | ConvertTo-ActionRow)
    }

    $running = $true
    while ($running) {
        $userInput = Show-TopMenu -RowsByCategory $rowsByCategory
        if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

        $cmd = $userInput.Trim().ToUpper()
        switch -Regex ($cmd) {
            '^Q$' { $running = $false; break }
            '^\?$' { Show-CliHelp; break }
            '^D$' { Invoke-CliDryRun -RowsByCategory $rowsByCategory; break }
            '^R$' { Invoke-CliRun    -RowsByCategory $rowsByCategory; break }
            '^C$' {
                foreach ($key in $rowsByCategory.Keys) {
                    Set-RowsSelection -Rows $rowsByCategory[$key] -Selected $false
                }
                break
            }
            '^\d+$' {
                $idx = [int]$cmd
                $sorted = @($rowsByCategory.Keys | Sort-Object)
                if ($idx -lt 1 -or $idx -gt $sorted.Count) {
                    Write-ColorLine -Text 'Invalid category number.' -Color DarkYellow
                    continue
                }
                $picked = $sorted[$idx - 1]
                $result = Show-CategoryScreen -CategoryName $picked -Rows $rowsByCategory[$picked]
                switch ($result) {
                    'QUIT' { $running = $false }
                    'DRY'  { Invoke-CliDryRun -RowsByCategory $rowsByCategory }
                    'RUN'  { Invoke-CliRun    -RowsByCategory $rowsByCategory }
                }
            }
            default {
                Write-ColorLine -Text 'Unrecognised command.' -Color DarkYellow
            }
        }
    }

    Write-Host 'bye.'
}
