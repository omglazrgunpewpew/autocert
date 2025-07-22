# Functions/Install-Certificate.ps1
<#
    .SYNOPSIS
        Certificate installation with deployment options,
        robust error handling, and post-installation features.
    .DESCRIPTION
        Provides an interface for installing Let's Encrypt certificates
        to various targets including certificate stores, PEM files, and PFX exports.
        Includes options, testing, monitoring, and reporting capabilities.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to install. If not provided, user will select from available certificates.
    .PARAMETER Force
        Forces installation even if certificate already exists.
    .EXAMPLE
        Install-Certificate
        Install-Certificate -PACertificate $cert -Force
#>
function Install-Certificate {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter()]
        [object]$PACertificate,
        [Parameter()]
        [switch]$Force
    )
    Initialize-ACMEServer
    $settings = Get-ScriptSettings
    # If no certificate provided, let user select one
    if ($null -eq $PACertificate) {
        Write-ProgressHelper -Activity "Certificate Installation" -Status "Loading available certificates..." -PercentComplete 10
        # Clear cache and get fresh certificate list
        Clear-CertificateCache
        $orders = Get-PAOrder
        if ($null -eq $orders -or $orders.Count -eq 0) {
            Write-Warning -Message "`nNo certificates available to install."
            Read-Host "`nPress Enter to return to the main menu"
            return
        }
        # Load certificates with error handling
        $certs = @()
        foreach ($order in $orders) {
            try {
                $cert = Get-CachedPACertificate -MainDomain $order.MainDomain
                if ($null -ne $cert) {
                    $certs += $cert
                }
            } catch {
                Write-Warning -Message "Failed to load certificate for $($order.MainDomain): $_"
            }
        }
        if ($certs.Count -eq 0) {
            Write-Warning -Message "`nNo valid certificates available to install."
            Read-Host "`nPress Enter to return to the main menu"
            return
        }
        # Display certificate selection menu
        Write-Information -MessageData "Select the certificate you want to install:" -InformationAction Continue
        for ($i = 0; $i -lt $certs.Count; $i++) {
            $cert = $certs[$i]
            $expiryInfo = ""
            if ($cert.Certificate) {
                $daysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                $expiryInfo = " (expires in $daysUntilExpiry days)"
                if ($daysUntilExpiry -le 7) {
                    Write-Warning -Message "$($i + 1)) $($cert.MainDomain)$expiryInfo"
                } else {
                    Write-Information -MessageData "$($i + 1)) $($cert.MainDomain)$expiryInfo" -InformationAction Continue
                }
            } else {
                Write-Information -MessageData "$($i + 1)) $($cert.MainDomain)$expiryInfo" -InformationAction Continue
            }
        }
        Write-Information -MessageData "0) Back to main menu" -InformationAction Continue
        $selection = Get-ValidatedInput -Prompt "`nEnter your choice (0-$($certs.Count))" -ValidOptions (0..$certs.Count)
        if ($selection -eq 0) {
            return
        } else {
            $PACertificate = $certs[$selection - 1]
        }
    }
    # Display certificate information
    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Write-Host -Object "CERTIFICATE INSTALLATION" -ForegroundColor Cyan
    Write-Host -Object "="*70 -ForegroundColor Cyan
    Write-Host -Object "Selected Certificate: $($PACertificate.MainDomain)" -ForegroundColor White
    if ($PACertificate.Certificate) {
        Write-Warning -Message "`nCertificate Details:"
        Write-Host -Object "  Subject: $($PACertificate.Certificate.Subject)"
        Write-Host -Object "  Issuer: $($PACertificate.Certificate.Issuer)"
        Write-Host -Object "  Valid From: $($PACertificate.Certificate.NotBefore)"
        Write-Host -Object "  Valid Until: $($PACertificate.Certificate.NotAfter)"
        Write-Host -Object "  Thumbprint: $($PACertificate.Certificate.Thumbprint)"
        # Show expiry warning if needed
        $daysUntilExpiry = ($PACertificate.Certificate.NotAfter - (Get-Date)).Days
        if ($daysUntilExpiry -le 30) {
            Write-Warning -Message "  This certificate expires in $daysUntilExpiry days!"
        }
    }
    # Main installation menu loop
    $installed = $false
    while (-not $installed) {
        Write-Host -Object "`n" + "-"*70 -ForegroundColor Gray
        Write-Warning -Message "INSTALLATION OPTIONS"
        Write-Host -Object "-"*70 -ForegroundColor Gray
        Write-Host -Object "1) Install to Management Server (Windows Certificate Store)"
        Write-Host -Object "2) Install to Recording Server (PEM Files)"
        Write-Host -Object "3) Export as PFX File"
        Write-Host -Object "4) Export Multiple Formats"
        Write-Host -Object "5) Installation Options"
        Write-Host -Object "0) Back to main menu"
        $installChoice = Get-ValidatedInput -Prompt "`nSelect installation method (0-5)" -ValidOptions (0..5)
        switch ($installChoice) {
            0 {
                return
            }
            1 {
                # Management Server Installation
                Write-Host -Object "`nInstalling certificate to Management Server..." -ForegroundColor Cyan
                Write-ProgressHelper -Activity "Certificate Installation" -Status "Preparing Management Server installation..." -PercentComplete 25
                # Handle exportable key preference
                $exportableChoice = $null
                if ($null -ne $settings.AlwaysExportable) {
                    $usePreference = Read-Host "`nUse saved preference (Private Key Exportable: $($settings.AlwaysExportable))? (Y/N/0 to go back)"
                    if ($usePreference -eq '0') { continue }
                    if ($usePreference -match '^[Yy]$') {
                        $exportableChoice = if ($settings.AlwaysExportable) { 'Y' } else { 'N' }
                    }
                }
                if (-not $exportableChoice) {
                    $exportableChoice = Read-Host "`nMake private key exportable? (Y/N/0 to go back)"
                    if ($exportableChoice -eq '0') { continue }
                    # Offer to save preference
                    $savePreference = Read-Host "Save this as your default preference? (Y/N)"
                    if ($savePreference -match '^[Yy]$') {
                        $settings.AlwaysExportable = $exportableChoice -match '^[Yy]$'
                        Save-ScriptSettings -Settings $settings
                        Write-Information -MessageData "Preference saved." -InformationAction Continue
                    }
                }
                $isNotExportable = $exportableChoice -match '^[Nn]$'
                Write-ProgressHelper -Activity "Certificate Installation" -Status "Installing to certificate store..." -PercentComplete 50
                try {
                    # Prepare installation parameters
                    $installParams = @{
                        PACertificate = $PACertificate
                        StoreLocation = 'LocalMachine'
                        Verbose       = $true
                    }
                    if ($isNotExportable) {
                        $installParams['NotExportable'] = $true
                    }
                    # Install with retry logic
                    Invoke-WithRetry -ScriptBlock {
                        Install-PACertificate @installParams
                    } -MaxAttempts 3 -InitialDelaySeconds 2 `
                      -OperationName "Certificate installation to LocalMachine store" `
                      -SuccessCondition { $? }
                    Write-ProgressHelper -Activity "Certificate Installation" -Status "Installation complete" -PercentComplete 100
                    # Verify installation
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                    $store.Open("ReadOnly")
                    $installedCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $PACertificate.Certificate.Thumbprint }
                    $store.Close()
                    if ($installedCert) {
                        Write-Information -MessageData "`n✓ Certificate installed to LocalMachine\My store" -InformationAction Continue
                        Write-Warning -Message "`nInstallation Details:"
                        Write-Host -Object "  Store: LocalMachine\My"
                        Write-Host -Object "  Private Key Exportable: $(-not $isNotExportable)"
                        Write-Host -Object "  Thumbprint: $($PACertificate.Certificate.Thumbprint)"
                        Write-Host -Object "  Subject: $($PACertificate.Certificate.Subject)"
                        Write-Log "Certificate installed to LocalMachine\My for $($PACertificate.MainDomain)"
                        $installed = $true
                    } else {
                        throw "Certificate installation verification failed"
                    }
                } catch {
                    $msg = "Failed to install certificate to LocalMachine\My store: $($_.Exception.Message)"
                    Write-Error -Message $msg
                    Write-Log $msg -Level 'Error'
                    Write-Warning -Message "`nTroubleshooting suggestions:"
                    Write-Host -Object "• Ensure you're running as Administrator"
                    Write-Host -Object "• Check if the certificate store is accessible"
                    Write-Host -Object "• Verify the certificate is valid and not corrupted"
                    Read-Host "`nPress Enter to continue"
                } finally {
                    Write-Progress -Activity "Certificate Installation" -Completed
                }
            }
            2 {
                # Recording Server Installation
                Write-Host -Object "`nInstalling certificate to Recording Server..." -ForegroundColor Cyan
                Write-ProgressHelper -Activity "Certificate Installation" -Status "Locating Recording Server directory..." -PercentComplete 25
                $certDir = Get-RSCertFolder
                if ($null -eq $certDir) {
                    Write-Error -Message "Recording Server certificate directory not found."
                    Read-Host "`nPress Enter to continue"
                    continue
                }
                Write-Information -MessageData "Using Recording Server directory: $certDir" -InformationAction Continue
                Write-ProgressHelper -Activity "Certificate Installation" -Status "Extracting certificate content..." -PercentComplete 40
                # Extract certificate and key content
                $pemContent = Get-CertificatePEMContent -Certificate $PACertificate -IncludeKey
                if (-not $pemContent.Success) {
                    Write-Error -Message "Failed to extract certificate content: $($pemContent.ErrorMessage)"
                    Read-Host "`nPress Enter to continue"
                    continue
                }
                Write-ProgressHelper -Activity "Certificate Installation" -Status "Saving PEM files..." -PercentComplete 60
                try {
                    # Save PEM files with auto-versioning
                    $result = Save-PEMFiles -directory $certDir `
                        -certContent $pemContent.CertContent `
                        -keyContent $pemContent.KeyContent
                    if ($result) {
                        Write-ProgressHelper -Activity "Certificate Installation" -Status "Installation complete" -PercentComplete 100
                        Write-Information -MessageData "`n✓ Certificate and private key saved" -InformationAction Continue
                        Write-Warning -Message "`nFile Details:"
                        Write-Host -Object "  Certificate: $($result.CertFile)"
                        Write-Host -Object "  Private Key: $($result.KeyFile)"
                        # Show file sizes for verification
                        $certSize = (Get-Item $result.CertFile).Length
                        $keySize = (Get-Item $result.KeyFile).Length
                        Write-Host -Object "  Certificate Size: $certSize bytes"
                        Write-Host -Object "  Private Key Size: $keySize bytes"
                        Write-Log "Certificate and private key saved to Recording Server directory"
                        Write-Host -Object "`nNext Steps:" -ForegroundColor Cyan
                        Write-Host -Object "• Restart the Recording Server service"
                        Write-Host -Object "• Update configuration files with new certificate paths"
                        Write-Host -Object "• Test HTTPS connectivity"
                        $installed = $true
                    }
                } catch {
                    Write-Error -Message "Failed to save PEM files: $($_.Exception.Message)"
                    Read-Host "`nPress Enter to continue"
                } finally {
                    Write-Progress -Activity "Certificate Installation" -Completed
                }
            }
            3 {
                # PFX Export
                Write-Host -Object "`nExporting certificate as PFX file..." -ForegroundColor Cyan
                Write-ProgressHelper -Activity "Certificate Export" -Status "Configuring export options..." -PercentComplete 25
                # Determine export path
                $defaultPath = $settings.DefaultPFXLocation
                if (-not $defaultPath) {
                    $defaultPath = [Environment]::GetFolderPath("Desktop")
                }
                $defaultFileName = "$($PACertificate.MainDomain.Replace('*', 'wildcard')).pfx"
                $defaultCertPath = Join-Path $defaultPath $defaultFileName
                $certPath = Read-Host "`nEnter path for PFX file (default: $defaultCertPath) or 0 to go back"
                if ($certPath -eq '0') { continue }
                if (-not $certPath) { $certPath = $defaultCertPath }
                # Validate and create directory if needed
                $certDir = Split-Path $certPath -Parent
                if (-not (Test-Path $certDir)) {
                    try {
                        New-Item -ItemType Directory -Path $certDir -Force | Out-Null
                        Write-Information -MessageData "Created directory: $certDir" -InformationAction Continue
                    } catch {
                        Write-Error -Message "Failed to create directory: $certDir"
                        Read-Host "`nPress Enter to continue"
                        continue
                    }
                }
                # Check if file already exists
                if ((Test-Path $certPath) -and -not $Force) {
                    $overwrite = Read-Host "`nFile exists. Overwrite? (Y/N)"
                    if ($overwrite -notmatch '^[Yy]$') { continue }
                }
                Write-ProgressHelper -Activity "Certificate Export" -Status "Setting password..." -PercentComplete 40
                # Get password for PFX
                $certPassword = Read-Host "`nEnter password for PFX file (leave blank for no password) or 0 to go back" -AsSecureString
                $passwordString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($certPassword))
                if ($passwordString -eq '0') { continue }
                Write-ProgressHelper -Activity "Certificate Export" -Status "Exporting certificate..." -PercentComplete 60
                try {
                    # Export with retry logic
                    Invoke-WithRetry -ScriptBlock {
                        Export-PACertificate -MainDomain $PACertificate.MainDomain -Type PFX -Path $certPath -Password $certPassword
                    } -MaxAttempts 3 -InitialDelaySeconds 2 `
                      -OperationName "PFX export" `
                      -SuccessCondition { Test-Path $certPath }
                    Write-ProgressHelper -Activity "Certificate Export" -Status "Export complete" -PercentComplete 100
                    # Verify export and show details
                    $fileInfo = Get-Item $certPath
                    Write-Information -MessageData "`n✓ Certificate exported" -InformationAction Continue
                    Write-Warning -Message "`nExport Details:"
                    Write-Host -Object "  File: $certPath"
                    Write-Host -Object "  Size: $($fileInfo.Length) bytes"
                    Write-Host -Object "  Created: $($fileInfo.CreationTime)"
                    Write-Host -Object "  Password Protected: $(if ($passwordString) { 'Yes' } else { 'No' })"
                    Write-Log "Certificate exported as PFX to $certPath"
                    # Update default path setting
                    $savePathPreference = Read-Host "`nSave this directory as default PFX location? (Y/N)"
                    if ($savePathPreference -match '^[Yy]$') {
                        $settings.DefaultPFXLocation = Split-Path $certPath -Parent
                        Save-ScriptSettings -Settings $settings
                        Write-Information -MessageData "Default PFX location updated." -InformationAction Continue
                    }
                    $installed = $true
                } catch {
                    $msg = "Failed to export certificate as PFX: $($_.Exception.Message)"
                    Write-Error -Message $msg
                    Write-Log $msg -Level 'Error'
                    Read-Host "`nPress Enter to continue"
                } finally {
                    Write-Progress -Activity "Certificate Export" -Completed
                }
            }
            4 {
                # Multiple Format Export
                Write-Host -Object "`nExporting certificate in multiple formats..." -ForegroundColor Cyan
                $exportDir = Read-Host "`nEnter directory for exports (default: Desktop) or 0 to go back"
                if ($exportDir -eq '0') { continue }
                if (-not $exportDir) {
                    $exportDir = [Environment]::GetFolderPath("Desktop")
                }
                # Create export directory if needed
                if (-not (Test-Path $exportDir)) {
                    try {
                        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
                        Write-Information -MessageData "Created directory: $exportDir" -InformationAction Continue
                    } catch {
                        Write-Error -Message "Failed to create directory: $exportDir"
                        Read-Host "`nPress Enter to continue"
                        continue
                    }
                }
                $baseName = $PACertificate.MainDomain.Replace("*", "wildcard").Replace(".", "_")
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                Write-ProgressHelper -Activity "Multi-Format Export" -Status "Starting export..." -PercentComplete 10
                try {
                    $exportResults = @()
                    # Export PFX
                    Write-ProgressHelper -Activity "Multi-Format Export" -Status "Exporting PFX..." -PercentComplete 25
                    $pfxPath = Join-Path $exportDir "${baseName}_${timestamp}.pfx"
                    $password = Read-Host "Enter password for PFX (leave blank for no password)" -AsSecureString
                    Export-PACertificate -MainDomain $PACertificate.MainDomain -Type PFX -Path $pfxPath -Password $password
                    $exportResults += "PFX: $pfxPath"
                    # Export individual PEM files
                    Write-ProgressHelper -Activity "Multi-Format Export" -Status "Exporting PEM files..." -PercentComplete 50
                    $pemContent = Get-CertificatePEMContent -Certificate $PACertificate -IncludeKey
                    if ($pemContent.Success) {
                        $certPemPath = Join-Path $exportDir "${baseName}_${timestamp}_cert.pem"
                        $keyPemPath = Join-Path $exportDir "${baseName}_${timestamp}_key.pem"
                        Set-Content -Path $certPemPath -Value $pemContent.CertContent -Encoding ASCII
                        Set-Content -Path $keyPemPath -Value $pemContent.KeyContent -Encoding ASCII
                        $exportResults += "Certificate PEM: $certPemPath"
                        $exportResults += "Private Key PEM: $keyPemPath"
                    }
                    # Export full chain if available
                    Write-ProgressHelper -Activity "Multi-Format Export" -Status "Exporting full chain..." -PercentComplete 75
                    if ($PACertificate.FullChainFile -and (Test-Path $PACertificate.FullChainFile)) {
                        $fullChainPath = Join-Path $exportDir "${baseName}_${timestamp}_fullchain.pem"
                        Copy-Item -Path $PACertificate.FullChainFile -Destination $fullChainPath
                        $exportResults += "Full Chain PEM: $fullChainPath"
                    }
                    # Create metadata file
                    Write-ProgressHelper -Activity "Multi-Format Export" -Status "Creating metadata..." -PercentComplete 90
                    $metadataPath = Join-Path $exportDir "${baseName}_${timestamp}_metadata.json"
                    $metadata = @{
                        Domain = $PACertificate.MainDomain
                        AllDomains = $PACertificate.AllSANs
                        Subject = $PACertificate.Certificate.Subject
                        Issuer = $PACertificate.Certificate.Issuer
                        Thumbprint = $PACertificate.Certificate.Thumbprint
                        ValidFrom = $PACertificate.Certificate.NotBefore
                        ValidUntil = $PACertificate.Certificate.NotAfter
                        ExportDate = Get-Date
                        ExportedFiles = $exportResults
                    }
                    $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath
                    $exportResults += "Metadata: $metadataPath"
                    Write-ProgressHelper -Activity "Multi-Format Export" -Status "Export complete" -PercentComplete 100
                    Write-Host -Object "`n✓ Multi-format export completed" -ForegroundColor Green
                    Write-Warning -Message "`nExported Files:"
                    $exportResults | ForEach-Object { Write-Host -Object "  $_" }
                    Write-Log "Multi-format export completed for $($PACertificate.MainDomain)"
                    $installed = $true
                } catch {
                    Write-Error -Message "Multi-format export failed: $_"
                    Write-Log "Multi-format export failed for $($PACertificate.MainDomain): $_" -Level 'Error'
                    Read-Host "`nPress Enter to continue"
                } finally {
                    Write-Progress -Activity "Multi-Format Export" -Completed
                }
            }
            5 {
                # Installation Options
                Write-Host -Object "`nInstallation Options:" -ForegroundColor Cyan
                Write-Host -Object "1) Install to custom certificate store"
                Write-Host -Object "2) Install with custom friendly name"
                Write-Host -Object "3) Install with backup creation"
                Write-Host -Object "4) Configure IIS site binding"
                Write-Host -Object "5) Schedule automatic reinstallation"
                Write-Host -Object "0) Back to main menu"
                $installChoice = Get-ValidatedInput -Prompt "`nSelect installation option (0-5)" -ValidOptions (0..5)
                switch ($installChoice) {
                    0 { continue }
                    1 {
                        # Custom certificate store
                        Write-Warning -Message "`nCustom Certificate Store Installation:"
                        Write-Host -Object "1) LocalMachine\My (Personal)"
                        Write-Host -Object "2) LocalMachine\WebHosting"
                        Write-Host -Object "3) CurrentUser\My (Personal)"
                        Write-Host -Object "4) LocalMachine\TrustedPeople"
                        Write-Host -Object "5) Custom store name"
                        $storeChoice = Get-ValidatedInput -Prompt "`nSelect store (1-5)" -ValidOptions (1..5)
                        $storeLocation = "LocalMachine"
                        $storeName = "My"
                        switch ($storeChoice) {
                            1 { $storeLocation = "LocalMachine"; $storeName = "My" }
                            2 { $storeLocation = "LocalMachine"; $storeName = "WebHosting" }
                            3 { $storeLocation = "CurrentUser"; $storeName = "My" }
                            4 { $storeLocation = "LocalMachine"; $storeName = "TrustedPeople" }
                            5 {
                                $customStore = Read-Host "Enter custom store name"
                                if ($customStore) { $storeName = $customStore }
                            }
                        }
                        try {
                            Install-PACertificate -PACertificate $PACertificate -StoreLocation $storeLocation -StoreName $storeName -Verbose
                            Write-Information -MessageData "✓ Certificate installed to $storeLocation\$storeName" -InformationAction Continue
                            Write-Log "Certificate installed to custom store $storeLocation\$storeName"
                            $installed = $true
                        } catch {
                            Write-Error -Message "Failed to install to custom store: $_"
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                    2 {
                        # Custom friendly name
                        $friendlyName = Read-Host "`nEnter friendly name for the certificate (or 0 to cancel)"
                        if ($friendlyName -eq '0') { continue }
                        if ($friendlyName) {
                            try {
                                # Install normally first
                                Install-PACertificate -PACertificate $PACertificate -StoreLocation LocalMachine -Verbose
                                # Update friendly name
                                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                                $store.Open("ReadWrite")
                                $cert = $store.Certificates | Where-Object { $_.Thumbprint -eq $PACertificate.Certificate.Thumbprint }
                                if ($cert) {
                                    $cert.FriendlyName = $friendlyName
                                    Write-Information -MessageData "✓ Certificate installed with friendly name: $friendlyName" -InformationAction Continue
                                    Write-Log "Certificate installed with friendly name: $friendlyName"
                                    $installed = $true
                                } else {
                                    throw "Certificate not found after installation"
                                }
                                $store.Close()
                            } catch {
                                Write-Error -Message "Failed to set friendly name: $_"
                                Read-Host "`nPress Enter to continue"
                            }
                        }
                    }
                    3 {
                        # Backup and install
                        Write-Warning -Message "`nCreating backup before installation..."
                        $backupDir = Read-Host "Enter backup directory (default: Desktop\CertBackup, or 0 to cancel)"
                        if ($backupDir -eq '0') { continue }
                        if (-not $backupDir) {
                            $backupDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "CertBackup"
                        }
                        if (-not (Test-Path $backupDir)) {
                            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                        }
                        try {
                            # Create backup
                            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                            $backupPath = Join-Path $backupDir "backup_${timestamp}.pfx"
                            $backupPassword = Read-Host "Enter backup password" -AsSecureString
                            Export-PACertificate -MainDomain $PACertificate.MainDomain -Type PFX -Path $backupPath -Password $backupPassword
                            Write-Information -MessageData "✓ Backup created: $backupPath" -InformationAction Continue
                            # Install certificate
                            Install-PACertificate -PACertificate $PACertificate -StoreLocation LocalMachine -Verbose
                            Write-Information -MessageData "✓ Certificate installed" -InformationAction Continue
                            Write-Log "Certificate installed with backup created"
                            $installed = $true
                        } catch {
                            Write-Error -Message "Backup and install failed: $_"
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                    4 {
                        # IIS site binding
                        if (Get-Module -ListAvailable -Name WebAdministration) {
                            Import-Module WebAdministration
                            $sites = Get-Website
                            if ($sites) {
                                Write-Warning -Message "`nAvailable IIS Sites:"
                                for ($i = 0; $i -lt $sites.Count; $i++) {
                                    Write-Host -Object "$($i + 1)) $($sites[$i].Name) - $($sites[$i].State)"
                                }
                                $siteChoice = Get-ValidatedInput -Prompt "`nSelect site (1-$($sites.Count))" -ValidOptions (1..$sites.Count)
                                $selectedSite = $sites[$siteChoice - 1]
                                try {
                                    # Install certificate first
                                    Install-PACertificate -PACertificate $PACertificate -StoreLocation LocalMachine -Verbose
                                    # Remove existing HTTPS binding if it exists
                                    $existingBinding = Get-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -ErrorAction SilentlyContinue
                                    if ($existingBinding) {
                                        Remove-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -Confirm:$false
                                        Write-Warning -Message "Removed existing HTTPS binding"
                                    }
                                    # Create new HTTPS binding
                                    New-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -SslFlags 1
                                    # Bind certificate
                                    $binding = Get-WebBinding -Name $selectedSite.Name -Protocol https -Port 443
                                    $binding.AddSslCertificate($PACertificate.Certificate.Thumbprint, "my")
                                    Write-Information -MessageData "✓ Certificate bound to IIS site: $($selectedSite.Name)" -InformationAction Continue
                                    Write-Log "Certificate bound to IIS site: $($selectedSite.Name)"
                                    $installed = $true
                                } catch {
                                    Write-Error -Message "Failed to configure IIS binding: $_"
                                    Read-Host "`nPress Enter to continue"
                                }
                            } else {
                                Write-Warning -Message "No IIS sites found."
                                Read-Host "`nPress Enter to continue"
                            }
                        } else {
                            Write-Warning -Message "IIS WebAdministration module not available."
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                    5 {
                        # Schedule automatic reinstallation
                        Write-Warning -Message "`nScheduling automatic certificate reinstallation..."
                        $taskName = "Certificate Auto-Reinstall - $($PACertificate.MainDomain)"
                        $scriptContent = @"
# Auto-reinstall script for $($PACertificate.MainDomain)
Import-Module Posh-ACME -Force
try {
    `$cert = Get-PACertificate -MainDomain "$($PACertificate.MainDomain)"
    if (`$cert) {
        Install-PACertificate -PACertificate `$cert -StoreLocation LocalMachine
        Write-EventLog -LogName Application -Source "Certificate Management" -EventId 1001 -Message "Certificate auto-reinstalled for $($PACertificate.MainDomain)"
    }
} catch {
    Write-EventLog -LogName Application -Source "Certificate Management" -EventId 1002 -EntryType Error -Message "Certificate auto-reinstall failed for $($PACertificate.MainDomain): `$_"
}
"@
                        $scriptPath = Join-Path $env:TEMP "reinstall_$($PACertificate.MainDomain.Replace('*','wildcard').Replace('.','_')).ps1"
                        $scriptContent | Set-Content -Path $scriptPath
                        try {
                            $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
                            $trigger = New-ScheduledTaskTrigger -Weekly -At 3am -DaysOfWeek Sunday
                            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                            $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
                            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force
                            Write-Information -MessageData "✓ Automatic reinstallation scheduled for $($PACertificate.MainDomain)" -InformationAction Continue
                            Write-Host -Object "  Task: $taskName" -ForegroundColor Cyan
                            Write-Host -Object "  Schedule: Weekly on Sundays at 3:00 AM" -ForegroundColor Cyan
                            Write-Log "Automatic reinstallation scheduled for $($PACertificate.MainDomain)"
                            $installed = $true
                        } catch {
                            Write-Error -Message "Failed to create scheduled task: $_"
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                }
            }
        }
    }
    # Post-installation actions and verification
    if ($installed) {
        Write-Information -MessageData "`n" + "="*70 -InformationAction Continue
        Write-Information -MessageData "INSTALLATION COMPLETED!" -InformationAction Continue
        Write-Information -MessageData "="*70 -InformationAction Continue
        # Post-installation menu
        Write-Host -Object "`nPost-Installation Options:" -ForegroundColor Yellow
        Write-Host -Object "1) Test certificate installation"
        Write-Host -Object "2) View detailed certificate information"
        Write-Host -Object "3) Configure monitoring and alerts"
        Write-Host -Object "4) Generate installation report"
        Write-Host -Object "5) Configure application bindings"
        Write-Host -Object "6) Verify certificate chain"
        Write-Host -Object "0) Continue to main menu"
        $postChoice = Get-ValidatedInput -Prompt "`nSelect option (0-6)" -ValidOptions (0..6)
        switch ($postChoice) {
            1 {
                # Certificate testing
                Write-Host -Object "`nRunning certificate tests..." -ForegroundColor Cyan
                Write-ProgressHelper -Activity "Certificate Testing" -Status "Initializing tests..." -PercentComplete 10
                $testResults = @()
                $allTestsPassed = $true
                try {
                    # Test 1: Certificate store presence
                    Write-ProgressHelper -Activity "Certificate Testing" -Status "Checking certificate store..." -PercentComplete 25
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                    $store.Open("ReadOnly")
                    $installedCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $PACertificate.Certificate.Thumbprint }
                    $store.Close()
                    if ($installedCert) {
                        Write-Information -MessageData "✓ Certificate found in LocalMachine\My store" -InformationAction Continue
                        $testResults += @{ Test = "Certificate Store"; Result = "PASS"; Details = "Found in LocalMachine\My" }
                        # Test 2: Private key availability
                        Write-ProgressHelper -Activity "Certificate Testing" -Status "Checking private key..." -PercentComplete 40
                        if ($installedCert.HasPrivateKey) {
                            Write-Information -MessageData "✓ Private key is available and accessible" -InformationAction Continue
                            $testResults += @{ Test = "Private Key"; Result = "PASS"; Details = "Available and accessible" }
                        } else {
                            Write-Error -Message "✗ Private key is not available"
                            $testResults += @{ Test = "Private Key"; Result = "FAIL"; Details = "Not available" }
                            $allTestsPassed = $false
                        }
                        # Test 3: Certificate validity period
                        Write-ProgressHelper -Activity "Certificate Testing" -Status "Checking validity..." -PercentComplete 55
                        $now = Get-Date
                        if ($installedCert.NotAfter -gt $now -and $installedCert.NotBefore -le $now) {
                            $daysValid = ($installedCert.NotAfter - $now).Days
                            Write-Information -MessageData "✓ Certificate is currently valid ($daysValid days remaining)" -InformationAction Continue
                            $testResults += @{ Test = "Validity Period"; Result = "PASS"; Details = "$daysValid days remaining" }
                        } else {
                            Write-Error -Message "✗ Certificate is not valid (expired or not yet valid)"
                            $testResults += @{ Test = "Validity Period"; Result = "FAIL"; Details = "Expired or not yet valid" }
                            $allTestsPassed = $false
                        }
                        # Test 4: Certificate chain validation
                        Write-ProgressHelper -Activity "Certificate Testing" -Status "Validating certificate chain..." -PercentComplete 70
                        try {
                            $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                            $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
                            $chainValid = $chain.Build($installedCert)
                            if ($chainValid) {
                                Write-Information -MessageData "✓ Certificate chain is valid and trusted" -InformationAction Continue
                                $testResults += @{ Test = "Chain Validation"; Result = "PASS"; Details = "Valid and trusted" }
                            } else {
                                $chainErrors = $chain.ChainStatus | ForEach-Object { $_.Status } | Sort-Object -Unique
                                Write-Error -Message "⚠ Certificate chain has warnings: $($chainErrors -join ', ')" -ForegroundColor Yellow
                                $testResults += @{ Test = "Chain Validation"; Result = "WARNING"; Details = $chainErrors -join ', ' }
                            }
                            $chain.Dispose()
                        } catch {
                            Write-Error -Message "✗ Certificate chain validation failed: $_"
                            $testResults += @{ Test = "Chain Validation"; Result = "FAIL"; Details = $_.Exception.Message }
                            $allTestsPassed = $false
                        }
                        # Test 5: Key usage validation
                        Write-ProgressHelper -Activity "Certificate Testing" -Status "Checking key usage..." -PercentComplete 85
                        $keyUsageExt = $installedCert.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.15" }
                        if ($keyUsageExt) {
                            Write-Information -MessageData "✓ Key usage extension present: $($keyUsageExt.Format($false))" -InformationAction Continue
                            $testResults += @{ Test = "Key Usage"; Result = "PASS"; Details = $keyUsageExt.Format($false) }
                        } else {
                            Write-Warning -Message "⚠ Key usage extension not found"
                            $testResults += @{ Test = "Key Usage"; Result = "WARNING"; Details = "Extension not found" }
                        }
                    } else {
                        Write-Error -Message "✗ Certificate not found in certificate store"
                        $testResults += @{ Test = "Certificate Store"; Result = "FAIL"; Details = "Not found in LocalMachine\My" }
                        $allTestsPassed = $false
                    }
                } catch {
                    Write-Error -Message "✗ Certificate testing failed: $_"
                    $testResults += @{ Test = "Certificate Test"; Result = "ERROR"; Details = $_.Exception.Message }
                    $allTestsPassed = $false
                }
                Write-ProgressHelper -Activity "Certificate Testing" -Status "Tests complete" -PercentComplete 100
                Write-Progress -Activity "Certificate Testing" -Completed
                # Display test summary
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "CERTIFICATE TEST SUMMARY" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan
                foreach ($result in $testResults) {
                    $color = switch ($result.Result) {
                        "PASS" { "Green" }
                        "WARNING" { "Yellow" }
                        "FAIL" { "Red" }
                        "ERROR" { "Red" }
                    }
                    Write-Host -Object "[$($result.Result.PadRight(7))] $($result.Test): $($result.Details)" -ForegroundColor $color
                }
                $overallStatus = if ($allTestsPassed) { "ALL TESTS PASSED" } else { "ISSUES DETECTED" }
                $statusColor = if ($allTestsPassed) { "Green" } else { "Red" }
                Write-Host -Object "`nOverall Status: $overallStatus" -ForegroundColor $statusColor
                Read-Host "`nPress Enter to continue"
            }
            2 {
                # Certificate information display
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
                if ($PACertificate.Certificate.Extensions) {
                    Write-Warning -Message "`nCertificate Extensions:"
                    # Subject Alternative Names
                    $sanExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.17" }
                    if ($sanExt) {
                        Write-Host -Object "Subject Alternative Names:"
                        $sanExt.Format($false) -split ", " | ForEach-Object { Write-Host -Object "  $_" }
                    }
                    # Key Usage
                    $keyUsageExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.15" }
                    if ($keyUsageExt) {
                        Write-Host -Object "Key Usage: $($keyUsageExt.Format($false))"
                    }
                    # Extended Key Usage
                    $extKeyUsageExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.37" }
                    if ($extKeyUsageExt) {
                        Write-Host -Object "Extended Key Usage: $($extKeyUsageExt.Format($false))"
                    }
                    # Basic Constraints
                    $basicConstraintsExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.19" }
                    if ($basicConstraintsExt) {
                        Write-Host -Object "Basic Constraints: $($basicConstraintsExt.Format($false))"
                    }
                    # Authority Information Access
                    $aiaExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "1.3.6.1.5.5.7.1.1" }
                    if ($aiaExt) {
                        Write-Host -Object "Authority Information Access: $($aiaExt.Format($false))"
                    }
                    # CRL Distribution Points
                    $crlExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.31" }
                    if ($crlExt) {
                        Write-Host -Object "CRL Distribution Points: $($crlExt.Format($false))"
                    }
                }
                Write-Warning -Message "`nFile Locations:"
                if ($PACertificate.CertFile) { Write-Host -Object "Certificate File: $($PACertificate.CertFile)" }
                if ($PACertificate.KeyFile) { Write-Host -Object "Private Key File: $($PACertificate.KeyFile)" }
                if ($PACertificate.ChainFile) { Write-Host -Object "Chain File: $($PACertificate.ChainFile)" }
                if ($PACertificate.FullChainFile) { Write-Host -Object "Full Chain File: $($PACertificate.FullChainFile)" }
                if ($PACertificate.PfxFile) { Write-Host -Object "PFX File: $($PACertificate.PfxFile)" }
                Read-Host "`nPress Enter to continue"
            }
            3 {
                # Configure monitoring and alerts
                Write-Host -Object "`nConfiguring certificate monitoring and alerts..." -ForegroundColor Cyan
                $config = Get-RenewalConfig
                Write-Warning -Message "`nCurrent monitoring settings:"
                Write-Warning -Message "Expiry warning threshold: $($config.RenewalThresholdDays) days"
                Write-Host -Object "Email notifications: $($config.EmailNotifications)"
                if ($config.EmailNotifications) {
                    Write-Host -Object "Notification email: $($config.NotificationEmail)"
                }
                $changeSettings = Read-Host "`nModify monitoring settings? (Y/N)"
                if ($changeSettings -match '^[Yy]') {
                    $thresholdDays = Read-Host "Enter expiry warning threshold in days (current: $($config.RenewalThresholdDays))"
                    if ($thresholdDays -and $thresholdDays -match '^\d+') {
                        $config.RenewalThresholdDays = [int]$thresholdDays
                    }
                    $enableEmail = Read-Host "Enable email notifications? (Y/N)"
                    if ($enableEmail -match '^[Yy]') {
                        $config.EmailNotifications = $true
                        $emailAddress = Read-Host "Enter notification email address"
                        if ($emailAddress -and (Test-ValidEmail -Email $emailAddress)) {
                            $config.NotificationEmail = $emailAddress
                        }
                    } else {
                        $config.EmailNotifications = $false
                    }
                    Save-RenewalConfig -Config $config
                    Write-Information -MessageData "✓ Monitoring settings updated" -InformationAction Continue
                }
                # Create monitoring script
                $createScript = Read-Host "`nCreate monitoring script? (Y/N)"
                if ($createScript -match '^[Yy]') {
                    $monitorScript = @"
# Certificate monitoring script for $($PACertificate.MainDomain)
# Generated: $(Get-Date)
Import-Module Posh-ACME -Force
try {
    `$cert = Get-PACertificate -MainDomain "$($PACertificate.MainDomain)"
    if (`$cert -and `$cert.Certificate) {
        `$daysUntilExpiry = (`$cert.Certificate.NotAfter - (Get-Date)).Days
        `$threshold = $($config.RenewalThresholdDays)
        if (`$daysUntilExpiry -le `$threshold) {
            `$message = "Certificate $($PACertificate.MainDomain) expires in `$daysUntilExpiry days (threshold: `$threshold days)"
            # Log to Windows Event Log
            try {
                New-EventLog -LogName Application -Source "Certificate Management" -ErrorAction SilentlyContinue
                Write-EventLog -LogName Application -Source "Certificate Management" -EventId 2001 -EntryType Warning -Message `$message
            } catch {
                Write-Warning -Message "Warning: Could not write to event log: `$_"
            }
            # Output for scheduled task
            Write-Host -Object `$message
            # Email notification (if configured)
            # Add your email sending logic here
        } else {
            Write-Host -Object "Certificate $($PACertificate.MainDomain) is valid for `$daysUntilExpiry more days"
        }
    } else {
        Write-Error -Message "Error: Certificate $($PACertificate.MainDomain) not found or invalid"
        Write-EventLog -LogName Application -Source "Certificate Management" -EventId 2002 -EntryType Error -Message "Certificate $($PACertificate.MainDomain) not found or invalid"
    }
} catch {
    `$errorMessage = "Certificate monitoring failed for $($PACertificate.MainDomain): `$_"
    Write-Host -Object `$errorMessage
    Write-EventLog -LogName Application -Source "Certificate Management" -EventId 2003 -EntryType Error -Message `$errorMessage
}
"@
                    $monitorPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "monitor_$($PACertificate.MainDomain.Replace('*','wildcard').Replace('.','_')).ps1"
                    $monitorScript | Set-Content -Path $monitorPath
                    Write-Information -MessageData "✓ Monitoring script created: $monitorPath" -InformationAction Continue
                    # Offer to create scheduled task
                    $createTask = Read-Host "Create scheduled task to run monitoring script daily? (Y/N)"
                    if ($createTask -match '^[Yy]') {
                        try {
                            $taskName = "Certificate Monitor - $($PACertificate.MainDomain)"
                            $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -File `"$monitorPath`""
                            $trigger = New-ScheduledTaskTrigger -Daily -At 9am
                            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
                            $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
                            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force
                            Write-Information -MessageData "✓ Monitoring task created: $taskName" -InformationAction Continue
                            Write-Host -Object "  Schedule: Daily at 9:00 AM" -ForegroundColor Cyan
                        } catch {
                            Write-Error -Message "Failed to create monitoring task: $_"
                        }
                    }
                }
                Write-Log "Monitoring configured for $($PACertificate.MainDomain)"
                Read-Host "`nPress Enter to continue"
            }
            4 {
                # Generate installation report
                Write-Host -Object "`nGenerating installation report..." -ForegroundColor Cyan
                $reportPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "certificate_installation_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                # Gather system information
                $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
                $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
                $report = @"
CERTIFICATE INSTALLATION REPORT
==============================================
Generated: $(Get-Date)
Report for: $($PACertificate.MainDomain)
SYSTEM INFORMATION
==================
Computer Name: $($computerInfo.Name)
Operating System: $($osInfo.Caption) $($osInfo.Version)
Architecture: $($osInfo.OSArchitecture)
PowerShell Version: $($PSVersionTable.PSVersion)
User Context: $($env:USERNAME)
Domain: $($env:USERDOMAIN)
CERTIFICATE DETAILS
===================
Main Domain: $($PACertificate.MainDomain)
All Domains: $($PACertificate.AllSANs -join ', ')
Subject: $($PACertificate.Certificate.Subject)
Issuer: $($PACertificate.Certificate.Issuer)
Serial Number: $($PACertificate.Certificate.SerialNumber)
Thumbprint: $($PACertificate.Certificate.Thumbprint)
Valid From: $($PACertificate.Certificate.NotBefore)
Valid Until: $($PACertificate.Certificate.NotAfter)
Days Until Expiry: $(($PACertificate.Certificate.NotAfter - (Get-Date)).Days)
CRYPTOGRAPHIC INFORMATION
=========================
Public Key Algorithm: $($PACertificate.Certificate.PublicKey.Oid.FriendlyName)
Key Size: $($PACertificate.Certificate.PublicKey.Key.KeySize) bits
Signature Algorithm: $($PACertificate.Certificate.SignatureAlgorithm.FriendlyName)
Has Private Key: $($PACertificate.Certificate.HasPrivateKey)
INSTALLATION DETAILS
====================
Installation Date: $(Get-Date)
Installation Method: Certificate Management System
Installed By: $($env:USERNAME)
Installation Location: LocalMachine\My Certificate Store
Private Key Exportable: $(-not $settings.AlwaysExportable -or $settings.AlwaysExportable)
FILE LOCATIONS
==============
Certificate File: $($PACertificate.CertFile)
Private Key File: $($PACertificate.KeyFile)
Chain File: $($PACertificate.ChainFile)
Full Chain File: $($PACertificate.FullChainFile)
PFX File: $($PACertificate.PfxFile)
SECURITY RECOMMENDATIONS
========================
1. Verify certificate is properly bound to applications
2. Ensure private key files have appropriate access permissions
3. Set up certificate expiry monitoring (recommended: 30 days before expiry)
4. Consider enabling Certificate Transparency monitoring
5. Regularly validate certificate chain integrity
6. Monitor for certificate-related security vulnerabilities
7. Keep certificate management tools updated
8. Document certificate renewal procedures
NEXT STEPS
==========
1. Test HTTPS connectivity to verify certificate is working correctly
2. Update application configurations to reference the new certificate
3. Set up automatic renewal monitoring and alerts
4. Configure application-specific certificate bindings (IIS, services, etc.)
5. Schedule regular certificate validation checks
6. Update documentation and runbooks
7. Notify relevant teams of certificate installation
8. Plan for next renewal cycle
TROUBLESHOOTING INFORMATION
===========================
Common Issues:
- Certificate not trusted: Verify certificate chain and root CA trust
- Private key not accessible: Check file permissions and certificate store access
- Application not using certificate: Verify application configuration and bindings
- Certificate appears expired: Check system clock and certificate validity period
Support Resources:
- Certificate management logs: $env:LOCALAPPDATA\Posh-ACME\certificate_script.log
- Windows Event Logs: Application log, source "Certificate Management"
- Posh-ACME documentation: https://poshac.me/
- Let's Encrypt documentation: https://letsencrypt.org/docs/
VERIFICATION CHECKLIST
======================
□ Certificate appears in LocalMachine\My certificate store
□ Private key is accessible and properly secured
□ Certificate chain validates correctly
□ Certificate is bound to target applications
□ HTTPS connectivity works correctly
□ Monitoring and alerts are configured
□ Documentation has been updated
□ Team notifications have been sent
END OF REPORT
=============
This report was generated by the Certificate Management System.
For questions or issues, refer to the troubleshooting section above.
"@
                Set-Content -Path $reportPath -Value $report -Encoding UTF8
                Write-Information -MessageData "✓ Installation report generated" -InformationAction Continue
                Write-Host -Object "  Report saved to: $reportPath" -ForegroundColor Cyan
                $openReport = Read-Host "`nOpen report in default text editor? (Y/N)"
                if ($openReport -match '^[Yy]') {
                    try {
                        Start-Process $reportPath
                    } catch {
                        Write-Host -Object "Could not open report automatically. File location: $reportPath"
                    }
                }
                Write-Log "Installation report generated: $reportPath"
                Read-Host "`nPress Enter to continue"
            }
            5 {
                # Configure application bindings
                Write-Host -Object "`nApplication Binding Configuration:" -ForegroundColor Cyan
                Write-Host -Object "1) Configure IIS website binding"
                Write-Host -Object "2) Configure Windows service binding"
                Write-Host -Object "3) Generate custom application configuration"
                Write-Host -Object "0) Skip application binding"
                $bindingChoice = Get-ValidatedInput -Prompt "`nSelect binding type (0-3)" -ValidOptions (0..3)
                switch ($bindingChoice) {
                    1 {
                        # IIS Website Binding (continued from advanced section)
                        if (Get-Module -ListAvailable -Name WebAdministration) {
                            Import-Module WebAdministration
                            $sites = Get-Website
                            if ($sites) {
                                Write-Warning -Message "`nAvailable IIS Sites:"
                                for ($i = 0; $i -lt $sites.Count; $i++) {
                                    $bindingInfo = $sites[$i].Bindings.Collection | Where-Object { $_.protocol -eq "https" }
                                    $httpsStatus = if ($bindingInfo) { "HTTPS Configured" } else { "HTTP Only" }
                                    Write-Host -Object "$($i + 1)) $($sites[$i].Name) - $($sites[$i].State) - $httpsStatus"
                                }
                                $siteChoice = Get-ValidatedInput -Prompt "`nSelect site to configure (1-$($sites.Count))" -ValidOptions (1..$sites.Count)
                                $selectedSite = $sites[$siteChoice - 1]
                                try {
                                    # Check if HTTPS binding already exists
                                    $existingBinding = Get-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -ErrorAction SilentlyContinue
                                    if ($existingBinding) {
                                        $replaceBinding = Read-Host "`nHTTPS binding already exists. Replace it? (Y/N)"
                                        if ($replaceBinding -match '^[Yy]') {
                                            Remove-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -Confirm:$false
                                            Write-Warning -Message "Existing HTTPS binding removed"
                                        } else {
                                            Read-Host "`nPress Enter to continue"
                                            continue
                                        }
                                    }
                                    # Create new HTTPS binding with certificate
                                    New-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -SslFlags 1
                                    # Associate certificate with binding
                                    $binding = Get-WebBinding -Name $selectedSite.Name -Protocol https -Port 443
                                    $binding.AddSslCertificate($PACertificate.Certificate.Thumbprint, "my")
                                    Write-Information -MessageData "✓ Certificate bound to IIS site: $($selectedSite.Name)" -InformationAction Continue
                                    Write-Host -Object "  Binding: HTTPS on port 443" -ForegroundColor Cyan
                                    Write-Host -Object "  Certificate: $($PACertificate.Certificate.Thumbprint)" -ForegroundColor Cyan
                                    # Test binding
                                    $testBinding = Read-Host "`nTest HTTPS binding? (Y/N)"
                                    if ($testBinding -match '^[Yy]') {
                                        try {
                                            $testUrl = "https://localhost"
                                            $response = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -SkipCertificateCheck -TimeoutSec 10
                                            Write-Information -MessageData "✓ HTTPS binding test successful (Status: $($response.StatusCode))" -InformationAction Continue
                                        } catch {
                                            Write-Warning -Message "HTTPS binding test failed: $($_.Exception.Message)"
                                            Write-Host -Object "This may be normal if the site requires specific host headers or has other configuration requirements." -ForegroundColor Gray
                                        }
                                    }
                                    Write-Log "Certificate bound to IIS site: $($selectedSite.Name)"
                                } catch {
                                    Write-Error -Message "Failed to configure IIS binding: $_"
                                    Read-Host "`nPress Enter to continue"
                                }
                            } else {
                                Write-Warning -Message "No IIS sites found."
                                Read-Host "`nPress Enter to continue"
                            }
                        } else {
                            Write-Warning -Message "IIS WebAdministration module not available."
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                    2 {
                        # Windows Service Binding
                        Write-Warning -Message "`nWindows Service Certificate Binding:"
                        Write-Host -Object "This will generate configuration snippets for common Windows services."
                        $services = @(
                            @{ Name = "IIS Express"; Config = "applicationhost.config binding" },
                            @{ Name = "WCF Service"; Config = "app.config/web.config binding" },
                            @{ Name = "Custom .NET Service"; Config = "Service configuration" },
                            @{ Name = "Apache/Nginx"; Config = "SSL configuration" }
                        )
                        Write-Host -Object "`nSelect service type:"
                        for ($i = 0; $i -lt $services.Count; $i++) {
                            Write-Host -Object "$($i + 1)) $($services[$i].Name)"
                        }
                        $serviceChoice = Get-ValidatedInput -Prompt "`nSelect service (1-$($services.Count))" -ValidOptions (1..$services.Count)
                        $selectedService = $services[$serviceChoice - 1]
                        $configSnippet = switch ($serviceChoice) {
                            1 {
                                # IIS Express
                                @"
<!-- IIS Express applicationhost.config binding -->
<binding protocol="https" bindingInformation="*:443:" sslFlags="0">
  <certificate thumbprint="$($PACertificate.Certificate.Thumbprint)" storeName="My" storeLocation="LocalMachine" />
</binding>
"@
                            }
                            2 {
                                # WCF Service
                                @"
<!-- WCF Service SSL Configuration -->
<system.serviceModel>
  <services>
    <service name="YourService">
      <endpoint address="https://yourserver:443/YourService"
                binding="wsHttpBinding"
                bindingConfiguration="SecureBinding"
                contract="IYourService" />
    </service>
  </services>
  <bindings>
    <wsHttpBinding>
      <binding name="SecureBinding">
        <security mode="Transport">
          <transport clientCredentialType="Certificate" />
        </security>
      </binding>
    </wsHttpBinding>
  </bindings>
  <behaviors>
    <serviceBehaviors>
      <behavior>
        <serviceCredentials>
          <serviceCertificate findValue="$($PACertificate.Certificate.Thumbprint)"
                              storeLocation="LocalMachine"
                              storeName="My"
                              x509FindType="FindByThumbprint" />
        </serviceCredentials>
      </behavior>
    </serviceBehaviors>
  </behaviors>
</system.serviceModel>
"@
                            }
                            3 {
                                # Custom .NET Service
                                @"
// Custom .NET Service Certificate Binding
// Add to your service configuration
public void ConfigureSSL()
{
    var store = new X509Store(StoreName.My, StoreLocation.LocalMachine);
    store.Open(OpenFlags.ReadOnly);
    var certificate = store.Certificates
        .Find(X509FindType.FindByThumbprint, "$($PACertificate.Certificate.Thumbprint)", false)
        .OfType<X509Certificate2>()
        .FirstOrDefault();
    if (certificate != null)
    {
        // Use certificate for HTTPS endpoint
        var httpsBinding = new HttpsTransportBindingElement();
        httpsBinding.RequireClientCertificate = false;
        // Configure your service with the certificate
    }
    store.Close();
}
"@
                            }
                            4 {
                                # Apache/Nginx
                                @"
# Apache SSL Configuration
<VirtualHost *:443>
    ServerName $($PACertificate.MainDomain)
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile $($PACertificate.CertFile)
    SSLCertificateKeyFile $($PACertificate.KeyFile)
    SSLCertificateChainFile $($PACertificate.FullChainFile)
    # Modern SSL configuration
    SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:...
    SSLHonorCipherOrder on
</VirtualHost>
# Nginx SSL Configuration
server {
    listen 443 ssl http2;
    server_name $($PACertificate.MainDomain);
    ssl_certificate $($PACertificate.FullChainFile);
    ssl_certificate_key $($PACertificate.KeyFile);
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:...;
    ssl_prefer_server_ciphers off;
    location / {
        # Your application configuration
    }
}
"@
                            }
                        }
                        $configPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "service_config_$($selectedService.Name.Replace(' ','_'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                        Set-Content -Path $configPath -Value $configSnippet
                        Write-Information -MessageData "✓ Configuration snippet generated for $($selectedService.Name)" -InformationAction Continue
                        Write-Host -Object "  Configuration saved to: $configPath" -ForegroundColor Cyan
                        Write-Warning -Message "`nNext Steps:"
                        Write-Host -Object "• Review and customize the configuration for your environment"
                        Write-Host -Object "• Update your service configuration files"
                        Write-Host -Object "• Restart the service to apply changes"
                        Write-Host -Object "• Test the SSL/TLS connectivity"
                        Read-Host "`nPress Enter to continue"
                    }
                    3 {
                        # Generate custom application configuration
                        Write-Warning -Message "`nCustom Application Configuration Generator:"
                        $appName = Read-Host "Enter application name"
                        $appType = Read-Host "Enter application type (e.g., Web API, Desktop App, Service)"
                        $additionalNotes = Read-Host "Enter any additional configuration notes (optional)"
                        $customConfig = @"
CUSTOM APPLICATION CERTIFICATE CONFIGURATION
===========================================
Application: $appName
Type: $appType
Generated: $(Get-Date)
CERTIFICATE DETAILS
==================
Domain: $($PACertificate.MainDomain)
Thumbprint: $($PACertificate.Certificate.Thumbprint)
Subject: $($PACertificate.Certificate.Subject)
Valid Until: $($PACertificate.Certificate.NotAfter)
CONFIGURATION STEPS
==================
1. Certificate Store Location: LocalMachine\My
2. Certificate Identifier: Thumbprint = $($PACertificate.Certificate.Thumbprint)
3. Private Key Access: Ensure application identity has read access
SAMPLE CODE SNIPPETS
===================
PowerShell:
```powershell
`$cert = Get-ChildItem -Path Cert:\LocalMachine\My\$($PACertificate.Certificate.Thumbprint)
# Use `$cert for your PowerShell operations
```
C# (.NET):
```csharp
using System.Security.Cryptography.X509Certificates;
var store = new X509Store(StoreName.My, StoreLocation.LocalMachine);
store.Open(OpenFlags.ReadOnly);
var certificate = store.Certificates
    .Find(X509FindType.FindByThumbprint, "$($PACertificate.Certificate.Thumbprint)", false)
    .OfType<X509Certificate2>()
    .FirstOrDefault();
if (certificate != null)
{
    // Use certificate for your application
    // For HTTPS: httpsBinding.Certificate = certificate;
    // For client authentication: httpClient.ClientCertificates.Add(certificate);
}
store.Close();
```
Python:
```python
import ssl
import socket
# Load certificate for SSL context
ssl_context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
ssl_context.load_cert_chain('$($PACertificate.CertFile)', '$($PACertificate.KeyFile)')
# Use ssl_context with your Python SSL operations
```
Node.js:
```javascript
const https = require('https');
const fs = require('fs');
const options = {
    cert: fs.readFileSync('$($PACertificate.CertFile)'),
    key: fs.readFileSync('$($PACertificate.KeyFile)')
};
const server = https.createServer(options, (req, res) => {
    // Your application logic
});
server.listen(443);
```
SECURITY CONSIDERATIONS
======================
• Ensure private key files have appropriate permissions (read-only for application identity)
• Use certificate pinning where appropriate
• Implement proper certificate validation in client applications
• Monitor certificate expiry and plan for renewal
• Keep application frameworks and SSL libraries updated
ADDITIONAL NOTES
===============
$additionalNotes
TROUBLESHOOTING
==============
• Verify certificate is in correct store location
• Check application permissions to access private key
• Validate certificate chain and trust
• Test with SSL/TLS analysis tools
• Monitor application logs for certificate-related errors
For more information, consult your application framework's SSL/TLS documentation.
"@
                        $customConfigPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "custom_config_$($appName.Replace(' ','_'))_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                        Set-Content -Path $customConfigPath -Value $customConfig
                        Write-Information -MessageData "✓ Custom configuration generated for $appName" -InformationAction Continue
                        Write-Host -Object "  Configuration saved to: $customConfigPath" -ForegroundColor Cyan
                        Read-Host "`nPress Enter to continue"
                    }
                    0 {
                        Write-Host -Object "Skipping application binding configuration." -ForegroundColor Gray
                    }
                }
            }
            6 {
                # Verify certificate chain
                Write-Host -Object "`nVerifying certificate chain..." -ForegroundColor Cyan
                Write-ProgressHelper -Activity "Certificate Chain Verification" -Status "Loading certificate..." -PercentComplete 20
                try {
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                    $store.Open("ReadOnly")
                    $installedCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $PACertificate.Certificate.Thumbprint }
                    $store.Close()
                    if ($installedCert) {
                        Write-ProgressHelper -Activity "Certificate Chain Verification" -Status "Building certificate chain..." -PercentComplete 50
                        $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
                        $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::Online
                        $chain.ChainPolicy.RevocationFlag = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::ExcludeRoot
                        $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag
                        Write-ProgressHelper -Activity "Certificate Chain Verification" -Status "Validating chain..." -PercentComplete 75
                        $chainIsValid = $chain.Build($installedCert)
                        Write-ProgressHelper -Activity "Certificate Chain Verification" -Status "Analysis complete" -PercentComplete 100
                        Write-Progress -Activity "Certificate Chain Verification" -Completed
                        Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                        Write-Host -Object "CERTIFICATE CHAIN VERIFICATION RESULTS" -ForegroundColor Cyan
                        Write-Host -Object "="*60 -ForegroundColor Cyan
                        if ($chainIsValid) {
                            Write-Information -MessageData "✓ Certificate chain is valid and trusted" -InformationAction Continue
                        } else {
                            Write-Warning -Message "⚠ Certificate chain has issues"
                        }
                        Write-Warning -Message "`nChain Details:"
                        for ($i = 0; $i -lt $chain.ChainElements.Count; $i++) {
                            $element = $chain.ChainElements[$i]
                            $certType = if ($i -eq 0) { "End Entity" } elseif ($i -eq $chain.ChainElements.Count - 1) { "Root CA" } else { "Intermediate CA" }
                            Write-Host -Object "[$i] $certType Certificate:" -ForegroundColor White
                            Write-Host -Object "    Subject: $($element.Certificate.Subject)"
                            Write-Host -Object "    Issuer: $($element.Certificate.Issuer)"
                            Write-Host -Object "    Thumbprint: $($element.Certificate.Thumbprint)"
                            Write-Host -Object "    Valid Until: $($element.Certificate.NotAfter)"
                            if ($element.ChainElementStatus.Count -gt 0) {
                                Write-Error -Message "    Status Issues:"
                                foreach ($status in $element.ChainElementStatus) {
                                    Write-Host -Object "      - $($status.Status): $($status.StatusInformation)" -ForegroundColor Red
                                }
                            } else {
                                Write-Information -MessageData "    Status: Valid" -InformationAction Continue
                            }
                            Write-Information -MessageData "" -InformationAction Continue
                        }
                        # Overall chain status
                        if ($chain.ChainStatus.Count -gt 0) {
                            Write-Error -Message "Overall Chain Issues:"
                            foreach ($status in $chain.ChainStatus) {
                                Write-Host -Object "  - $($status.Status): $($status.StatusInformation)" -ForegroundColor Red
                            }
                        } else {
                            Write-Information -MessageData "Overall Chain Status: Valid" -InformationAction Continue
                        }
                        $chain.Dispose()
                    } else {
                        Write-Warning -Message "Certificate not found in LocalMachine\My store for chain verification."
                    }
                } catch {
                    Write-Error -Message "Certificate chain verification failed: $_"
                    Write-Log "Certificate chain verification failed: $_" -Level 'Error'
                } finally {
                    Write-Progress -Activity "Certificate Chain Verification" -Completed
                }
                Read-Host "`nPress Enter to continue"
            }
            0 {
                Write-Host -Object "Continuing to main menu..." -ForegroundColor Gray
            }
        }
    }
    # Final summary and cleanup
    if ($installed) {
        Write-Information -MessageData "`n" + "="*70 -InformationAction Continue
        Write-Information -MessageData "CERTIFICATE INSTALLATION SUMMARY" -InformationAction Continue
        Write-Information -MessageData "="*70 -InformationAction Continue
        Write-Information -MessageData "✓ Certificate for $($PACertificate.MainDomain) has been installed" -InformationAction Continue
        Write-Host -Object "✓ Installation completed at $(Get-Date)" -ForegroundColor Green
        Write-Host -Object "✓ All post-installation options have been configured" -ForegroundColor Green
        Write-Host -Object "`nRecommended Next Steps:" -ForegroundColor Cyan
        Write-Host -Object "• Test your applications to ensure they're using the new certificate"
        Write-Host -Object "• Update any hardcoded certificate references in configuration files"
        Write-Host -Object "• Schedule regular certificate monitoring and renewal"
        Write-Host -Object "• Document the installation for your team"
        Write-Host -Object "• Consider setting up automated renewal for future certificates"
        Write-Log "Certificate installation completed for $($PACertificate.MainDomain)"
    }
    Read-Host "`nPress Enter to return to the main menu"
}




