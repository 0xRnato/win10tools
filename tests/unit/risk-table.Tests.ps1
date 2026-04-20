BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:repoRoot 'src/core/risk-table.ps1')
}

Describe 'Get-AppxRisk' {
    Context 'AVOID patterns' {
        It 'classifies Xbox apps as Avoid' {
            Get-AppxRisk -Name 'Microsoft.XboxApp'           | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.XboxGameOverlay'   | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.Xbox.TCUI'         | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.GamingApp'         | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.GamingServices'    | Should -Be 'Avoid'
        }

        It 'classifies Edge as Avoid' {
            Get-AppxRisk -Name 'Microsoft.MicrosoftEdge.Stable'        | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.MicrosoftEdgeDevToolsClient' | Should -Be 'Avoid'
        }

        It 'classifies Store, Search, Photos, Cortana as Avoid' {
            Get-AppxRisk -Name 'Microsoft.WindowsStore'        | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.StorePurchaseApp'    | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.Windows.Search'      | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.Windows.Photos'      | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.Windows.Cortana'     | Should -Be 'Avoid'
        }

        It 'classifies OneDrive as Avoid' {
            Get-AppxRisk -Name 'Microsoft.MicrosoftOneDrive' | Should -Be 'Avoid'
        }

        It 'classifies framework runtimes as Avoid (do not remove)' {
            Get-AppxRisk -Name 'Microsoft.VCLibs.140.00'       | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.NET.Native.Runtime'  | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.UI.Xaml.2.7'         | Should -Be 'Avoid'
            Get-AppxRisk -Name 'Microsoft.DesktopAppInstaller' | Should -Be 'Avoid'
        }
    }

    Context 'MINOR patterns' {
        It 'classifies OneNote and Sticky Notes as Minor' {
            Get-AppxRisk -Name 'Microsoft.OneNote'              | Should -Be 'Minor'
            Get-AppxRisk -Name 'Microsoft.MicrosoftStickyNotes' | Should -Be 'Minor'
        }

        It 'classifies Groove, Movies, Phone Link, Paint as Minor' {
            Get-AppxRisk -Name 'Microsoft.ZuneMusic' | Should -Be 'Minor'
            Get-AppxRisk -Name 'Microsoft.ZuneVideo' | Should -Be 'Minor'
            Get-AppxRisk -Name 'Microsoft.YourPhone' | Should -Be 'Minor'
            Get-AppxRisk -Name 'Microsoft.MSPaint'   | Should -Be 'Minor'
        }
    }

    Context 'SAFE default' {
        It 'treats third-party stubs as Safe' {
            Get-AppxRisk -Name 'king.com.CandyCrushSaga'          | Should -Be 'Safe'
            Get-AppxRisk -Name 'Facebook.Facebook'                | Should -Be 'Safe'
            Get-AppxRisk -Name 'SpotifyAB.SpotifyMusic'           | Should -Be 'Safe'
            Get-AppxRisk -Name '5A894077.McAfeeSecurity'          | Should -Be 'Safe'
        }

        It 'treats Bing and other Microsoft bloat as Safe' {
            Get-AppxRisk -Name 'Microsoft.BingNews'            | Should -Be 'Safe'
            Get-AppxRisk -Name 'Microsoft.BingWeather'         | Should -Be 'Safe'
            Get-AppxRisk -Name 'Microsoft.GetHelp'             | Should -Be 'Safe'
            Get-AppxRisk -Name 'Microsoft.Microsoft3DViewer'   | Should -Be 'Safe'
            Get-AppxRisk -Name 'Microsoft.WindowsFeedbackHub'  | Should -Be 'Safe'
            Get-AppxRisk -Name 'Microsoft.MixedReality.Portal' | Should -Be 'Safe'
        }

        It 'treats completely unknown publishers as Safe' {
            Get-AppxRisk -Name 'SomeUnknownPublisher.WeirdApp' | Should -Be 'Safe'
        }
    }

    Context 'pattern lists' {
        It 'exposes non-empty AVOID list' {
            (Get-AvoidAppxPatterns).Count | Should -BeGreaterThan 10
        }

        It 'exposes non-empty MINOR list' {
            (Get-MinorAppxPatterns).Count | Should -BeGreaterThan 0
        }
    }
}
