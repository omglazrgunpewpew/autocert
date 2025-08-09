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
function Show-CertificateManagementMenu {
    [CmdletBinding()]
    param()

    while ($true) {
        Clear-Host
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
        Write-Host -Object "    CERTIFICATE MANAGEMENT" -ForegroundColor Cyan
        Write-Host -Object "="*70 -ForegroundColor Cyan

        # Show current certificate summary
        try {
            $orders = Get-PAOrder
            if ($orders) {
                $config = Get-RenewalConfig
                $renewalStatus = Get-CertificateRenewalStatus -Config $config
                $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
                $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count
                $total = $orders.Count

                Write-Information -MessageData "Certificate Summary:" -InformationAction Continue
                Write-Host -Object "  Total certificates: $total" -ForegroundColor White
                if ($needsRenewal -gt 0) {
                    Write-Warning -Message "  Certificates needing renewal: $needsRenewal"
                }
                if ($expiringSoon -gt 0) {
                    Write-Error -Message "  Expiring within 7 days: $expiringSoon"
                }
                Write-Information -MessageData "" -InformationAction Continue
            } else {
                Write-Warning -Message "No certificates found."
                Write-Information -MessageData "" -InformationAction Continue
            }
        } catch {
            Write-Error -Message "Could not retrieve certificate summary."
            Write-Information -MessageData "" -InformationAction Continue
        }

        Write-Host -Object "Available Actions:" -ForegroundColor White
        Write-Information -MessageData "1. View all certificates (detailed list)" -InformationAction Continue
        Write-Host -Object "2. Manage individual certificate" -ForegroundColor Cyan
        Write-Warning -Message "3. Bulk renewal check"
        Write-Host -Object "4. Export certificates" -ForegroundColor Blue
        Write-Error -Message "5. Revoke a certificate"
        Write-Error -Message "6. Delete a certificate"
        Write-Host -Object "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            '1' {
                # View all certificates in detailed list format
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    ALL CERTIFICATES - DETAILED VIEW" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                Get-ExistingCertificates
                Read-Host "`nPress Enter to continue"
            }
            '2' {
                # Manage individual certificate - show selection menu
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    SELECT CERTIFICATE TO MANAGE" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Invoke-SingleCertificateManagement -CertificateOrder $selectedOrder
                } else {
                    Write-Warning -Message "No certificate selected."
                    Read-Host "Press Enter to continue"
                }
            }
            '3' {
                # Bulk renewal check
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    BULK RENEWAL CHECK" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                try {
                    $orders = Get-PAOrder
                    if ($orders) {
                        $config = Get-RenewalConfig
                        $renewalStatus = Get-CertificateRenewalStatus -Config $config

                        Write-Information -MessageData "Renewal Status Summary:" -InformationAction Continue
                        foreach ($status in $renewalStatus) {
                            $color = if ($status.NeedsRenewal) {
                                if ($status.DaysUntilExpiry -le 7) { "Red" } else { "Yellow" }
                            } else { "Green" }

                            $statusText = if ($status.NeedsRenewal) { "NEEDS RENEWAL" } else { "OK" }
                            Write-Host -Object "  $($status.Domain): $statusText (expires in $($status.DaysUntilExpiry) days)" -ForegroundColor $color
                        }

                        $needsRenewal = $renewalStatus | Where-Object { $_.NeedsRenewal }
                        if ($needsRenewal) {
                            Write-Warning -Message "`nWould you like to renew all certificates that need renewal? (y/n)"
                            $renewChoice = Read-Host
                            if ($renewChoice -eq 'y' -or $renewChoice -eq 'Y') {
                                Write-Host -Object "Starting bulk renewal process..." -ForegroundColor Cyan
                                Update-AllCertificates -Force
                            }
                        }
                    } else {
                        Write-Warning -Message "No certificates found."
                    }
                } catch {
                    Write-Error -Message "Bulk renewal check failed: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '4' {
                # Export certificates
                Invoke-CertificateExportMenu
            }
            '5' {
                # Revoke a certificate
                Invoke-CertificateRevocationMenu
            }
            '6' {
                # Delete a certificate
                Invoke-CertificateDeletionMenu
            }
            '0' {
                return
            }
            default {
                Write-Warning -Message "Invalid option. Please try again."
                Read-Host "Press Enter to continue"
            }
        }
    }
}

