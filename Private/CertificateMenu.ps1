# Certificate Management Menu System
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 8, 2025

<#
.SYNOPSIS
    Certificate management menu for AutoCert system
.DESCRIPTION
    Provides a menu system for managing certificates including viewing,
    managing individual certificates, bulk renewal, exporting, revoking, and deletion.
.NOTES
    Requires the core certificate functions to be available
#>

# Helper Functions
function Show-MenuHeader
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [int]$Width = 60
    )
    Clear-Host
    Write-Information -MessageData "`n$("="*$Width)" -InformationAction Continue
    Write-Information -MessageData "    $Title" -InformationAction Continue
    Write-Information -MessageData "$("="*$Width)" -InformationAction Continue
}

function Wait-UserInput
{
    [CmdletBinding()]
    param(
        [string]$Message = "`nPress Enter to continue"
    )
    Read-Host $Message
}

function Export-CertificateFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Certificate,
        [Parameter(Mandatory)]
        [string]$ExportPath,
        [Parameter(Mandatory)]
        [string]$DomainName
    )

    $domainPath = Join-Path $ExportPath $DomainName
    New-Item -ItemType Directory -Path $domainPath -Force | Out-Null

    $fileMap = @{
        'CertFile'      = 'cert.pem'
        'KeyFile'       = 'key.pem'
        'ChainFile'     = 'chain.pem'
        'FullChainFile' = 'fullchain.pem'
        'PfxFile'       = 'cert.pfx'
    }

    foreach ($sourceProperty in $fileMap.Keys)
    {
        $sourcePath = $Certificate.$sourceProperty
        if ($sourcePath -and (Test-Path $sourcePath))
        {
            $destinationFile = $fileMap[$sourceProperty]
            Copy-Item -Path $sourcePath -Destination (Join-Path $domainPath $destinationFile)
        }
    }

    return $domainPath
}

function Show-CertificateManagementMenu
{
    [CmdletBinding()]
    param()

    while ($true)
    {
        Clear-Host
        Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
        Write-Information -MessageData "    CERTIFICATE MANAGEMENT" -InformationAction Continue
        Write-Information -MessageData "$("="*70)" -InformationAction Continue

        # Show current certificate summary
        try
        {
            $orders = Get-PAOrder
            if ($orders)
            {
                $config = Get-RenewalConfig
                $renewalStatus = Get-CertificateRenewalStatus -Config $config
                $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
                $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count
                $total = $orders.Count

                Write-Information -MessageData "Certificate Summary:" -InformationAction Continue
                Write-Information -MessageData "  Total certificates: $total" -InformationAction Continue
                if ($needsRenewal -gt 0)
                {
                    Write-Warning -Message "  Certificates needing renewal: $needsRenewal"
                }
                if ($expiringSoon -gt 0)
                {
                    Write-Error -Message "  Expiring within 7 days: $expiringSoon"
                }
                Write-Information -MessageData "" -InformationAction Continue
            } else
            {
                Write-Warning -Message "No certificates found."
                Write-Information -MessageData "" -InformationAction Continue
            }
        } catch
        {
            Write-Error -Message "Could not retrieve certificate summary."
            Write-Information -MessageData "" -InformationAction Continue
        }

        Write-Information -MessageData "Available Actions:" -InformationAction Continue
        Write-Information -MessageData "1. View all certificates (detailed list)" -InformationAction Continue
        Write-Information -MessageData "2. Manage individual certificate" -InformationAction Continue
        Write-Warning -Message "3. Bulk renewal check"
        Write-Information -MessageData "4. Export certificates" -InformationAction Continue
        Write-Error -Message "5. Revoke a certificate"
        Write-Error -Message "6. Delete a certificate"
        Write-Information -MessageData "0. Return to Main Menu" -InformationAction Continue
        Write-Information -MessageData "`n$("="*70)" -InformationAction Continue

        $choice = Read-Host "Enter your choice"

        switch ($choice)
        {
            '1'
            {
                # View all certificates in detailed list format
                Show-MenuHeader -Title "ALL CERTIFICATES - DETAILED VIEW"

                Get-ExistingCertificates
                Wait-UserInput
            }
            '2'
            {
                # Manage individual certificate - show selection menu
                Show-MenuHeader -Title "SELECT CERTIFICATE TO MANAGE"

                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder)
                {
                    Invoke-SingleCertificateManagement -CertificateOrder $selectedOrder
                } else
                {
                    Write-Warning -Message "No certificate selected."
                    Wait-UserInput -Message "Press Enter to continue"
                }
            }
            '3'
            {
                # Bulk renewal check
                Show-MenuHeader -Title "BULK RENEWAL CHECK"

                try
                {
                    $orders = Get-PAOrder
                    if ($orders)
                    {
                        $config = Get-RenewalConfig
                        $renewalStatus = Get-CertificateRenewalStatus -Config $config

                        Write-Information -MessageData "Renewal Status Summary:" -InformationAction Continue
                        foreach ($status in $renewalStatus)
                        {
                            $statusText = if ($status.NeedsRenewal) { "NEEDS RENEWAL" } else { "OK" }
                            Write-Information -MessageData "  $($status.Domain): $statusText (expires in $($status.DaysUntilExpiry) days)" -InformationAction Continue
                        }

                        $needsRenewal = $renewalStatus | Where-Object { $_.NeedsRenewal }
                        if ($needsRenewal)
                        {
                            Write-Warning -Message "`nWould you like to renew all certificates that need renewal? (y/n)"
                            $renewChoice = Read-Host
                            if ($renewChoice -eq 'y' -or $renewChoice -eq 'Y')
                            {
                                Write-Information -MessageData "Starting bulk renewal process..." -InformationAction Continue
                                Update-AllCertificates -Force
                            }
                        } else
                        {
                            Write-Information -MessageData "`nAll certificates are up to date!" -InformationAction Continue
                        }
                    } else
                    {
                        Write-Warning -Message "No certificates found."
                    }
                } catch
                {
                    Write-Error -Message "Failed to check renewal status: $($_.Exception.Message)"
                }

                Wait-UserInput
            }
            '4'
            {
                # Export certificates
                Invoke-CertificateExportMenu
            }
            '5'
            {
                # Revoke a certificate
                Invoke-CertificateRevocationMenu
            }
            '6'
            {
                # Delete a certificate
                Invoke-CertificateDeletionMenu
            }
            '0'
            {
                return
            }
            default
            {
                Write-Warning -Message "Invalid option. Please try again."
                Wait-UserInput -Message "Press Enter to continue"
            }
        }
    }
}

