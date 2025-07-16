<#
    .SYNOPSIS
        Allows the user to select and revoke an active certificate.
#>
function Revoke-Certificate {
    Initialize-ACMEServer
    # Load revoked certificates
    $revokedCerts = Get-RevokedCertificates
    # Filter out any domains that are already revoked
    $certs = Get-PACertificate | Where-Object { $revokedCerts -notcontains $_.MainDomain }
    if (-not $certs) {
        Write-Host "No active certificates available to revoke." -ForegroundColor Yellow
        return
    }
    Write-Host "`nSelect the certificate to revoke:"
    $i = 1
    foreach ($cert in $certs) {
        Write-Host "$i) $($cert.AllSANs -join ', ')"
        $i++
    }
    $selection = Get-ValidatedInput -Prompt "`nEnter the number corresponding to the certificate or 0 to cancel" -ValidOptions (1..$certs.Count)
    if ($selection -eq 0) {
        Write-Host "Operation canceled."
        return
    }
    $certToRevoke = $certs[$selection - 1]
    # Get certificate file path
    $certFilePath = $certToRevoke.CertFile
    if (-not (Test-Path $certFilePath)) {
        Write-Host "Certificate file not found at $certFilePath. Cannot revoke." -ForegroundColor Red
        Write-Log "Certificate file not found at $certFilePath. Cannot revoke." -Level 'Error'
        return
    }
    # Get private key file path
    $keyFilePath = $certToRevoke.KeyFile
    if (-not (Test-Path $keyFilePath)) {
        Write-Host "Private key file not found at $keyFilePath. Cannot revoke." -ForegroundColor Red
        Write-Log "Private key file not found at $keyFilePath. Cannot revoke." -Level 'Error'
        return
    }
    # Confirm revocation
    if (-not (Confirm-Action -Message "`nAre you sure you want to revoke the certificate for $($certToRevoke.AllSANs -join ', ')? (Y/N)")) {
        Write-Host "Revocation canceled."
        return
    }
    try {
        Revoke-PACertificate -CertFile $certFilePath -KeyFile $keyFilePath -Reason keyCompromise -Force -Verbose
        # Mark local as revoked
        $revokedCerts += $certToRevoke.MainDomain
        Save-RevokedCertificates $revokedCerts
        Write-Host "Certificate for $($certToRevoke.AllSANs -join ', ') has been revoked." -ForegroundColor Green
        Write-Log "Certificate for $($certToRevoke.AllSANs -join ', ') has been revoked."
    } catch {
        if ($_.Exception.Message -match 'already revoked') {
            # Update local status
            $revokedCerts += $certToRevoke.MainDomain
            Save-RevokedCertificates $revokedCerts
            Write-Host "Certificate is already revoked. Updated status." -ForegroundColor Yellow
            Write-Log "Certificate already revoked. Updated status."
        } else {
            Write-Host "Failed to revoke certificate: $($_)" -ForegroundColor Red
            Write-Log "Failed to revoke certificate: $($_)" -Level 'Error'
        }
    }
}