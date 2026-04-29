Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
Add-Type -AssemblyName PresentationCore     -ErrorAction SilentlyContinue
Add-Type -AssemblyName WindowsBase           -ErrorAction SilentlyContinue

$script:W10UiDir = $PSScriptRoot
if (-not $script:W10UiDir) {
    $script:W10UiDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

. (Join-Path $script:W10UiDir 'main-window-helpers.ps1')

function Read-UiXaml {
    [CmdletBinding()]
    [OutputType([System.Windows.Window])]
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )

    $path = Join-Path $script:W10UiDir $FileName
    $xaml = [System.IO.File]::ReadAllText($path)
    [xml]$doc = $xaml
    $reader = New-Object System.Xml.XmlNodeReader $doc
    [System.Windows.Markup.XamlReader]::Load($reader)
}

function Show-AvoidConfirmModal {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Rows,

        [System.Windows.Window]$Owner
    )

    $window = Read-UiXaml -FileName 'avoid-confirm.xaml'
    if ($Owner) { $window.Owner = $Owner }

    $list    = $window.FindName('AvoidListBox')
    $box     = $window.FindName('ConfirmBox')
    $confirm = $window.FindName('ConfirmButton')
    $cancel  = $window.FindName('CancelButton')

    foreach ($row in $Rows) {
        $null = $list.Items.Add("[$($row.Category)] $($row.Name)")
    }

    $script:AvoidConfirmed = $false

    $box.Add_TextChanged({
        $confirm.IsEnabled = ($box.Text -ceq 'CONFIRM')
    })

    $confirm.Add_Click({
        $script:AvoidConfirmed = $true
        $window.Close()
    })

    $cancel.Add_Click({
        $script:AvoidConfirmed = $false
        $window.Close()
    })

    $window.ShowDialog() | Out-Null
    [bool]$script:AvoidConfirmed
}

function New-CategoryTab {
    [CmdletBinding()]
    [OutputType([System.Windows.Controls.TabItem])]
    param(
        [Parameter(Mandatory)]
        [string]$CategoryName,

        [Parameter(Mandatory)]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [scriptblock]$OnSelectionChanged
    )

    $null = $OnSelectionChanged

    $tab = New-Object System.Windows.Controls.TabItem
    $tab.Header = "$CategoryName ($($Rows.Count))"

    $grid = New-Object System.Windows.Controls.DataGrid

    $checkboxCol = New-Object System.Windows.Controls.DataGridCheckBoxColumn
    $checkboxCol.Header = ''
    $checkboxCol.Binding = New-Object System.Windows.Data.Binding 'Selected'
    $checkboxCol.Binding.Mode = 'TwoWay'
    $checkboxCol.Binding.UpdateSourceTrigger = 'PropertyChanged'
    $checkboxCol.Width = [System.Windows.Controls.DataGridLength]::new(40)
    $grid.Columns.Add($checkboxCol) | Out-Null

    $riskCol = New-Object System.Windows.Controls.DataGridTemplateColumn
    $riskCol.Header = 'Risk'
    $riskCol.Width  = [System.Windows.Controls.DataGridLength]::new(70)
    $riskTemplateXaml = @'
<DataTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">
    <TextBlock Text="{Binding Risk}" FontWeight="SemiBold" TextAlignment="Center" Padding="4,2">
        <TextBlock.Style>
            <Style TargetType="TextBlock">
                <Setter Property="Foreground" Value="#7bd88f"/>
                <Style.Triggers>
                    <DataTrigger Binding="{Binding Risk}" Value="Minor">
                        <Setter Property="Foreground" Value="#e6d97e"/>
                    </DataTrigger>
                    <DataTrigger Binding="{Binding Risk}" Value="Avoid">
                        <Setter Property="Foreground" Value="#ff7b80"/>
                    </DataTrigger>
                </Style.Triggers>
            </Style>
        </TextBlock.Style>
    </TextBlock>
</DataTemplate>
'@
    $riskReader = New-Object System.Xml.XmlNodeReader ([xml]$riskTemplateXaml)
    $riskCol.CellTemplate = [System.Windows.Markup.XamlReader]::Load($riskReader)
    $grid.Columns.Add($riskCol) | Out-Null

    $nameCol = New-Object System.Windows.Controls.DataGridTextColumn
    $nameCol.Header = 'Name'
    $nameCol.Binding = New-Object System.Windows.Data.Binding 'Name'
    $nameCol.Width = [System.Windows.Controls.DataGridLength]::new(1, 'Star')
    $grid.Columns.Add($nameCol) | Out-Null

    $flagsCol = New-Object System.Windows.Controls.DataGridTextColumn
    $flagsCol.Header = 'Flags'
    $flagsCol.Binding = New-Object System.Windows.Data.Binding 'Flags'
    $flagsCol.Width = [System.Windows.Controls.DataGridLength]::new(200)
    $grid.Columns.Add($flagsCol) | Out-Null

    $descCol = New-Object System.Windows.Controls.DataGridTextColumn
    $descCol.Header = 'Description'
    $descCol.Binding = New-Object System.Windows.Data.Binding 'Description'
    $descCol.Width = [System.Windows.Controls.DataGridLength]::new(2, 'Star')
    $grid.Columns.Add($descCol) | Out-Null

    $rowStyle = New-Object System.Windows.Style([System.Windows.Controls.DataGridRow])
    $toolTipBinding = New-Object System.Windows.Data.Binding 'Description'
    $toolTipSetter  = New-Object System.Windows.Setter([System.Windows.Controls.DataGridRow]::ToolTipProperty, $toolTipBinding)
    $rowStyle.Setters.Add($toolTipSetter) | Out-Null
    $grid.RowStyle = $rowStyle

    $observable = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($row in $Rows) { $observable.Add($row) | Out-Null }
    $grid.ItemsSource = $observable

    $grid.Add_CellEditEnding({ $OnSelectionChanged.Invoke() })
    $grid.Add_CurrentCellChanged({ $OnSelectionChanged.Invoke() })

    $tab.Content = $grid
    $tab
}