# Extracted from the main certificate menu to improve modularity
function Invoke-CertificateExportMenu
{
    [CmdletBinding()]
    param()

    Show-MenuHeader -Title "EXPORT CERTIFICATES"

    try
    {
        $orders = Get-PAOrder
        if ($orders)
        {
            Write-Information -MessageData "Available certificates:" -InformationAction Continue
            for ($i = 0; $i -lt $orders.Count; $i++)
            {
                Write-Information -MessageData "  $($i + 1). $($orders[$i].MainDomain)" -InformationAction Continue
            }
            Write-Warning -Message "  A. All certificates"
            Write-Error -Message "  0. Cancel"

            $exportChoice = Read-Host "`nEnter your choice"

            if ($exportChoice -eq 'A' -or $exportChoice -eq 'a')
            {
                # Export all certificates
                $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                if ([string]::IsNullOrWhiteSpace($exportPath))
                {
                    $exportPath = $PWD.Path
                }

                Write-Information -MessageData "Exporting all certificates to: $exportPath" -InformationAction Continue
                foreach ($order in $orders)
                {
                    try
                    {
                        $cert = Get-PACertificate -MainDomain $order.MainDomain
                        $domainPath = Export-CertificateFile -Certificate $cert -ExportPath $exportPath -DomainName $order.MainDomain
                        Write-Information -MessageData "  Exported: $($order.MainDomain)" -InformationAction Continue
                    } catch
                    {
                        Write-Error -Message "  Failed to export: $($order.MainDomain) - $($_.Exception.Message)"
                    }
                }
                Write-Information -MessageData "Export completed." -InformationAction Continue
            } elseif ($exportChoice -ge 1 -and $exportChoice -le $orders.Count)
            {
                # Export specific certificate
                $selectedOrder = $orders[$exportChoice - 1]
                $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                if ([string]::IsNullOrWhiteSpace($exportPath))
                {
                    $exportPath = $PWD.Path
                }

                try
                {
                    $cert = Get-PACertificate -MainDomain $selectedOrder.MainDomain
                    $domainPath = Export-CertificateFile -Certificate $cert -ExportPath $exportPath -DomainName $selectedOrder.MainDomain
                    Write-Information -MessageData "Certificate exported to: $domainPath" -InformationAction Continue
                } catch
                {
                    Write-Error -Message "Failed to export certificate: $($_.Exception.Message)"
                }
            } elseif ($exportChoice -ne '0')
            {
                Write-Error -Message "Invalid choice."
            }
        } else
        {
            Write-Warning -Message "No certificates found to export."
        }
    } catch
    {
        Write-Error -Message "Export operation failed: $($_.Exception.Message)"
    }

    Wait-UserInput
}

