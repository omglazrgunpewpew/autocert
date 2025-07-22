# Functions/CertificateInstallation/Show-PostInstallationMenu.ps1
<#
    .SYNOPSIS
        Shows post-installation options and actions
    .DESCRIPTION
        Provides post-installation menu with options for testing, reporting,
        monitoring configuration, and application binding setup.
    .PARAMETER PACertificate
        The Posh-ACME certificate object that was installed
    .EXAMPLE
        Show-PostInstallationMenu -PACertificate $cert
#>
function Show-PostInstallationMenu
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    Write-Information -MessageData "`n" + "="*70 -InformationAction Continue
    Write-Information -MessageData "INSTALLATION COMPLETED!" -InformationAction Continue
    Write-Information -MessageData "="*70 -InformationAction Continue

    # Post-installation menu
    Write-Host -Object "`nPost-Installation Options:" -ForegroundColor Yellow
    Write-Host -Object "1) Test certificate installation"
    Write-Host -Object "2) View detailed certificate information"
    Write-Host -Object "3) Configure monitoring and alerts"
    Write-Host -Object "4) Generate installation report"
    Write-Host -Object "5) Configure application bindings"
    Write-Host -Object "6) Verify certificate chain"
    Write-Host -Object "0) Continue to main menu"

    $postChoice = Get-ValidatedInput -Prompt "`nSelect option (0-6)" -ValidOptions (0..6)

    switch ($postChoice)
    {
        1
        {
            # Certificate testing
            $testResults = Test-CertificateInstallation -PACertificate $PACertificate
            Read-Host "`nPress Enter to continue"
        }
        2
        {
            # Certificate information display
            Show-DetailedCertificateInformation -PACertificate $PACertificate
            Read-Host "`nPress Enter to continue"
        }
        3
        {
            # Configure monitoring and alerts
            Set-CertificateMonitoring -PACertificate $PACertificate
            Read-Host "`nPress Enter to continue"
        }
        4
        {
            # Generate installation report
            New-InstallationReport -PACertificate $PACertificate
            Read-Host "`nPress Enter to continue"
        }
        5
        {
            # Configure application bindings
            Set-ApplicationBinding -PACertificate $PACertificate
            Read-Host "`nPress Enter to continue"
        }
        6
        {
            # Verify certificate chain
            Test-CertificateChain -PACertificate $PACertificate
            Read-Host "`nPress Enter to continue"
        }
        0
        {
            return
        }
    }
}
