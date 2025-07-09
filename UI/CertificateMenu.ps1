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
        Write-Host "`n" + "="*70 -ForegroundColor Cyan
        Write-Host "    CERTIFICATE MANAGEMENT" -ForegroundColor Cyan
        Write-Host "="*70 -ForegroundColor Cyan

        # Show current certificate summary
        try {
            $orders = Get-PAOrder
            if ($orders) {
                $config = Get-RenewalConfig
                $renewalStatus = Get-CertificateRenewalStatus -Config $config
                $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
                $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count
                $total = $orders.Count
                
                Write-Host "Certificate Summary:" -ForegroundColor Green
                Write-Host "  Total certificates: $total" -ForegroundColor White
                if ($needsRenewal -gt 0) {
                    Write-Host "  Certificates needing renewal: $needsRenewal" -ForegroundColor Yellow
                }
                if ($expiringSoon -gt 0) {
                    Write-Host "  Expiring within 7 days: $expiringSoon" -ForegroundColor Red
                }
                Write-Host ""
            } else {
                Write-Host "No certificates found." -ForegroundColor Yellow
                Write-Host ""
            }
        } catch {
            Write-Host "Could not retrieve certificate summary." -ForegroundColor Red
            Write-Host ""
        }

        Write-Host "Available Actions:" -ForegroundColor White
        Write-Host "1. View all certificates (detailed list)" -ForegroundColor Green
        Write-Host "2. Manage individual certificate" -ForegroundColor Cyan
        Write-Host "3. Bulk renewal check" -ForegroundColor Yellow
        Write-Host "4. Export certificates" -ForegroundColor Blue
        Write-Host "5. Revoke a certificate" -ForegroundColor Red
        Write-Host "6. Delete a certificate" -ForegroundColor Red
        Write-Host "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            '1' {
                # View all certificates in detailed list format
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    ALL CERTIFICATES - DETAILED VIEW" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                Get-ExistingCertificates
                Read-Host "`nPress Enter to continue"
            }
            '2' {
                # Manage individual certificate - show selection menu
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    SELECT CERTIFICATE TO MANAGE" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Invoke-SingleCertificateManagement -CertificateOrder $selectedOrder
                } else {
                    Write-Host "No certificate selected." -ForegroundColor Yellow
                    Read-Host "Press Enter to continue"
                }
            }
            '3' {
                # Bulk renewal check
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    BULK RENEWAL CHECK" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                try {
                    $orders = Get-PAOrder
                    if ($orders) {
                        $config = Get-RenewalConfig
                        $renewalStatus = Get-CertificateRenewalStatus -Config $config
                        
                        Write-Host "Renewal Status Summary:" -ForegroundColor Green
                        foreach ($status in $renewalStatus) {
                            $color = if ($status.NeedsRenewal) { 
                                if ($status.DaysUntilExpiry -le 7) { "Red" } else { "Yellow" }
                            } else { "Green" }
                            
                            $statusText = if ($status.NeedsRenewal) { "NEEDS RENEWAL" } else { "OK" }
                            Write-Host "  $($status.Domain): $statusText (expires in $($status.DaysUntilExpiry) days)" -ForegroundColor $color
                        }
                        
                        $needsRenewal = $renewalStatus | Where-Object { $_.NeedsRenewal }
                        if ($needsRenewal) {
                            Write-Host "`nWould you like to renew all certificates that need renewal? (y/n)" -ForegroundColor Yellow
                            $renewChoice = Read-Host
                            if ($renewChoice -eq 'y' -or $renewChoice -eq 'Y') {
                                Write-Host "Starting bulk renewal process..." -ForegroundColor Cyan
                                Update-AllCertificates -Force
                            }
                        }
                    } else {
                        Write-Host "No certificates found." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Error "Bulk renewal check failed: $($_.Exception.Message)"
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
                Write-Warning "Invalid option. Please try again."
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
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    EXPORT CERTIFICATES" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    try {
        $orders = Get-PAOrder
        if ($orders) {
            Write-Host "Available certificates:" -ForegroundColor Green
            for ($i = 0; $i -lt $orders.Count; $i++) {
                Write-Host "  $($i + 1). $($orders[$i].MainDomain)" -ForegroundColor White
            }
            Write-Host "  A. All certificates" -ForegroundColor Yellow
            Write-Host "  0. Cancel" -ForegroundColor Red
            
            $exportChoice = Read-Host "`nEnter your choice"
            
            if ($exportChoice -eq 'A' -or $exportChoice -eq 'a') {
                # Export all certificates
                $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                if ([string]::IsNullOrWhiteSpace($exportPath)) {
                    $exportPath = $PWD.Path
                }
                
                Write-Host "Exporting all certificates to: $exportPath" -ForegroundColor Cyan
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
                        
                        Write-Host "  Exported: $($order.MainDomain)" -ForegroundColor Green
                    } catch {
                        Write-Host "  Failed to export: $($order.MainDomain) - $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Host "Export completed." -ForegroundColor Green
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
                    
                    Write-Host "Certificate exported to: $domainPath" -ForegroundColor Green
                } catch {
                    Write-Error "Failed to export certificate: $($_.Exception.Message)"
                }
            } elseif ($exportChoice -ne '0') {
                Write-Host "Invalid choice." -ForegroundColor Red
            }
        } else {
            Write-Host "No certificates found to export." -ForegroundColor Yellow
        }
    } catch {
        Write-Error "Export operation failed: $($_.Exception.Message)"
    }
    
    Read-Host "`nPress Enter to continue"
}