# Extracted from the main certificate menu to improve modularity
function Invoke-CertificateRevocationMenu
{
    [CmdletBinding()]
    param()

    Show-MenuHeader -Title "REVOKE CERTIFICATE"

    Write-Error -Message "Warning: Certificate revocation is permanent and cannot be undone!"
    Write-Warning -Message "Revoked certificates will be immediately invalid for all uses."
    Write-Information -MessageData "" -InformationAction Continue

    $selectedOrder = Get-ExistingCertificates -ShowMenu
    if ($selectedOrder)
    {
        Write-Warning -Message "`nYou have selected: $($selectedOrder.MainDomain)"
        Write-Error -Message "Are you sure you want to revoke this certificate? (yes/no)"
        $confirmation = Read-Host

        if ($confirmation -eq 'yes')
        {
            try
            {
                # Note: Revoke-Certificate doesn't accept MainDomain parameter
                # It will show a selection menu for the user
                Write-Information -MessageData "Launching certificate revocation process..." -InformationAction Continue
                Revoke-Certificate
                Write-Information -MessageData "Certificate revocation process completed." -InformationAction Continue
            } catch
            {
                Write-Error -Message "Failed to revoke certificate: $($_.Exception.Message)"
            }
        } else
        {
            Write-Warning -Message "Revocation cancelled."
        }
    } else
    {
        Write-Warning -Message "No certificate selected."
    }

    Wait-UserInput
}

# Extracted from the main certificate menu to improve modularity
function Invoke-CertificateDeletionMenu
{
    [CmdletBinding()]
    param()

    Show-MenuHeader -Title "DELETE CERTIFICATE"

    Write-Error -Message "Warning: This will permanently delete the certificate and all associated data!"
    Write-Warning -Message "The certificate will be removed from local storage and cannot be recovered."
    Write-Warning -Message "Consider revoking the certificate first if it's still valid."
    Write-Information -MessageData "" -InformationAction Continue

    $selectedOrder = Get-ExistingCertificates -ShowMenu
    if ($selectedOrder)
    {
        Write-Warning -Message "`nYou have selected: $($selectedOrder.MainDomain)"
        Write-Error -Message "Are you sure you want to delete this certificate? (yes/no)"
        $confirmation = Read-Host
        if ($confirmation -eq 'yes')
        {
            try
            {
                # Note: Remove-Certificate doesn't accept MainDomain parameter
                # It will show a selection menu for the user
                Write-Information -MessageData "Launching certificate deletion process..." -InformationAction Continue
                Remove-Certificate
                Write-Information -MessageData "Certificate deletion process completed." -InformationAction Continue
            } catch
            {
                Write-Error -Message "Failed to delete certificate: $($_.Exception.Message)"
            }
        } else
        {
            Write-Warning -Message "Deletion cancelled."
        }
    } else
    {
        Write-Warning -Message "No certificate selected."
    }

    Wait-UserInput
}