# Extracted from the main certificate menu to improve modularity
function Invoke-CertificateExportMenu {
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    EXPORT CERTIFICATES" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    try {
        $orders = Get-PAOrder
        if ($orders) {
            Write-Information -MessageData "Available certificates:" -InformationAction Continue
            for ($i = 0; $i -lt $orders.Count; $i++) {
                Write-Host -Object "  $($i + 1). $($orders[$i].MainDomain)" -ForegroundColor White
            }
            Write-Warning -Message "  A. All certificates"
            Write-Error -Message "  0. Cancel"

            $exportChoice = Read-Host "`nEnter your choice"

            if ($exportChoice -eq 'A' -or $exportChoice -eq 'a') {
                # Export all certificates
                $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                if ([string]::IsNullOrWhiteSpace($exportPath)) {
                    $exportPath = $PWD.Path
                }

                Write-Host -Object "Exporting all certificates to: $exportPath" -ForegroundColor Cyan
                foreach ($order in $orders) {
                    try {
                        $cert = Get-PACertificate -MainDomain $order.MainDomain
                        $domainPath = Join-Path $exportPath $order.MainDomain
                        New-Item -ItemType Directory -Path $domainPath -Force | Out-Null

                        # Export certificate files if they exist
                        if ($cert.CertFile -and (Test-Path $cert.CertFile)) {
                            Copy-Item -Path $cert.CertFile -Destination (Join-Path $domainPath "cert.pem")
                        }
                        if ($cert.KeyFile -and (Test-Path $cert.KeyFile)) {
                            Copy-Item -Path $cert.KeyFile -Destination (Join-Path $domainPath "key.pem")
                        }
                        if ($cert.ChainFile -and (Test-Path $cert.ChainFile)) {
                            Copy-Item -Path $cert.ChainFile -Destination (Join-Path $domainPath "chain.pem")
                        }
                        if ($cert.FullChainFile -and (Test-Path $cert.FullChainFile)) {
                            Copy-Item -Path $cert.FullChainFile -Destination (Join-Path $domainPath "fullchain.pem")
                        }
                        if ($cert.PfxFile -and (Test-Path $cert.PfxFile)) {
                            Copy-Item -Path $cert.PfxFile -Destination (Join-Path $domainPath "cert.pfx")
                        }

                        Write-Information -MessageData "  Exported: $($order.MainDomain)" -InformationAction Continue
                    } catch {
                        Write-Host -Object "  Failed to export: $($order.MainDomain) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Information -MessageData "Export completed." -InformationAction Continue
            } elseif ($exportChoice -ge 1 -and $exportChoice -le $orders.Count) {
                # Export specific certificate
                $selectedOrder = $orders[$exportChoice - 1]
                $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                if ([string]::IsNullOrWhiteSpace($exportPath)) {
                    $exportPath = $PWD.Path
                }

                try {
                    $cert = Get-PACertificate -MainDomain $selectedOrder.MainDomain
                    $domainPath = Join-Path $exportPath $selectedOrder.MainDomain
                    New-Item -ItemType Directory -Path $domainPath -Force | Out-Null

                    # Export certificate files if they exist
                    if ($cert.CertFile -and (Test-Path $cert.CertFile)) {
                        Copy-Item -Path $cert.CertFile -Destination (Join-Path $domainPath "cert.pem")
                    }
                    if ($cert.KeyFile -and (Test-Path $cert.KeyFile)) {
                        Copy-Item -Path $cert.KeyFile -Destination (Join-Path $domainPath "key.pem")
                    }
                    if ($cert.ChainFile -and (Test-Path $cert.ChainFile)) {
                        Copy-Item -Path $cert.ChainFile -Destination (Join-Path $domainPath "chain.pem")
                    }
                    if ($cert.FullChainFile -and (Test-Path $cert.FullChainFile)) {
                        Copy-Item -Path $cert.FullChainFile -Destination (Join-Path $domainPath "fullchain.pem")
                    }
                    if ($cert.PfxFile -and (Test-Path $cert.PfxFile)) {
                        Copy-Item -Path $cert.PfxFile -Destination (Join-Path $domainPath "cert.pfx")
                    }

                    Write-Information -MessageData "Certificate exported to: $domainPath" -InformationAction Continue
                } catch {
                    Write-Error -Message "Failed to export certificate: $($_.Exception.Message)"
                }
            } elseif ($exportChoice -ne '0') {
                Write-Error -Message "Invalid choice."
            }
        } else {
            Write-Warning -Message "No certificates found to export."
        }
    } catch {
        Write-Error -Message "Export operation failed: $($_.Exception.Message)"
    }

    Read-Host "`nPress Enter to continue"
}

# Extracted from the main certificate menu to improve modularity
function Invoke-CertificateRevocationMenu {
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    REVOKE CERTIFICATE" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    Write-Error -Message "Warning: Certificate revocation is permanent and cannot be undone!"
    Write-Warning -Message "Revoked certificates will be immediately invalid for all uses."
    Write-Information -MessageData "" -InformationAction Continue

    $selectedOrder = Get-ExistingCertificates -ShowMenu
    if ($selectedOrder) {
        Write-Warning -Message "`nYou have selected: $($selectedOrder.MainDomain)"
        Write-Error -Message "Are you sure you want to revoke this certificate? (yes/no)"
        $confirmation = Read-Host

        if ($confirmation -eq 'yes') {
            try {
                # Note: Revoke-Certificate doesn't accept MainDomain parameter
                # It will show a selection menu for the user
                Write-Host -Object "Launching certificate revocation process..." -ForegroundColor Cyan
                Revoke-Certificate
                Write-Information -MessageData "Certificate revocation process completed." -InformationAction Continue
            } catch {
                Write-Error -Message "Failed to revoke certificate: $($_.Exception.Message)"
            }
        } else {
            Write-Warning -Message "Revocation cancelled."
        }
    } else {
        Write-Warning -Message "No certificate selected."
    }

    Read-Host "`nPress Enter to continue"
}

# Extracted from the main certificate menu to improve modularity
function Invoke-CertificateDeletionMenu {
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    DELETE CERTIFICATE" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    Write-Error -Message "Warning: This will permanently delete the certificate and all associated data!"
    Write-Warning -Message "The certificate will be removed from local storage and cannot be recovered."
    Write-Warning -Message "Consider revoking the certificate first if it's still valid."
    Write-Information -MessageData "" -InformationAction Continue

    $selectedOrder = Get-ExistingCertificates -ShowMenu
    if ($selectedOrder) {
        Write-Warning -Message "`nYou have selected: $($selectedOrder.MainDomain)"
        Write-Error -Message "Are you sure you want to delete this certificate? (yes/no)"
        $confirmation = Read-Host
        if ($confirmation -eq 'yes') {
            try {
                # Note: Remove-Certificate doesn't accept MainDomain parameter
                # It will show a selection menu for the user
                Write-Host -Object "Launching certificate deletion process..." -ForegroundColor Cyan
                Remove-Certificate
                Write-Information -MessageData "Certificate deletion process completed." -InformationAction Continue
            } catch {
                Write-Error -Message "Failed to delete certificate: $($_.Exception.Message)"
            }
        } else {
            Write-Warning -Message "Deletion cancelled."
        }
    } else {
        Write-Warning -Message "No certificate selected."
    }

    Read-Host "`nPress Enter to continue"
}

# Export the single-certificate management function
function Invoke-SingleCertificateManagement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$CertificateOrder
    )

    while ($true) {
        Clear-Host
        $mainDomain = $CertificateOrder.MainDomain
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
        Write-Host -Object "    MANAGING CERTIFICATE: $mainDomain" -ForegroundColor Cyan
        Write-Host -Object "="*70 -ForegroundColor Cyan

        try {
            $certDetails = Get-PACertificate -MainDomain $mainDomain -ErrorAction Stop
            Write-Host -Object "Status: $($certDetails.Status)" -ForegroundColor $(if ($certDetails.Status -eq "Valid") { "Green" } else { "Yellow" })
            Write-Host -Object "Expires: $($certDetails.NotAfter)" -ForegroundColor $(if (($certDetails.NotAfter - (Get-Date)).Days -gt 30) { "Green" } else { "Yellow" })
            Write-Host -Object "SANs: $($certDetails.SANs -join ', ')" -ForegroundColor Gray
        } catch {
            Write-Error -Message "Could not retrieve certificate details."
        }

        Write-Host -Object "`nAvailable Actions for ${mainDomain}:" -ForegroundColor White
        Write-Warning -Message "1. Force Renew"
        Write-Host -Object "2. Re-install Certificate" -ForegroundColor Cyan
        Write-Error -Message "3. Revoke Certificate"
        Write-Host -Object "4. View Details" -ForegroundColor Magenta
        Write-Host -Object "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice for '$mainDomain'"

        switch ($choice) {
            '1' {
                # Force renew certificate
                try {
                    Write-Warning -Message "Initiating certificate renewal for $mainDomain..."
                    Submit-Renewal -MainDomain $mainDomain -Force
                    Write-Information -MessageData "Certificate renewal initiated." -InformationAction Continue
                } catch {
                    Write-Error -Message "Failed to renew certificate: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '2' {
                # Re-install certificate
                try {
                    Write-Host -Object "Re-installing certificate for $mainDomain..." -ForegroundColor Cyan
                    Install-Certificate -MainDomain $mainDomain
                } catch {
                    Write-Error -Message "Failed to re-install certificate: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '3' {
                # Revoke certificate
                Write-Error -Message "`nWarning: This will permanently revoke the certificate for $mainDomain!"
                Write-Warning -Message "The certificate will be immediately invalid for all uses."
                Write-Error -Message "Are you sure you want to proceed? (yes/no)"

                $confirm = Read-Host
                if ($confirm -eq 'yes') {
                    try {
                        Write-Warning -Message "Revoking certificate for $mainDomain..."
                        Revoke-Certificate -MainDomain $mainDomain
                        Write-Information -MessageData "Certificate revoked." -InformationAction Continue
                    } catch {
                        Write-Error -Message "Failed to revoke certificate: $($_.Exception.Message)"
                    }
                } else {
                    Write-Warning -Message "Revocation cancelled."
                }

                Read-Host "`nPress Enter to continue"
            }
            '4' {
                # View detailed information
                Clear-Host
                Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
                Write-Host -Object "    CERTIFICATE DETAILS: $mainDomain" -ForegroundColor Cyan
                Write-Host -Object "="*70 -ForegroundColor Cyan

                try {
                    $cert = Get-PACertificate -MainDomain $mainDomain
                    $order = Get-PAOrder -MainDomain $mainDomain

                    Write-Information -MessageData "`nCertificate Information:" -InformationAction Continue
                    Write-Host -Object "  Subject: $($cert.Subject)" -ForegroundColor White
                    Write-Host -Object "  Issuer: $($cert.Issuer)" -ForegroundColor White
                    Write-Host -Object "  Valid from: $($cert.NotBefore)" -ForegroundColor White
                    Write-Host -Object "  Valid until: $($cert.NotAfter)" -ForegroundColor White
                    Write-Host -Object "  Expires in: $(($cert.NotAfter - (Get-Date)).Days) days" -ForegroundColor $(if (($cert.NotAfter - (Get-Date)).Days -gt 30) { "Green" } else { "Yellow" })
                    Write-Host -Object "  Serial Number: $($cert.SerialNumber)" -ForegroundColor Gray
                    Write-Host -Object "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray

                    Write-Information -MessageData "`nSubject Alternative Names:" -InformationAction Continue
                    foreach ($san in $cert.SANs) {
                        Write-Host -Object "  • $san" -ForegroundColor White
                    }

                    Write-Information -MessageData "`nOrder Information:" -InformationAction Continue
                    Write-Host -Object "  Status: $($order.Status)" -ForegroundColor White
                    Write-Host -Object "  Created: $($order.Created)" -ForegroundColor White
                    Write-Host -Object "  Last Renewed: $($order.RenewAfter)" -ForegroundColor White

                    Write-Information -MessageData "`nCertificate Paths:" -InformationAction Continue
                    Write-Host -Object "  Certificate: $($cert.CertFile)" -ForegroundColor Gray
                    Write-Host -Object "  Private Key: $($cert.KeyFile)" -ForegroundColor Gray
                    Write-Host -Object "  Chain: $($cert.ChainFile)" -ForegroundColor Gray
                    Write-Host -Object "  Full Chain: $($cert.FullChainFile)" -ForegroundColor Gray
                    Write-Host -Object "  PFX: $($cert.PfxFile)" -ForegroundColor Gray

                } catch {
                    Write-Error -Message "Failed to retrieve certificate details: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '0' { return }
            default { Write-Warning -Message "Invalid option. Please try again." }
        }
    }
}

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Show-CertificateManagementMenu, Invoke-SingleCertificateManagement