function Show-MainWindow {
    [CmdletBinding()]
    param()

    $window = Read-UiXaml -FileName 'main-window.xaml'

    $categoryTabs    = $window.FindName('CategoryTabs')
    $adminBadge      = $window.FindName('AdminBadge')
    $sessionBadge    = $window.FindName('SessionBadge')
    $deletionCombo   = $window.FindName('DeletionModeCombo')
    $thresholdSlider = $window.FindName('ThresholdSlider')
    $thresholdLabel  = $window.FindName('ThresholdLabel')
    $selectionLabel  = $window.FindName('SelectionCountLabel')
    $avoidLabel      = $window.FindName('AvoidCountLabel')
    $dryRunButton    = $window.FindName('DryRunButton')
    $runButton       = $window.FindName('RunButton')
    $clearButton     = $window.FindName('ClearSelectionButton')
    $helpButton      = $window.FindName('HelpButton')
    $outputBox       = $window.FindName('OutputBox')

    if (Test-IsAdmin) {
        $adminBadge.Text = 'admin'
        $adminBadge.Foreground = [System.Windows.Media.Brushes]::LimeGreen
    }
    $sessionBadge.Text = "session $(Get-W10SessionId)"

    $categories = Get-ActionCategories
    $rowsByCategory = @{}
    $script:W10GuiLastDryRunSignature = $null

    foreach ($cat in $categories) {
        $rows = @(Get-Actions -Category $cat | ConvertTo-ActionRow)
        $rowsByCategory[$cat] = $rows
        $tab = New-CategoryTab -CategoryName $cat -Rows $rows -OnSelectionChanged {
            $stats = Measure-RowSelection -RowsByCategory $rowsByCategory
            $selectionLabel.Text = "$($stats.Total) selected"
            if ($stats.Avoid -gt 0) {
                $avoidLabel.Text = "$($stats.Avoid) AVOID"
            } else {
                $avoidLabel.Text = ''
            }
        }
        $categoryTabs.Items.Add($tab) | Out-Null
    }

    $thresholdSlider.Add_ValueChanged({
        $days = [int]$thresholdSlider.Value
        $thresholdLabel.Text = "$days days"
        Update-DeepCleanupThreshold -ThresholdDays $days
    })

    $deletionCombo.Add_SelectionChanged({
        $mode = switch ($deletionCombo.SelectedIndex) {
            1 { 'Direct' }
            default { 'RecycleBin' }
        }
        Set-DeletionMode -Mode $mode
    })

    $dryRunButton.Add_Click({
        $selected = @(Get-SelectedRows -RowsByCategory $rowsByCategory)
        if ($selected.Count -eq 0) {
            $outputBox.Text = 'Nothing selected. Tick one or more rows first.'
            return
        }
        $script:W10GuiLastDryRunSignature = Get-SelectionSignature -Rows $selected
        $outputBox.Text = Format-DryRunReport -SelectedRows $selected
    })

    $runButton.Add_Click({
        $selected = @(Get-SelectedRows -RowsByCategory $rowsByCategory)
        if ($selected.Count -eq 0) {
            $outputBox.Text = 'Nothing selected.'
            return
        }

        $currentSignature = Get-SelectionSignature -Rows $selected
        if ((Test-DryRunRequired -SelectedRows $selected) -and $script:W10GuiLastDryRunSignature -ne $currentSignature) {
            $outputBox.Text = 'Dry Run required. Preview the current selection before running it.'
            return
        }

        $avoidRows = @($selected | Where-Object { $_.Risk -eq 'Avoid' })
        if ($avoidRows.Count -gt 0) {
            $confirmed = Show-AvoidConfirmModal -Rows $avoidRows -Owner $window
            if (-not $confirmed) {
                $outputBox.Text = 'Run cancelled at AVOID confirmation.'
                return
            }
        }

        $actions = @($selected | ForEach-Object { $_.ActionRef })
        $outputBox.Text = "Running $($actions.Count) actions..."
        $batch = Invoke-ActionBatch -Actions $actions
        $outputBox.Text = Format-RunReport -BatchResult $batch
    })

    $helpButton.Add_Click({
        $lines = @(
            'win10tools - quick help'
            ''
            '1. Tabs group actions by category. Hover any row for its description.'
            '2. Tick the actions you want. Nothing runs unless you tick it.'
            '3. Dry Run previews exactly what will happen. Run executes.'
            '4. Risk colors: SAFE = green, MINOR = yellow, AVOID = red.'
            '5. Any AVOID action needs double-confirm (type CONFIRM in the modal).'
            '6. Destructive batches auto-create a restore point first.'
            '7. Deletion mode controls where files go (Recycle Bin or direct).'
            '8. Stale threshold slider affects Deep Cleanup scans.'
            ''
            'Logs: %LOCALAPPDATA%\win10tools\logs\YYYY-MM-DD.log'
            'Quarantine: %LOCALAPPDATA%\win10tools\quarantine\'
        )
        $outputBox.Text = ($lines -join [Environment]::NewLine)
    })

    $clearButton.Add_Click({
        foreach ($key in $rowsByCategory.Keys) {
            foreach ($row in $rowsByCategory[$key]) {
                $row.Selected = $false
            }
        }
        $selectionLabel.Text = '0 selected'
        $avoidLabel.Text = ''
        foreach ($tab in $categoryTabs.Items) {
            $tab.Content.Items.Refresh()
        }
    })

    $window.ShowDialog() | Out-Null
}
