# Functions/CertificateInstallation/Select-CertificateForInstallation.ps1
<#
    .SYNOPSIS
        Interactive certificate selection for installation
    .DESCRIPTION
        Provides user interface for selecting certificates from available
        Let's Encrypt certificates for installation operations.
    .PARAMETER Force
        Forces selection even if certificate has issues
    .OUTPUTS
        Returns the selected PACertificate object or $null if cancelled
    .EXAMPLE
        $cert = Select-CertificateForInstallation
        $cert = Select-CertificateForInstallation -Force
#>
function Select-CertificateForInstallation
{
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$Force
    )

    Write-ProgressHelper -Activity "Certificate Installation" -Status "Loading available certificates..." -PercentComplete 10

    # Clear cache and get fresh certificate list
    Clear-CertificateCache
    $orders = Get-PAOrder

    if ($null -eq $orders -or $orders.Count -eq 0)
    {
        Write-Warning -Message "`nNo certificates available to install."
        Read-Host "`nPress Enter to return to the main menu"
        return $null
    }

    # Load certificates with error handling
    $certs = @()
    foreach ($order in $orders)
    {
        try
        {
            $cert = Get-CachedPACertificate -MainDomain $order.MainDomain
            if ($null -ne $cert)
            {
                $certs += $cert
            }
        } catch
        {
            Write-Warning -Message "Failed to load certificate for $($order.MainDomain): $_"
        }
    }

    if ($certs.Count -eq 0)
    {
        Write-Warning -Message "`nNo valid certificates available to install."
        Read-Host "`nPress Enter to return to the main menu"
        return $null
    }

    # Display certificate selection menu
    Write-Information -MessageData "`nSelect the certificate you want to install:" -InformationAction Continue
    for ($i = 0; $i -lt $certs.Count; $i++)
    {
        $cert = $certs[$i]
        $expiryInfo = ""

        if ($cert.Certificate)
        {
            $daysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
            $expiryInfo = " (expires in $daysUntilExpiry days)"

            if ($daysUntilExpiry -le 7)
            {
                Write-Warning -Message "$($i + 1)) $($cert.MainDomain)$expiryInfo"
            } else
            {
                Write-Information -MessageData "$($i + 1)) $($cert.MainDomain)$expiryInfo" -InformationAction Continue
            }
        } else
        {
            Write-Information -MessageData "$($i + 1)) $($cert.MainDomain)$expiryInfo" -InformationAction Continue
        }
    }

    Write-Information -MessageData "0) Back to main menu" -InformationAction Continue
    $selection = Get-ValidatedInput -Prompt "`nEnter your choice (0-$($certs.Count))" -ValidOptions (0..$certs.Count)

    if ($selection -eq 0)
    {
        return $null
    } else
    {
        return $certs[$selection - 1]
    }
}