# Export the single-certificate management function
function Invoke-SingleCertificateManagement
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$CertificateOrder
    )

    while ($true)
    {
        Clear-Host
        $mainDomain = $CertificateOrder.MainDomain
        Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
        Write-Information -MessageData "    MANAGING CERTIFICATE: $mainDomain" -InformationAction Continue
        Write-Information -MessageData "$("="*70)" -InformationAction Continue

        try
        {
            $certDetails = Get-PACertificate -MainDomain $mainDomain -ErrorAction Stop
            Write-Information -MessageData "Status: $($certDetails.Status)" -InformationAction Continue
            Write-Information -MessageData "Expires: $($certDetails.NotAfter)" -InformationAction Continue
            Write-Information -MessageData "SANs: $($certDetails.SANs -join ', ')" -InformationAction Continue
        } catch
        {
            Write-Error -Message "Could not retrieve certificate details."
        }

        Write-Information -MessageData "`nAvailable Actions for ${mainDomain}:" -InformationAction Continue
        Write-Warning -Message "1. Force Renew"
        Write-Information -MessageData "2. Re-install Certificate" -InformationAction Continue
        Write-Error -Message "3. Revoke Certificate"
        Write-Information -MessageData "4. View Details" -InformationAction Continue
        Write-Information -MessageData "0. Return to Main Menu" -InformationAction Continue
        Write-Information -MessageData "`n$("="*70)" -InformationAction Continue

        $choice = Read-Host "Enter your choice for '$mainDomain'"

        switch ($choice)
        {
            '1'
            {
                # Force renew certificate
                try
                {
                    Write-Warning -Message "Initiating certificate renewal for $mainDomain..."
                    Submit-Renewal -MainDomain $mainDomain -Force
                    Write-Information -MessageData "Certificate renewal initiated." -InformationAction Continue
                } catch
                {
                    Write-Error -Message "Failed to renew certificate: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '2'
            {
                # Re-install certificate
                try
                {
                    Write-Information -MessageData "Re-installing certificate for $mainDomain..." -InformationAction Continue
                    Install-Certificate -MainDomain $mainDomain
                } catch
                {
                    Write-Error -Message "Failed to re-install certificate: $($_.Exception.Message)"
                } finally
                {
                    Write-Progress -Activity "Certificate Re-installation" -Completed
                }

                Wait-UserInput
            }
            '3'
            {
                # Revoke certificate
                Write-Error -Message "`nWarning: This will permanently revoke the certificate for $mainDomain!"
                Write-Warning -Message "The certificate will be immediately invalid for all uses."
                Write-Error -Message "Are you sure you want to proceed? (yes/no)"

                $confirm = Read-Host
                if ($confirm -eq 'yes')
                {
                    try
                    {
                        Write-Warning -Message "Revoking certificate for $mainDomain..."
                        Revoke-Certificate -MainDomain $mainDomain
                        Write-Information -MessageData "Certificate revoked." -InformationAction Continue
                    } catch
                    {
                        Write-Error -Message "Failed to revoke certificate: $($_.Exception.Message)"
                    }
                } else
                {
                    Write-Warning -Message "Revocation cancelled."
                }

                Wait-UserInput
            }
            '4'
            {
                # View detailed information
                Clear-Host
                Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
                Write-Information -MessageData "    CERTIFICATE DETAILS: $mainDomain" -InformationAction Continue
                Write-Information -MessageData "$("="*70)" -InformationAction Continue

                try
                {
                    $cert = Get-PACertificate -MainDomain $mainDomain
                    $order = Get-PAOrder -MainDomain $mainDomain

                    Write-Information -MessageData "`nCertificate Information:" -InformationAction Continue
                    Write-Information -MessageData "  Subject: $($cert.Subject)" -InformationAction Continue
                    Write-Information -MessageData "  Issuer: $($cert.Issuer)" -InformationAction Continue
                    Write-Information -MessageData "  Valid from: $($cert.NotBefore)" -InformationAction Continue
                    Write-Information -MessageData "  Valid until: $($cert.NotAfter)" -InformationAction Continue
                    Write-Information -MessageData "  Expires in: $(($cert.NotAfter - (Get-Date)).Days) days" -InformationAction Continue
                    Write-Information -MessageData "  Serial Number: $($cert.SerialNumber)" -InformationAction Continue
                    Write-Information -MessageData "  Thumbprint: $($cert.Thumbprint)" -InformationAction Continue

                    Write-Information -MessageData "`nSubject Alternative Names:" -InformationAction Continue
                    foreach ($san in $cert.SANs)
                    {
                        Write-Information -MessageData "  - $san" -InformationAction Continue
                    }

                    Write-Information -MessageData "`nOrder Information:" -InformationAction Continue
                    Write-Information -MessageData "  Status: $($order.Status)" -InformationAction Continue
                    Write-Information -MessageData "  Created: $($order.Created)" -InformationAction Continue
                    Write-Information -MessageData "  Last Renewed: $($order.RenewAfter)" -InformationAction Continue

                    Write-Information -MessageData "`nCertificate Paths:" -InformationAction Continue
                    Write-Information -MessageData "  Certificate: $($cert.CertFile)" -InformationAction Continue
                    Write-Information -MessageData "  Private Key: $($cert.KeyFile)" -InformationAction Continue
                    Write-Information -MessageData "  Chain: $($cert.ChainFile)" -InformationAction Continue
                    Write-Information -MessageData "  Full Chain: $($cert.FullChainFile)" -InformationAction Continue
                    Write-Information -MessageData "  PFX: $($cert.PfxFile)" -InformationAction Continue

                } catch
                {
                    Write-Error -Message "Failed to retrieve certificate details: $($_.Exception.Message)"
                }

                Wait-UserInput
            }
            '0' { return }
            default { Write-Warning -Message "Invalid option. Please try again." }
        }
    }
}

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Show-CertificateManagementMenu, Invoke-SingleCertificateManagement

