# Functions/Install-Certificate-Refactored.ps1
<#
    .SYNOPSIS
        Certificate installation with deployment options,
        robust error handling, and post-installation features.
    .DESCRIPTION
        Provides an interface for installing Let's Encrypt certificates
        to various targets including certificate stores, PEM files, and PFX exports.
        Includes options, testing, monitoring, and reporting capabilities.

        This is the refactored version that uses modular components.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to install. If not provided, user will select from available certificates.
    .PARAMETER Force
        Forces installation even if certificate already exists.
    .EXAMPLE
        Install-Certificate
        Install-Certificate -PACertificate $cert -Force
#>
function Install-Certificate
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [object]$PACertificate,
        [Parameter()]
        [switch]$Force
    )

    # Import certificate installation module
    $modulePath = Join-Path $PSScriptRoot "CertificateInstallation"
    if (Test-Path (Join-Path $modulePath "CertificateInstallation.psm1"))
    {
        Import-Module $modulePath -Force -Verbose:$VerbosePreference
    } else
    {
        Write-Error "Certificate Installation module not found at: $modulePath"
        return
    }

    # Initialize required services
    Initialize-ACMEServer
    $settings = Get-ScriptSettings

    # If no certificate provided, let user select one
    if ($null -eq $PACertificate)
    {
        $PACertificate = Select-CertificateForInstallation -Force:$Force
        if ($null -eq $PACertificate)
        {
            return
        }
    }

    # Confirm the certificate installation operation
    if (-not $PSCmdlet.ShouldProcess("Certificate Installation", "Install certificate for $($PACertificate.Subject)"))
    {
        return
    }

    # Display certificate information
    Show-CertificateInformation -PACertificate $PACertificate

    # Main installation menu loop
    $installed = $false
    while (-not $installed)
    {
        Write-Host -Object "`n" + "-"*70 -ForegroundColor Gray
        Write-Warning -Message "INSTALLATION OPTIONS"
        Write-Host -Object "-"*70 -ForegroundColor Gray
        Write-Host -Object "1) Install to Management Server (Windows Certificate Store)"
        Write-Host -Object "2) Install to Recording Server (PEM Files)"
        Write-Host -Object "3) Export as PFX File"
        Write-Host -Object "4) Export Multiple Formats"
        Write-Host -Object "5) Installation Options"
        Write-Host -Object "0) Back to main menu"

        $installChoice = Get-ValidatedInput -Prompt "`nSelect installation method (0-5)" -ValidOptions (0..5)

        switch ($installChoice)
        {
            0
            {
                return
            }
            1
            {
                # Management Server Installation
                if ($PSCmdlet.ShouldProcess("Certificate Store", "Install certificate for $($PACertificate.Subject)"))
                {
                    $result = Install-CertificateToStore -PACertificate $PACertificate -Settings $settings
                    if ($result)
                    {
                        $installed = $true
                    }
                }
            }
            2
            {
                # Recording Server Installation
                if ($PSCmdlet.ShouldProcess("PEM Files", "Install certificate for $($PACertificate.Subject)"))
                {
                    $result = Install-CertificateToPEM -PACertificate $PACertificate
                    if ($result)
                    {
                        $installed = $true
                    }
                }
            }
            3
            {
                # PFX Export
                if ($PSCmdlet.ShouldProcess("PFX File", "Export certificate for $($PACertificate.Subject)"))
                {
                    $result = Export-CertificateToPFX -PACertificate $PACertificate -Settings $settings -Force:$Force
                    if ($result)
                    {
                        $installed = $true
                    }
                }
            }
            4
            {
                # Multiple Format Export
                if ($PSCmdlet.ShouldProcess("Multiple Formats", "Export certificate for $($PACertificate.Subject)"))
                {
                    $result = Export-CertificateMultipleFormats -PACertificate $PACertificate
                    if ($result)
                    {
                        $installed = $true
                    }
                }
            }
            5
            {
                # Installation Options
                if ($PSCmdlet.ShouldProcess("Installation Options", "Configure installation options for $($PACertificate.Subject)"))
                {
                    $result = Show-InstallationOptionsMenu -PACertificate $PACertificate -Settings $settings -Force:$Force
                    if ($result)
                    {
                        $installed = $true
                    }
                }
            }
        }
    }

    # Post-installation actions and verification
    if ($installed)
    {
        Show-PostInstallationMenu -PACertificate $PACertificate
    }
}
