# Functions/CertificateInstallation/Show-CertificateInformation.ps1
<#
    .SYNOPSIS
        Displays detailed certificate information before installation
    .DESCRIPTION
        Shows certificate details including subject, issuer, validity period,
        and expiry warnings to help users make informed installation decisions.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to display information for
    .EXAMPLE
        Show-CertificateInformation -PACertificate $cert
#>
function Show-CertificateInformation
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    # Display certificate information
    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Write-Host -Object "CERTIFICATE INSTALLATION" -ForegroundColor Cyan
    Write-Host -Object "="*70 -ForegroundColor Cyan
    Write-Host -Object "Selected Certificate: $($PACertificate.MainDomain)" -ForegroundColor White

    if ($PACertificate.Certificate)
    {
        Write-Warning -Message "`nCertificate Details:"
        Write-Host -Object "  Subject: $($PACertificate.Certificate.Subject)"
        Write-Host -Object "  Issuer: $($PACertificate.Certificate.Issuer)"
        Write-Host -Object "  Valid From: $($PACertificate.Certificate.NotBefore)"
        Write-Host -Object "  Valid Until: $($PACertificate.Certificate.NotAfter)"
        Write-Host -Object "  Thumbprint: $($PACertificate.Certificate.Thumbprint)"

        # Show expiry warning if needed
        $daysUntilExpiry = ($PACertificate.Certificate.NotAfter - (Get-Date)).Days
        if ($daysUntilExpiry -le 30)
        {
            Write-Warning -Message "  This certificate expires in $daysUntilExpiry days!"
        }
    }
}
