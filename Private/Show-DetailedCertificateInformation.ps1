# Functions/CertificateInstallation/Show-DetailedCertificateInformation.ps1
<#
    .SYNOPSIS
        Shows comprehensive certificate information
    .DESCRIPTION
        Displays detailed certificate information including basic details,
        validity period, cryptographic information, extensions, and file locations.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to display information for
    .EXAMPLE
        Show-DetailedCertificateInformation -PACertificate $cert
#>
function Show-DetailedCertificateInformation
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Write-Host -Object "DETAILED CERTIFICATE INFORMATION" -ForegroundColor Cyan
    Write-Host -Object "="*70 -ForegroundColor Cyan

    Write-Warning -Message "`nBasic Information:"
    Write-Host -Object "Subject: $($PACertificate.Certificate.Subject)"
    Write-Host -Object "Issuer: $($PACertificate.Certificate.Issuer)"
    Write-Host -Object "Serial Number: $($PACertificate.Certificate.SerialNumber)"
    Write-Host -Object "Thumbprint: $($PACertificate.Certificate.Thumbprint)"
    Write-Host -Object "Version: $($PACertificate.Certificate.Version)"

    Write-Warning -Message "`nValidity Period:"
    Write-Host -Object "Valid From: $($PACertificate.Certificate.NotBefore)"
    Write-Host -Object "Valid Until: $($PACertificate.Certificate.NotAfter)"

    $daysUntilExpiry = ($PACertificate.Certificate.NotAfter - (Get-Date)).Days
    $expiryColor = if ($daysUntilExpiry -gt 30) { "Green" } elseif ($daysUntilExpiry -gt 7) { "Yellow" } else { "Red" }
    Write-Host -Object "Days Until Expiry: $daysUntilExpiry" -ForegroundColor $expiryColor

    Write-Warning -Message "`nCryptographic Information:"
    Write-Host -Object "Public Key Algorithm: $($PACertificate.Certificate.PublicKey.Oid.FriendlyName)"
    Write-Host -Object "Key Size: $($PACertificate.Certificate.PublicKey.Key.KeySize) bits"
    Write-Host -Object "Signature Algorithm: $($PACertificate.Certificate.SignatureAlgorithm.FriendlyName)"
    Write-Host -Object "Has Private Key: $($PACertificate.Certificate.HasPrivateKey)"

    if ($PACertificate.Certificate.Extensions)
    {
        Write-Warning -Message "`nCertificate Extensions:"

        # Subject Alternative Names
        $sanExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.17" }
        if ($sanExt)
        {
            $sanDetails = $sanExt.Format($false)
            Write-Host -Object "Subject Alternative Names: $sanDetails"
        }

        # Key Usage
        $keyUsageExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.15" }
        if ($keyUsageExt)
        {
            $keyUsageDetails = $keyUsageExt.Format($false)
            Write-Host -Object "Key Usage: $keyUsageDetails"
        }

        # Extended Key Usage
        $extKeyUsageExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.37" }
        if ($extKeyUsageExt)
        {
            $extKeyUsageDetails = $extKeyUsageExt.Format($false)
            Write-Host -Object "Extended Key Usage: $extKeyUsageDetails"
        }
    }

    Write-Warning -Message "`nFile Locations:"
    if ($PACertificate.CertFile) { Write-Host -Object "Certificate File: $($PACertificate.CertFile)" }
    if ($PACertificate.KeyFile) { Write-Host -Object "Private Key File: $($PACertificate.KeyFile)" }
    if ($PACertificate.ChainFile) { Write-Host -Object "Chain File: $($PACertificate.ChainFile)" }
    if ($PACertificate.FullChainFile) { Write-Host -Object "Full Chain File: $($PACertificate.FullChainFile)" }
    if ($PACertificate.PfxFile) { Write-Host -Object "PFX File: $($PACertificate.PfxFile)" }
}
