$script:AvoidAppxPatterns = @(
    'Microsoft.XboxApp',
    'Microsoft.Xbox*',
    'Microsoft.GamingApp',
    'Microsoft.GamingServices',
    'Microsoft.MicrosoftEdge*',
    'Microsoft.Edge*',
    'Microsoft.WebMediaExtensions',
    'Microsoft.WindowsStore',
    'Microsoft.StorePurchaseApp',
    'Microsoft.Services.Store.Engagement',
    'Microsoft.549981C3F5F10',
    'Microsoft.Windows.Cortana*',
    'Microsoft.Search*',
    'Microsoft.Windows.Search*',
    'Microsoft.OneDriveSync',
    'Microsoft.MicrosoftOneDrive',
    'Microsoft.Windows.Photos',
    'Microsoft.Photos*',
    'Microsoft.Windows.SecHealthUI',
    'Microsoft.SecHealthUI',
    'Microsoft.WindowsCalculator',
    'Microsoft.WindowsCamera',
    'Microsoft.WindowsAlarms',
    'Microsoft.WindowsNotepad',
    'Microsoft.WindowsTerminal',
    'Microsoft.VCLibs.*',
    'Microsoft.NET.*',
    'Microsoft.UI.*',
    'Microsoft.DesktopAppInstaller',
    'Microsoft.WinAppRuntime.*',
    'Microsoft.WindowsAppRuntime.*',
    'Microsoft.AAD.*',
    'Microsoft.AccountsControl',
    'Microsoft.AsyncTextService',
    'Microsoft.BioEnrollment',
    'Microsoft.CredDialogHost',
    'Microsoft.ECApp',
    'Microsoft.LockApp',
    'Microsoft.Windows.*PeopleExperienceHost',
    'Microsoft.Windows.ShellExperienceHost',
    'Microsoft.Windows.StartMenuExperienceHost',
    'Microsoft.Windows.CloudExperienceHost',
    'Microsoft.Windows.ContentDeliveryManager',
    'Microsoft.Windows.NarratorQuickStart',
    'Microsoft.Windows.ParentalControls',
    'Microsoft.Windows.PinningConfirmationDialog',
    'Microsoft.Windows.PrintQueueActionCenter',
    'Microsoft.Windows.XGpuEjectDialog',
    'Microsoft.Windows.CapturePicker',
    'Microsoft.Windows.CallingShellApp',
    'Microsoft.Windows.AssignedAccessLockApp',
    'Microsoft.Win32WebViewHost',
    'windows.immersivecontrolpanel',
    'NcsiUwpApp'
)

$script:MinorAppxPatterns = @(
    'Microsoft.OneNote',
    'Microsoft.MicrosoftStickyNotes',
    'Microsoft.MSPaint',
    'Microsoft.Paint',
    'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo',
    'Microsoft.YourPhone',
    'MicrosoftCorporationII.MicrosoftFamily',
    'MicrosoftCorporationII.QuickAssist',
    'Microsoft.WindowsSoundRecorder',
    'Microsoft.ScreenSketch',
    'Microsoft.WindowsMaps'
)

function Get-AppxRisk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    foreach ($pattern in $script:AvoidAppxPatterns) {
        if ($Name -like $pattern) { return 'Avoid' }
    }

    foreach ($pattern in $script:MinorAppxPatterns) {
        if ($Name -like $pattern) { return 'Minor' }
    }

    return 'Safe'
}

function Get-AvoidAppxPatterns { $script:AvoidAppxPatterns }
function Get-MinorAppxPatterns { $script:MinorAppxPatterns }
