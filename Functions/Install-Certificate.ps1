<#
    .SYNOPSIS
        Installs or saves an issued certificate to a variety of targets.
#>

function Install-Certificate {
    param(
        [Parameter(Mandatory = $false)]
        [object]$PACertificate
    )

    Initialize-ACMEServer

    if (-not $PACertificate) {
        # Prompt user to select an existing certificate
        $certs = Get-PACertificate
        if (-not $certs) {
            Write-Host "No certificates available to install." -ForegroundColor Yellow
            return
        }

        Write-Host "`nSelect the certificate you want to install:"
        $i = 1
        foreach ($cert in $certs) {
            Write-Host "$i) $($cert.MainDomain)"
            $i++
        }
        Write-Host "0) Back"
        $selection = Get-ValidatedInput -Prompt "`nEnter the number corresponding to your choice (0-$($certs.Count))" -ValidOptions (1..$certs.Count)
        if ($selection -eq 0) {
            return
        } else {
            $PACertificate = $certs[$selection - 1]
        }
    }

    while ($true) {
        Write-Host "`nCertificate for $($PACertificate.MainDomain) selected."
        Write-Host "`nSelect how you want to install or save the certificate:"
        Write-Host "1) Install on Management Server (LocalMachine certificate store)"
        Write-Host "2) Install on Recording Server (convert to PEM and save)"
        Write-Host "3) Save certificate to Desktop (PFX file)"
        Write-Host "0) Back"

        $installChoice = Get-ValidatedInput -Prompt "`nEnter your choice (0-3)" -ValidOptions 1,2,3

        switch ($installChoice) {
            0 { return }
            1 {
                # Install on local machine
                Write-Host "`nInstalling certificate on Management Server..."
                $exportableChoice = Read-Host "`nDo you want the private key to be exportable? (Y/N) or 0 to go back"
                if ($exportableChoice -eq '0') { continue }

                $isNotExportable = $exportableChoice -match '^(N|n)$'
                try {
                    $installParams = @{
                        PACertificate = $PACertificate
                        StoreLocation = 'LocalMachine'
                        Verbose       = $true
                    }
                    if ($isNotExportable) {
                        $installParams['NotExportable'] = $true
                    }
                    Install-PACertificate @installParams
                    Write-Host "Certificate installed to LocalMachine\My store." -ForegroundColor Green
                    Write-Log "Certificate installed to LocalMachine\My for $($PACertificate.MainDomain)"
                } catch {
                    Write-Host "Failed to install certificate: $($_)" -ForegroundColor Red
                    Write-Log "Failed to install certificate: $($_)" -Level 'Error'
                }
                break
            }
            2 {
                # Install on Recording Server
                Write-Host "`nInstalling certificate on Recording Server..."
                $certDir = Get-RSCertFolder
                if (-not $certDir) { return }

                # Retrieve PEM content
                $certPemContent = if ($PACertificate.CertificatePEM) {
                    Get-Content -Path $PACertificate.CertificatePEM -Raw
                } elseif ($PACertificate.PEM) {
                    $PACertificate.PEM
                } elseif ($PACertificate.CertFile) {
                    Get-Content -Path $PACertificate.CertFile -Raw
                } else {
                    Write-Host "Unable to retrieve PEM content from certificate object." -ForegroundColor Red
                    Write-Log "Unable to retrieve PEM content from certificate object." -Level 'Error'
                    return
                }

                $keyPemContent = if ($PACertificate.KeyFile) {
                    Get-Content -Path $PACertificate.KeyFile -Raw
                } else {
                    Write-Host "Unable to retrieve key content from certificate object." -ForegroundColor Red
                    Write-Log "Unable to retrieve key content from certificate object." -Level 'Error'
                    return
                }

                # Save PEM files with auto-versioning
                $result = Save-PEMFiles -directory $certDir -certContent $certPemContent -keyContent $keyPemContent
                if ($result) {
                    Write-Host "`nCertificate and private key saved to:"
                    Write-Host "Certificate: $($result.CertFile)"
                    Write-Host "Private Key: $($result.KeyFile)"
                    Write-Log "Certificate and private key saved to Recording Server directory."
                }
                break
            }
            3 {
                # Save to Desktop as PFX
                Write-Host "`nSaving certificate to Desktop as PFX..."
                $desktopPath     = [Environment]::GetFolderPath("Desktop")
                $defaultCertPath = Join-Path $desktopPath "certificate.pfx"
                $certPath = Read-Host "`nEnter path to save the certificate (default: $defaultCertPath) or 0 to go back"
                if ($certPath -eq '0') { continue }
                if (-not $certPath) { $certPath = $defaultCertPath }

                $certPassword = Read-Host "`nEnter a password for the PFX file (leave blank for no password) or 0 to go back" -AsSecureString
                if (([System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($certPassword))
                    ) -eq '0') {
                    continue
                }

                try {
                    Export-PACertificate -MainDomain $PACertificate.MainDomain -Type PFX -Path $certPath -Password $certPassword
                    Write-Host "Certificate saved to $certPath" -ForegroundColor Green
                    Write-Log "Certificate saved to $certPath"
                } catch {
                    Write-Host "Failed to save certificate: $($_)" -ForegroundColor Red
                    Write-Log "Failed to save certificate: $($_)" -Level 'Error'
                }
                break
            }
            default {
                Write-Host "Invalid selection. Please choose 0-3." -ForegroundColor Yellow
            }
        }
    }
}
