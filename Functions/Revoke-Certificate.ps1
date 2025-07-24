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
        Write-Warning -Message "No active certificates available to revoke."
        return
    }
    Write-Host -Object "`nSelect the certificate to revoke:"
    $i = 1
    foreach ($cert in $certs) {
        Write-Host -Object "$i) $($cert.AllSANs -join ', ')"
        $i++
    }
    $selection = Get-ValidatedInput -Prompt "`nEnter the number corresponding to the certificate or 0 to cancel" -ValidOptions (1..$certs.Count)
    if ($selection -eq 0) {
        Write-Host -Object "Operation canceled."
        return
    }
    $certToRevoke = $certs[$selection - 1]
    # Get certificate file path
    $certFilePath = $certToRevoke.CertFile
    if (-not (Test-Path $certFilePath)) {
        Write-Error -Message "Certificate file not found at $certFilePath. Cannot revoke."
        Write-Log "Certificate file not found at $certFilePath. Cannot revoke." -Level 'Error'
        return
    }
    # Get private key file path
    $keyFilePath = $certToRevoke.KeyFile
    if (-not (Test-Path $keyFilePath)) {
        Write-Error -Message "Private key file not found at $keyFilePath. Cannot revoke."
        Write-Log "Private key file not found at $keyFilePath. Cannot revoke." -Level 'Error'
        return
    }
    # Confirm revocation
    if (-not (Confirm-Action -Message "`nAre you sure you want to revoke the certificate for $($certToRevoke.AllSANs -join ', ')? (Y/N)")) {
        Write-Host -Object "Revocation canceled."
        return
    }
    try {
        Revoke-PACertificate -CertFile $certFilePath -KeyFile $keyFilePath -Reason keyCompromise -Force -Verbose
        # Mark local as revoked
        $revokedCerts += $certToRevoke.MainDomain
        Save-RevokedCertificates $revokedCerts
        Write-Host -Object "Certificate for $($certToRevoke.AllSANs -join ', ') has been revoked." -ForegroundColor Green
        Write-Log "Certificate for $($certToRevoke.AllSANs -join ', ') has been revoked."
    } catch {
        if ($_.Exception.Message -match 'already revoked') {
            # Update local status
            $revokedCerts += $certToRevoke.MainDomain
            Save-RevokedCertificates $revokedCerts
            Write-Warning -Message "Certificate is already revoked. Updated status."
            Write-Log "Certificate already revoked. Updated status."
        } else {
            Write-Error -Message "Failed to revoke certificate: $($_)"
            Write-Log "Failed to revoke certificate: $($_)" -Level 'Error'
        }
    }
}


