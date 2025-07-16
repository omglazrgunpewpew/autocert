<#
    .SYNOPSIS
        Allows the user to select and remove an existing Posh-ACME order from local storage.
#>
function Remove-Certificate {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Initialize-ACMEServer
    $revokedCerts = Get-RevokedCertificates
    $orders       = Get-PAOrder
    if (-not $orders) {
        Write-Host "No certificates available to delete." -ForegroundColor Yellow
        return
    }
    Write-Host "`nSelect the certificate to delete:"
    $i = 1
    foreach ($order in $orders) {
        $status = ($revokedCerts -contains $order.MainDomain) ? "Revoked" : "Active"
        Write-Host "$i) $($order.MainDomain) - Status: $status"
        $i++
    }
    $selection = Get-ValidatedInput -Prompt "`nEnter the number corresponding to the certificate or 0 to cancel" -ValidOptions (1..$orders.Count)
    if ($selection -eq 0) {
        Write-Host "Operation canceled."
        return
    }
    $orderToDelete = $orders[$selection - 1]
    $mainDomain    = $orderToDelete.MainDomain
    $isRevoked     = $revokedCerts -contains $mainDomain
    if ($isRevoked) {
        if (-not (Confirm-Action -Message "`nThe certificate for $mainDomain is already revoked. Delete anyway? (Y/N)")) {
            Write-Host "Deletion canceled."
            return
        }
    } else {
        # Offer to revoke first
        $revokeFirst = Read-Host "`nThe certificate for $mainDomain is still active. Revoke before deletion? (Y/N/Cancel)"
        if ($revokeFirst -match '^(Y|y)$') {
            $cert = Get-PACertificate -MainDomain $mainDomain
            if ($cert) {
                $certFilePath = $cert.CertFile
                $keyFilePath  = $cert.KeyFile
                if ((Test-Path $certFilePath) -and (Test-Path $keyFilePath)) {
                    if ($PSCmdlet.ShouldProcess($mainDomain, "Revoke certificate")) {
                        try {
                            Revoke-PACertificate -CertFile $certFilePath -KeyFile $keyFilePath -Reason keyCompromise -Force -Verbose
                            $revokedCerts += $mainDomain
                            Save-RevokedCertificates $revokedCerts
                            Write-Information "Certificate for $mainDomain revoked." -InformationAction Continue
                        } catch {
                            if ($_.Exception.Message -match 'already revoked') {
                                $revokedCerts += $mainDomain
                                Save-RevokedCertificates $revokedCerts
                                Write-Warning "Certificate was already revoked. Updated status."
                            } else {
                                Write-Host "Failed to revoke certificate for ${mainDomain}: $($_)" -ForegroundColor Red
                                Write-Log "Failed to revoke certificate for ${mainDomain}: $($_)" -Level 'Error'
                                return
                            }
                        }
                    }
                } else {
                    Write-Host "`nCertificate or key file not found. Cannot revoke." -ForegroundColor Red
                    Write-Log "Certificate or key file not found for $mainDomain. Cannot revoke." -Level 'Error'
                    return
                }
            } else {
                Write-Host "`nCertificate not found. Cannot revoke." -ForegroundColor Red
                Write-Log "Certificate not found for $mainDomain. Cannot revoke." -Level 'Error'
                return
            }
        } elseif ($revokeFirst -match '^(Cancel|cancel|C|c)$') {
            Write-Host "Deletion canceled."
            return
        }
        # If user typed 'N', continue to deletion
    }
    # Confirm deletion
    if (-not (Confirm-Action -Message "`nAre you sure you want to delete the certificate for ${mainDomain}? (Y/N)")) {
        Write-Host "Deletion canceled."
        return
    }
    try {
        Remove-PAOrder -MainDomain $mainDomain -Force -Verbose
        # Remove from revoked list if needed
        if ($revokedCerts -contains $mainDomain) {
            $revokedCerts = $revokedCerts | Where-Object { $_ -ne $mainDomain }
            Save-RevokedCertificates $revokedCerts
        }
        Write-Host "`nCertificate for $mainDomain deleted." -ForegroundColor Green
        Write-Log "Certificate for $mainDomain deleted."
    } catch {
        Write-Host "Failed to delete certificate for ${mainDomain}: $($_)" -ForegroundColor Red
        Write-Log "Failed to delete certificate for ${mainDomain}: $($_)" -Level 'Error'
    }
}