# Extracted from the main certificate menu to improve modularity
function Invoke-CertificateRevocationMenu {
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    REVOKE CERTIFICATE" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    Write-Host "Warning: Certificate revocation is permanent and cannot be undone!" -ForegroundColor Red
    Write-Host "Revoked certificates will be immediately invalid for all uses." -ForegroundColor Yellow
    Write-Host ""
    
    $selectedOrder = Get-ExistingCertificates -ShowMenu
    if ($selectedOrder) {
        Write-Host "`nYou have selected: $($selectedOrder.MainDomain)" -ForegroundColor Yellow
        Write-Host "Are you sure you want to revoke this certificate? (yes/no)" -ForegroundColor Red
        $confirmation = Read-Host
        
        if ($confirmation -eq 'yes') {
            try {
                # Note: Revoke-Certificate doesn't accept MainDomain parameter
                # It will show a selection menu for the user
                Write-Host "Launching certificate revocation process..." -ForegroundColor Cyan
                Revoke-Certificate
                Write-Host "Certificate revocation process completed." -ForegroundColor Green
            } catch {
                Write-Error "Failed to revoke certificate: $($_.Exception.Message)"
            }
        } else {
            Write-Host "Revocation cancelled." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No certificate selected." -ForegroundColor Yellow
    }
    
    Read-Host "`nPress Enter to continue"
}

# Extracted from the main certificate menu to improve modularity
function Invoke-CertificateDeletionMenu {
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    DELETE CERTIFICATE" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    Write-Host "Warning: This will permanently delete the certificate and all associated data!" -ForegroundColor Red
    Write-Host "The certificate will be removed from local storage and cannot be recovered." -ForegroundColor Yellow
    Write-Host "Consider revoking the certificate first if it's still valid." -ForegroundColor Yellow
    Write-Host ""
    
    $selectedOrder = Get-ExistingCertificates -ShowMenu
    if ($selectedOrder) {
        Write-Host "`nYou have selected: $($selectedOrder.MainDomain)" -ForegroundColor Yellow
        Write-Host "Are you sure you want to delete this certificate? (yes/no)" -ForegroundColor Red
        $confirmation = Read-Host
        if ($confirmation -eq 'yes') {
            try {
                # Note: Remove-Certificate doesn't accept MainDomain parameter
                # It will show a selection menu for the user
                Write-Host "Launching certificate deletion process..." -ForegroundColor Cyan
                Remove-Certificate
                Write-Host "Certificate deletion process completed." -ForegroundColor Green
            } catch {
                Write-Error "Failed to delete certificate: $($_.Exception.Message)"
            }
        } else {
            Write-Host "Deletion cancelled." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No certificate selected." -ForegroundColor Yellow
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
        Write-Host "`n" + "="*70 -ForegroundColor Cyan
        Write-Host "    MANAGING CERTIFICATE: $mainDomain" -ForegroundColor Cyan
        Write-Host "="*70 -ForegroundColor Cyan

        try {
            $certDetails = Get-PACertificate -MainDomain $mainDomain -ErrorAction Stop
            Write-Host "Status: $($certDetails.Status)" -ForegroundColor $(if ($certDetails.Status -eq "Valid") { "Green" } else { "Yellow" })
            Write-Host "Expires: $($certDetails.NotAfter)" -ForegroundColor $(if (($certDetails.NotAfter - (Get-Date)).Days -gt 30) { "Green" } else { "Yellow" })
            Write-Host "SANs: $($certDetails.SANs -join ', ')" -ForegroundColor Gray
        } catch {
            Write-Host "Could not retrieve certificate details." -ForegroundColor Red
        }

        Write-Host "`nAvailable Actions for ${mainDomain}:" -ForegroundColor White
        Write-Host "1. Force Renew" -ForegroundColor Yellow
        Write-Host "2. Re-install Certificate" -ForegroundColor Cyan
        Write-Host "3. Revoke Certificate" -ForegroundColor Red
        Write-Host "4. View Details" -ForegroundColor Magenta
        Write-Host "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice for '$mainDomain'"

        switch ($choice) {
            '1' {
                # Force renew certificate
                try {
                    Write-Host "Initiating certificate renewal for $mainDomain..." -ForegroundColor Yellow
                    Submit-Renewal -MainDomain $mainDomain -Force
                    Write-Host "Certificate renewal initiated." -ForegroundColor Green
                } catch {
                    Write-Error "Failed to renew certificate: $($_.Exception.Message)"
                }
                
                Read-Host "`nPress Enter to continue"
            }
            '2' {
                # Re-install certificate
                try {
                    Write-Host "Re-installing certificate for $mainDomain..." -ForegroundColor Cyan
                    Install-Certificate -MainDomain $mainDomain
                } catch {
                    Write-Error "Failed to re-install certificate: $($_.Exception.Message)"
                }
                
                Read-Host "`nPress Enter to continue"
            }
            '3' {
                # Revoke certificate
                Write-Host "`nWarning: This will permanently revoke the certificate for $mainDomain!" -ForegroundColor Red
                Write-Host "The certificate will be immediately invalid for all uses." -ForegroundColor Yellow
                Write-Host "Are you sure you want to proceed? (yes/no)" -ForegroundColor Red
                
                $confirm = Read-Host
                if ($confirm -eq 'yes') {
                    try {
                        Write-Host "Revoking certificate for $mainDomain..." -ForegroundColor Yellow
                        Revoke-Certificate -MainDomain $mainDomain
                        Write-Host "Certificate revoked." -ForegroundColor Green
                    } catch {
                        Write-Error "Failed to revoke certificate: $($_.Exception.Message)"
                    }
                } else {
                    Write-Host "Revocation cancelled." -ForegroundColor Yellow
                }
                
                Read-Host "`nPress Enter to continue"
            }
            '4' {
                # View detailed information
                Clear-Host
                Write-Host "`n" + "="*70 -ForegroundColor Cyan
                Write-Host "    CERTIFICATE DETAILS: $mainDomain" -ForegroundColor Cyan
                Write-Host "="*70 -ForegroundColor Cyan
                
                try {
                    $cert = Get-PACertificate -MainDomain $mainDomain
                    $order = Get-PAOrder -MainDomain $mainDomain
                    
                    Write-Host "`nCertificate Information:" -ForegroundColor Green
                    Write-Host "  Subject: $($cert.Subject)" -ForegroundColor White
                    Write-Host "  Issuer: $($cert.Issuer)" -ForegroundColor White
                    Write-Host "  Valid from: $($cert.NotBefore)" -ForegroundColor White
                    Write-Host "  Valid until: $($cert.NotAfter)" -ForegroundColor White
                    Write-Host "  Expires in: $(($cert.NotAfter - (Get-Date)).Days) days" -ForegroundColor $(if (($cert.NotAfter - (Get-Date)).Days -gt 30) { "Green" } else { "Yellow" })
                    Write-Host "  Serial Number: $($cert.SerialNumber)" -ForegroundColor Gray
                    Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
                    
                    Write-Host "`nSubject Alternative Names:" -ForegroundColor Green
                    foreach ($san in $cert.SANs) {
                        Write-Host "  • $san" -ForegroundColor White
                    }
                    
                    Write-Host "`nOrder Information:" -ForegroundColor Green
                    Write-Host "  Status: $($order.Status)" -ForegroundColor White
                    Write-Host "  Created: $($order.Created)" -ForegroundColor White
                    Write-Host "  Last Renewed: $($order.RenewAfter)" -ForegroundColor White
                    
                    Write-Host "`nCertificate Paths:" -ForegroundColor Green
                    Write-Host "  Certificate: $($cert.CertFile)" -ForegroundColor Gray
                    Write-Host "  Private Key: $($cert.KeyFile)" -ForegroundColor Gray
                    Write-Host "  Chain: $($cert.ChainFile)" -ForegroundColor Gray
                    Write-Host "  Full Chain: $($cert.FullChainFile)" -ForegroundColor Gray
                    Write-Host "  PFX: $($cert.PfxFile)" -ForegroundColor Gray
                    
                } catch {
                    Write-Error "Failed to retrieve certificate details: $($_.Exception.Message)"
                }
                
                Read-Host "`nPress Enter to continue"
            }
            '0' { return }
            default { Write-Warning "Invalid option. Please try again." }
        }
    }
}

# Export functions
Export-ModuleMember -Function Show-CertificateManagementMenu, Invoke-SingleCertificateManagement
