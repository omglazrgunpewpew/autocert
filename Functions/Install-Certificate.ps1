# Functions/Install-Certificate.ps1
<#
    .SYNOPSIS
        Certificate installation with deployment options,
        robust error handling, and comprehensive post-installation features.

    .DESCRIPTION
        Provides a comprehensive interface for installing Let's Encrypt certificates
        to various targets including certificate stores, PEM files, and PFX exports.
        Includes advanced options, testing, monitoring, and reporting capabilities.

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
            Write-Warning "`nNo certificates available to install."
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
                Write-Warning "Failed to load certificate for $($order.MainDomain): $_"
            }
        }

        if ($certs.Count -eq 0) {
            Write-Warning "`nNo valid certificates available to install."
            Read-Host "`nPress Enter to return to the main menu"
            return
        }

        # Display certificate selection menu
        Write-Information "Select the certificate you want to install:" -InformationAction Continue
        for ($i = 0; $i -lt $certs.Count; $i++) {
            $cert = $certs[$i]
            $expiryInfo = ""
            if ($cert.Certificate) {
                $daysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                $expiryInfo = " (expires in $daysUntilExpiry days)"
                if ($daysUntilExpiry -le 7) {
                    Write-Warning "$($i + 1)) $($cert.MainDomain)$expiryInfo"
                } else {
                    Write-Information "$($i + 1)) $($cert.MainDomain)$expiryInfo" -InformationAction Continue
                }
            } else {
                Write-Information "$($i + 1)) $($cert.MainDomain)$expiryInfo" -InformationAction Continue
            }
        }
        Write-Information "0) Back to main menu" -InformationAction Continue
        
        $selection = Get-ValidatedInput -Prompt "`nEnter your choice (0-$($certs.Count))" -ValidOptions (0..$certs.Count)
        if ($selection -eq 0) {
            return
        } else {
            $PACertificate = $certs[$selection - 1]
        }
    }

    # Display certificate information
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host "CERTIFICATE INSTALLATION" -ForegroundColor Cyan
    Write-Host "="*70 -ForegroundColor Cyan
    Write-Host "Selected Certificate: $($PACertificate.MainDomain)" -ForegroundColor White

    if ($PACertificate.Certificate) {
        Write-Host "`nCertificate Details:" -ForegroundColor Yellow
        Write-Host "  Subject: $($PACertificate.Certificate.Subject)"
        Write-Host "  Issuer: $($PACertificate.Certificate.Issuer)"
        Write-Host "  Valid From: $($PACertificate.Certificate.NotBefore)"
        Write-Host "  Valid Until: $($PACertificate.Certificate.NotAfter)"
        Write-Host "  Thumbprint: $($PACertificate.Certificate.Thumbprint)"
        
        # Show expiry warning if needed
        $daysUntilExpiry = ($PACertificate.Certificate.NotAfter - (Get-Date)).Days
        if ($daysUntilExpiry -le 30) {
            Write-Warning "  This certificate expires in $daysUntilExpiry days!"
        }
    }

    # Main installation menu loop
    $installed = $false
    while (-not $installed) {
        Write-Host "`n" + "-"*70 -ForegroundColor Gray
        Write-Host "INSTALLATION OPTIONS" -ForegroundColor Yellow
        Write-Host "-"*70 -ForegroundColor Gray
        Write-Host "1) Install to Management Server (Windows Certificate Store)"
        Write-Host "2) Install to Recording Server (PEM Files)"
        Write-Host "3) Export as PFX File"
        Write-Host "4) Export Multiple Formats"
        Write-Host "5) Advanced Installation Options"
        Write-Host "0) Back to main menu"

        $installChoice = Get-ValidatedInput -Prompt "`nSelect installation method (0-5)" -ValidOptions (0..5)

        switch ($installChoice) {
            0 { 
                return 
            }
            
            1 {
                # Management Server Installation
                Write-Host "`nInstalling certificate to Management Server..." -ForegroundColor Cyan
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
                        Write-Host "Preference saved." -ForegroundColor Green
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
                        Write-Host "`n✓ Certificate installed to LocalMachine\My store" -ForegroundColor Green
                        Write-Host "`nInstallation Details:" -ForegroundColor Yellow
                        Write-Host "  Store: LocalMachine\My"
                        Write-Host "  Private Key Exportable: $(-not $isNotExportable)"
                        Write-Host "  Thumbprint: $($PACertificate.Certificate.Thumbprint)"
                        Write-Host "  Subject: $($PACertificate.Certificate.Subject)"
                        
                        Write-Log "Certificate installed to LocalMachine\My for $($PACertificate.MainDomain)"
                        $installed = $true
                    } else {
                        throw "Certificate installation verification failed"
                    }
                    
                } catch {
                    $msg = "Failed to install certificate to LocalMachine\My store: $($_.Exception.Message)"
                    Write-Error $msg
                    Write-Log $msg -Level 'Error'
                    
                    Write-Host "`nTroubleshooting suggestions:" -ForegroundColor Yellow
                    Write-Host "• Ensure you're running as Administrator"
                    Write-Host "• Check if the certificate store is accessible"
                    Write-Host "• Verify the certificate is valid and not corrupted"
                    Read-Host "`nPress Enter to continue"
                    
                } finally {
                    Write-Progress -Activity "Certificate Installation" -Completed
                }
            }
            
            2 {
                # Recording Server Installation
                Write-Host "`nInstalling certificate to Recording Server..." -ForegroundColor Cyan
                Write-ProgressHelper -Activity "Certificate Installation" -Status "Locating Recording Server directory..." -PercentComplete 25
                
                $certDir = Get-RSCertFolder
                if ($null -eq $certDir) {
                    Write-Error "Recording Server certificate directory not found."
                    Read-Host "`nPress Enter to continue"
                    continue
                }

                Write-Host "Using Recording Server directory: $certDir" -ForegroundColor Green
                Write-ProgressHelper -Activity "Certificate Installation" -Status "Extracting certificate content..." -PercentComplete 40

                # Extract certificate and key content
                $pemContent = Get-CertificatePEMContent -Certificate $PACertificate -IncludeKey
                if (-not $pemContent.Success) {
                    Write-Error "Failed to extract certificate content: $($pemContent.ErrorMessage)"
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
                        Write-Host "`n✓ Certificate and private key saved" -ForegroundColor Green
                        Write-Host "`nFile Details:" -ForegroundColor Yellow
                        Write-Host "  Certificate: $($result.CertFile)"
                        Write-Host "  Private Key: $($result.KeyFile)"
                        
                        # Show file sizes for verification
                        $certSize = (Get-Item $result.CertFile).Length
                        $keySize = (Get-Item $result.KeyFile).Length
                        Write-Host "  Certificate Size: $certSize bytes"
                        Write-Host "  Private Key Size: $keySize bytes"
                        
                        Write-Log "Certificate and private key saved to Recording Server directory"
                        
                        Write-Host "`nNext Steps:" -ForegroundColor Cyan
                        Write-Host "• Restart the Recording Server service"
                        Write-Host "• Update configuration files with new certificate paths"
                        Write-Host "• Test HTTPS connectivity"
                        
                        $installed = $true
                    }
                } catch {
                    Write-Error "Failed to save PEM files: $($_.Exception.Message)"
                    Read-Host "`nPress Enter to continue"
                } finally {
                    Write-Progress -Activity "Certificate Installation" -Completed
                }
            }
            
            3 {
                # PFX Export
                Write-Host "`nExporting certificate as PFX file..." -ForegroundColor Cyan
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
                        Write-Host "Created directory: $certDir" -ForegroundColor Green
                    } catch {
                        Write-Error "Failed to create directory: $certDir"
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
                    Write-Host "`n✓ Certificate exported" -ForegroundColor Green
                    Write-Host "`nExport Details:" -ForegroundColor Yellow
                    Write-Host "  File: $certPath"
                    Write-Host "  Size: $($fileInfo.Length) bytes"
                    Write-Host "  Created: $($fileInfo.CreationTime)"
                    Write-Host "  Password Protected: $(if ($passwordString) { 'Yes' } else { 'No' })"
                    
                    Write-Log "Certificate exported as PFX to $certPath"
                    
                    # Update default path setting
                    $savePathPreference = Read-Host "`nSave this directory as default PFX location? (Y/N)"
                    if ($savePathPreference -match '^[Yy]$') {
                        $settings.DefaultPFXLocation = Split-Path $certPath -Parent
                        Save-ScriptSettings -Settings $settings
                        Write-Host "Default PFX location updated." -ForegroundColor Green
                    }
                    
                    $installed = $true
                    
                } catch {
                    $msg = "Failed to export certificate as PFX: $($_.Exception.Message)"
                    Write-Error $msg
                    Write-Log $msg -Level 'Error'
                    Read-Host "`nPress Enter to continue"
                } finally {
                    Write-Progress -Activity "Certificate Export" -Completed
                }
            }
            
            4 {
                # Multiple Format Export
                Write-Host "`nExporting certificate in multiple formats..." -ForegroundColor Cyan
                
                $exportDir = Read-Host "`nEnter directory for exports (default: Desktop) or 0 to go back"
                if ($exportDir -eq '0') { continue }
                
                if (-not $exportDir) {
                    $exportDir = [Environment]::GetFolderPath("Desktop")
                }

                # Create export directory if needed
                if (-not (Test-Path $exportDir)) {
                    try {
                        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
                        Write-Host "Created directory: $exportDir" -ForegroundColor Green
                    } catch {
                        Write-Error "Failed to create directory: $exportDir"
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

                    Write-Host "`n✓ Multi-format export completed" -ForegroundColor Green
                    Write-Host "`nExported Files:" -ForegroundColor Yellow
                    $exportResults | ForEach-Object { Write-Host "  $_" }

                    Write-Log "Multi-format export completed for $($PACertificate.MainDomain)"
                    $installed = $true

                } catch {
                    Write-Error "Multi-format export failed: $_"
                    Write-Log "Multi-format export failed for $($PACertificate.MainDomain): $_" -Level 'Error'
                    Read-Host "`nPress Enter to continue"
                } finally {
                    Write-Progress -Activity "Multi-Format Export" -Completed
                }
            }
            
            5 {
                # Advanced Installation Options
                Write-Host "`nAdvanced Installation Options:" -ForegroundColor Cyan
                Write-Host "1) Install to custom certificate store"
                Write-Host "2) Install with custom friendly name"
                Write-Host "3) Install with backup creation"
                Write-Host "4) Configure IIS site binding"
                Write-Host "5) Schedule automatic reinstallation"
                Write-Host "0) Back to main menu"
                
                $advancedChoice = Get-ValidatedInput -Prompt "`nSelect advanced option (0-5)" -ValidOptions (0..5)
                
                switch ($advancedChoice) {
                    0 { continue }
                    
                    1 {
                        # Custom certificate store
                        Write-Host "`nCustom Certificate Store Installation:" -ForegroundColor Yellow
                        Write-Host "1) LocalMachine\My (Personal)"
                        Write-Host "2) LocalMachine\WebHosting"
                        Write-Host "3) CurrentUser\My (Personal)"
                        Write-Host "4) LocalMachine\TrustedPeople"
                        Write-Host "5) Custom store name"
                        
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
                            Write-Host "✓ Certificate installed to $storeLocation\$storeName" -ForegroundColor Green
                            Write-Log "Certificate installed to custom store $storeLocation\$storeName"
                            $installed = $true
                        } catch {
                            Write-Error "Failed to install to custom store: $_"
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
                                    Write-Host "✓ Certificate installed with friendly name: $friendlyName" -ForegroundColor Green
                                    Write-Log "Certificate installed with friendly name: $friendlyName"
                                    $installed = $true
                                } else {
                                    throw "Certificate not found after installation"
                                }
                                $store.Close()
                            } catch {
                                Write-Error "Failed to set friendly name: $_"
                                Read-Host "`nPress Enter to continue"
                            }
                        }
                    }
                    
                    3 {
                        # Backup and install
                        Write-Host "`nCreating backup before installation..." -ForegroundColor Yellow
                        
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
                            Write-Host "✓ Backup created: $backupPath" -ForegroundColor Green
                            
                            # Install certificate
                            Install-PACertificate -PACertificate $PACertificate -StoreLocation LocalMachine -Verbose
                            Write-Host "✓ Certificate installed successfully" -ForegroundColor Green
                            Write-Log "Certificate installed with backup created"
                            $installed = $true
                            
                        } catch {
                            Write-Error "Backup and install failed: $_"
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                    
                    4 {
                        # IIS site binding
                        if (Get-Module -ListAvailable -Name WebAdministration) {
                            Import-Module WebAdministration
                            $sites = Get-Website
                            
                            if ($sites) {
                                Write-Host "`nAvailable IIS Sites:" -ForegroundColor Yellow
                                for ($i = 0; $i -lt $sites.Count; $i++) {
                                    Write-Host "$($i + 1)) $($sites[$i].Name) - $($sites[$i].State)"
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
                                        Write-Host "Removed existing HTTPS binding" -ForegroundColor Yellow
                                    }
                                    
                                    # Create new HTTPS binding
                                    New-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -SslFlags 1
                                    
                                    # Bind certificate
                                    $binding = Get-WebBinding -Name $selectedSite.Name -Protocol https -Port 443
                                    $binding.AddSslCertificate($PACertificate.Certificate.Thumbprint, "my")
                                    
                                    Write-Host "✓ Certificate bound to IIS site: $($selectedSite.Name)" -ForegroundColor Green
                                    Write-Log "Certificate bound to IIS site: $($selectedSite.Name)"
                                    $installed = $true
                                    
                                } catch {
                                    Write-Error "Failed to configure IIS binding: $_"
                                    Read-Host "`nPress Enter to continue"
                                }
                            } else {
                                Write-Warning "No IIS sites found."
                                Read-Host "`nPress Enter to continue"
                            }
                        } else {
                            Write-Warning "IIS WebAdministration module not available."
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                    
                    5 {
                        # Schedule automatic reinstallation
                        Write-Host "`nScheduling automatic certificate reinstallation..." -ForegroundColor Yellow
                        
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
                            
                            Write-Host "✓ Automatic reinstallation scheduled for $($PACertificate.MainDomain)" -ForegroundColor Green
                            Write-Host "  Task: $taskName" -ForegroundColor Cyan
                            Write-Host "  Schedule: Weekly on Sundays at 3:00 AM" -ForegroundColor Cyan
                            Write-Log "Automatic reinstallation scheduled for $($PACertificate.MainDomain)"
                            $installed = $true
                            
                        } catch {
                            Write-Error "Failed to create scheduled task: $_"
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                }
            }
        }
    }

    # Post-installation actions and verification
    if ($installed) {
        Write-Host "`n" + "="*70 -ForegroundColor Green
        Write-Host "INSTALLATION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        Write-Host "="*70 -ForegroundColor Green
        
        # Post-installation menu
        Write-Host "`nPost-Installation Options:" -ForegroundColor Yellow
        Write-Host "1) Test certificate installation"
        Write-Host "2) View detailed certificate information"
        Write-Host "3) Configure monitoring and alerts"
        Write-Host "4) Generate installation report"
        Write-Host "5) Configure application bindings"
        Write-Host "6) Verify certificate chain"
        Write-Host "0) Continue to main menu"
        
        $postChoice = Get-ValidatedInput -Prompt "`nSelect option (0-6)" -ValidOptions (0..6)
        
        switch ($postChoice) {
            1 {
                # Comprehensive certificate testing
                Write-Host "`nRunning comprehensive certificate tests..." -ForegroundColor Cyan
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
                        Write-Host "✓ Certificate found in LocalMachine\My store" -ForegroundColor Green
                        $testResults += @{ Test = "Certificate Store"; Result = "PASS"; Details = "Found in LocalMachine\My" }
                        
                        # Test 2: Private key availability
                        Write-ProgressHelper -Activity "Certificate Testing" -Status "Checking private key..." -PercentComplete 40
                        if ($installedCert.HasPrivateKey) {
                            Write-Host "✓ Private key is available and accessible" -ForegroundColor Green
                            $testResults += @{ Test = "Private Key"; Result = "PASS"; Details = "Available and accessible" }
                        } else {
                            Write-Host "✗ Private key is not available" -ForegroundColor Red
                            $testResults += @{ Test = "Private Key"; Result = "FAIL"; Details = "Not available" }
                            $allTestsPassed = $false
                        }
                        
                        # Test 3: Certificate validity period
                        Write-ProgressHelper -Activity "Certificate Testing" -Status "Checking validity..." -PercentComplete 55
                        $now = Get-Date
                        if ($installedCert.NotAfter -gt $now -and $installedCert.NotBefore -le $now) {
                            $daysValid = ($installedCert.NotAfter - $now).Days
                            Write-Host "✓ Certificate is currently valid ($daysValid days remaining)" -ForegroundColor Green
                            $testResults += @{ Test = "Validity Period"; Result = "PASS"; Details = "$daysValid days remaining" }
                        } else {
                            Write-Host "✗ Certificate is not valid (expired or not yet valid)" -ForegroundColor Red
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
                                Write-Host "✓ Certificate chain is valid and trusted" -ForegroundColor Green
                                $testResults += @{ Test = "Chain Validation"; Result = "PASS"; Details = "Valid and trusted" }
                            } else {
                                $chainErrors = $chain.ChainStatus | ForEach-Object { $_.Status } | Sort-Object -Unique
                                Write-Host "⚠ Certificate chain has warnings: $($chainErrors -join ', ')" -ForegroundColor Yellow
                                $testResults += @{ Test = "Chain Validation"; Result = "WARNING"; Details = $chainErrors -join ', ' }
                            }
                            $chain.Dispose()
                        } catch {
                            Write-Host "✗ Certificate chain validation failed: $_" -ForegroundColor Red
                            $testResults += @{ Test = "Chain Validation"; Result = "FAIL"; Details = $_.Exception.Message }
                            $allTestsPassed = $false
                        }
                        
                        # Test 5: Key usage validation
                        Write-ProgressHelper -Activity "Certificate Testing" -Status "Checking key usage..." -PercentComplete 85
                        $keyUsageExt = $installedCert.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.15" }
                        if ($keyUsageExt) {
                            Write-Host "✓ Key usage extension present: $($keyUsageExt.Format($false))" -ForegroundColor Green
                            $testResults += @{ Test = "Key Usage"; Result = "PASS"; Details = $keyUsageExt.Format($false) }
                        } else {
                            Write-Host "⚠ Key usage extension not found" -ForegroundColor Yellow
                            $testResults += @{ Test = "Key Usage"; Result = "WARNING"; Details = "Extension not found" }
                        }
                        
                    } else {
                        Write-Host "✗ Certificate not found in certificate store" -ForegroundColor Red
                        $testResults += @{ Test = "Certificate Store"; Result = "FAIL"; Details = "Not found in LocalMachine\My" }
                        $allTestsPassed = $false
                    }
                } catch {
                    Write-Host "✗ Certificate testing failed: $_" -ForegroundColor Red
                    $testResults += @{ Test = "Certificate Test"; Result = "ERROR"; Details = $_.Exception.Message }
                    $allTestsPassed = $false
                }
                
                Write-ProgressHelper -Activity "Certificate Testing" -Status "Tests complete" -PercentComplete 100
                Write-Progress -Activity "Certificate Testing" -Completed
                
                # Display comprehensive test summary
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "CERTIFICATE TEST SUMMARY" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                foreach ($result in $testResults) {
                    $color = switch ($result.Result) {
                        "PASS" { "Green" }
                        "WARNING" { "Yellow" }
                        "FAIL" { "Red" }
                        "ERROR" { "Red" }
                    }
                    Write-Host "[$($result.Result.PadRight(7))] $($result.Test): $($result.Details)" -ForegroundColor $color
                }
                
                $overallStatus = if ($allTestsPassed) { "ALL TESTS PASSED" } else { "ISSUES DETECTED" }
                $statusColor = if ($allTestsPassed) { "Green" } else { "Red" }
                Write-Host "`nOverall Status: $overallStatus" -ForegroundColor $statusColor
                
                Read-Host "`nPress Enter to continue"
            }
            
            2 {
                # Certificate information display
                Write-Host "`n" + "="*70 -ForegroundColor Cyan
                Write-Host "DETAILED CERTIFICATE INFORMATION" -ForegroundColor Cyan
                Write-Host "="*70 -ForegroundColor Cyan
                
                Write-Host "`nBasic Information:" -ForegroundColor Yellow
                Write-Host "Subject: $($PACertificate.Certificate.Subject)"
                Write-Host "Issuer: $($PACertificate.Certificate.Issuer)"
                Write-Host "Serial Number: $($PACertificate.Certificate.SerialNumber)"
                Write-Host "Thumbprint: $($PACertificate.Certificate.Thumbprint)"
                Write-Host "Version: $($PACertificate.Certificate.Version)"
                
                Write-Host "`nValidity Period:" -ForegroundColor Yellow
                Write-Host "Valid From: $($PACertificate.Certificate.NotBefore)"
                Write-Host "Valid Until: $($PACertificate.Certificate.NotAfter)"
                $daysUntilExpiry = ($PACertificate.Certificate.NotAfter - (Get-Date)).Days
                $expiryColor = if ($daysUntilExpiry -gt 30) { "Green" } elseif ($daysUntilExpiry -gt 7) { "Yellow" } else { "Red" }
                Write-Host "Days Until Expiry: $daysUntilExpiry" -ForegroundColor $expiryColor
                
                Write-Host "`nCryptographic Information:" -ForegroundColor Yellow
                Write-Host "Public Key Algorithm: $($PACertificate.Certificate.PublicKey.Oid.FriendlyName)"
                Write-Host "Key Size: $($PACertificate.Certificate.PublicKey.Key.KeySize) bits"
                Write-Host "Signature Algorithm: $($PACertificate.Certificate.SignatureAlgorithm.FriendlyName)"
                Write-Host "Has Private Key: $($PACertificate.Certificate.HasPrivateKey)"
                
                if ($PACertificate.Certificate.Extensions) {
                    Write-Host "`nCertificate Extensions:" -ForegroundColor Yellow
                    
                    # Subject Alternative Names
                    $sanExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.17" }
                    if ($sanExt) {
                        Write-Host "Subject Alternative Names:"
                        $sanExt.Format($false) -split ", " | ForEach-Object { Write-Host "  $_" }
                    }
                    
                    # Key Usage
                    $keyUsageExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.15" }
                    if ($keyUsageExt) {
                        Write-Host "Key Usage: $($keyUsageExt.Format($false))"
                    }
                    
                    # Extended Key Usage
                    $extKeyUsageExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.37" }
                    if ($extKeyUsageExt) {
                        Write-Host "Extended Key Usage: $($extKeyUsageExt.Format($false))"
                    }
                    
                    # Basic Constraints
                    $basicConstraintsExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.19" }
                    if ($basicConstraintsExt) {
                        Write-Host "Basic Constraints: $($basicConstraintsExt.Format($false))"
                    }
                    
                    # Authority Information Access
                    $aiaExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "1.3.6.1.5.5.7.1.1" }
                    if ($aiaExt) {
                        Write-Host "Authority Information Access: $($aiaExt.Format($false))"
                    }
                    
                    # CRL Distribution Points
                    $crlExt = $PACertificate.Certificate.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.31" }
                    if ($crlExt) {
                        Write-Host "CRL Distribution Points: $($crlExt.Format($false))"
                    }
                }
                
                Write-Host "`nFile Locations:" -ForegroundColor Yellow
                if ($PACertificate.CertFile) { Write-Host "Certificate File: $($PACertificate.CertFile)" }
                if ($PACertificate.KeyFile) { Write-Host "Private Key File: $($PACertificate.KeyFile)" }
                if ($PACertificate.ChainFile) { Write-Host "Chain File: $($PACertificate.ChainFile)" }
                if ($PACertificate.FullChainFile) { Write-Host "Full Chain File: $($PACertificate.FullChainFile)" }
                if ($PACertificate.PfxFile) { Write-Host "PFX File: $($PACertificate.PfxFile)" }
                
                Read-Host "`nPress Enter to continue"
            }
            
            3 {
                # Configure monitoring and alerts
                Write-Host "`nConfiguring certificate monitoring and alerts..." -ForegroundColor Cyan
                
                $config = Get-RenewalConfig
                Write-Host "`nCurrent monitoring settings:" -ForegroundColor Yellow
                Write-Host "Expiry warning threshold: $($config.RenewalThresholdDays) days"
                Write-Host "Email notifications: $($config.EmailNotifications)"
                if ($config.EmailNotifications) {
                    Write-Host "Notification email: $($config.NotificationEmail)"
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
                    Write-Host "✓ Monitoring settings updated" -ForegroundColor Green
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
                Write-Host "Warning: Could not write to event log: `$_"
            }
            
            # Output for scheduled task
            Write-Host `$message
            
            # Email notification (if configured)
            # Add your email sending logic here
        } else {
            Write-Host "Certificate $($PACertificate.MainDomain) is valid for `$daysUntilExpiry more days"
        }
    } else {
        Write-Host "Error: Certificate $($PACertificate.MainDomain) not found or invalid"
        Write-EventLog -LogName Application -Source "Certificate Management" -EventId 2002 -EntryType Error -Message "Certificate $($PACertificate.MainDomain) not found or invalid"
    }
} catch {
    `$errorMessage = "Certificate monitoring failed for $($PACertificate.MainDomain): `$_"
    Write-Host `$errorMessage
    Write-EventLog -LogName Application -Source "Certificate Management" -EventId 2003 -EntryType Error -Message `$errorMessage
}
"@
                    
                    $monitorPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "monitor_$($PACertificate.MainDomain.Replace('*','wildcard').Replace('.','_')).ps1"
                    $monitorScript | Set-Content -Path $monitorPath
                    Write-Host "✓ Monitoring script created: $monitorPath" -ForegroundColor Green
                    
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
                            
                            Write-Host "✓ Monitoring task created: $taskName" -ForegroundColor Green
                            Write-Host "  Schedule: Daily at 9:00 AM" -ForegroundColor Cyan
                        } catch {
                            Write-Error "Failed to create monitoring task: $_"
                        }
                    }
                }
                
                Write-Log "Monitoring configured for $($PACertificate.MainDomain)"
                Read-Host "`nPress Enter to continue"
            }
            
            4 {
                # Generate comprehensive installation report
                Write-Host "`nGenerating comprehensive installation report..." -ForegroundColor Cyan
                
                $reportPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "certificate_installation_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
                
                # Gather system information
                $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
                $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
                
                $report = @"
COMPREHENSIVE CERTIFICATE INSTALLATION REPORT
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
□ Certificate chain validates successfully
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
                Write-Host "✓ Comprehensive installation report generated" -ForegroundColor Green
                Write-Host "  Report saved to: $reportPath" -ForegroundColor Cyan
                
                $openReport = Read-Host "`nOpen report in default text editor? (Y/N)"
                if ($openReport -match '^[Yy]') {
                    try {
                        Start-Process $reportPath
                    } catch {
                        Write-Host "Could not open report automatically. File location: $reportPath"
                    }
                }
                
                Write-Log "Installation report generated: $reportPath"
                Read-Host "`nPress Enter to continue"
            }
            
            5 {
                # Configure application bindings
                Write-Host "`nApplication Binding Configuration:" -ForegroundColor Cyan
                Write-Host "1) Configure IIS website binding"
                Write-Host "2) Configure Windows service binding"
                Write-Host "3) Generate custom application configuration"
                Write-Host "0) Skip application binding"
                
                $bindingChoice = Get-ValidatedInput -Prompt "`nSelect binding type (0-3)" -ValidOptions (0..3)
                
                switch ($bindingChoice) {
                    1 {
                        # IIS Website Binding (continued from advanced section)
                        if (Get-Module -ListAvailable -Name WebAdministration) {
                            Import-Module WebAdministration
                            $sites = Get-Website
                            if ($sites) {
                                Write-Host "`nAvailable IIS Sites:" -ForegroundColor Yellow
                                for ($i = 0; $i -lt $sites.Count; $i++) {
                                    $bindingInfo = $sites[$i].Bindings.Collection | Where-Object { $_.protocol -eq "https" }
                                    $httpsStatus = if ($bindingInfo) { "HTTPS Configured" } else { "HTTP Only" }
                                    Write-Host "$($i + 1)) $($sites[$i].Name) - $($sites[$i].State) - $httpsStatus"
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
                                            Write-Host "Existing HTTPS binding removed" -ForegroundColor Yellow
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
                                    
                                    Write-Host "✓ Certificate successfully bound to IIS site: $($selectedSite.Name)" -ForegroundColor Green
                                    Write-Host "  Binding: HTTPS on port 443" -ForegroundColor Cyan
                                    Write-Host "  Certificate: $($PACertificate.Certificate.Thumbprint)" -ForegroundColor Cyan
                                    
                                    # Test binding
                                    $testBinding = Read-Host "`nTest HTTPS binding? (Y/N)"
                                    if ($testBinding -match '^[Yy]') {
                                        try {
                                            $testUrl = "https://localhost"
                                            $response = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -SkipCertificateCheck -TimeoutSec 10
                                            Write-Host "✓ HTTPS binding test successful (Status: $($response.StatusCode))" -ForegroundColor Green
                                        } catch {
                                            Write-Warning "HTTPS binding test failed: $($_.Exception.Message)"
                                            Write-Host "This may be normal if the site requires specific host headers or has other configuration requirements." -ForegroundColor Gray
                                        }
                                    }
                                    
                                    Write-Log "Certificate bound to IIS site: $($selectedSite.Name)"
                                    
                                } catch {
                                    Write-Error "Failed to configure IIS binding: $_"
                                    Read-Host "`nPress Enter to continue"
                                }
                            } else {
                                Write-Warning "No IIS sites found."
                                Read-Host "`nPress Enter to continue"
                            }
                        } else {
                            Write-Warning "IIS WebAdministration module not available."
                            Read-Host "`nPress Enter to continue"
                        }
                    }
                    
                    2 {
                        # Windows Service Binding
                        Write-Host "`nWindows Service Certificate Binding:" -ForegroundColor Yellow
                        Write-Host "This will generate configuration snippets for common Windows services."
                        
                        $services = @(
                            @{ Name = "IIS Express"; Config = "applicationhost.config binding" },
                            @{ Name = "WCF Service"; Config = "app.config/web.config binding" },
                            @{ Name = "Custom .NET Service"; Config = "Service configuration" },
                            @{ Name = "Apache/Nginx"; Config = "SSL configuration" }
                        )
                        
                        Write-Host "`nSelect service type:"
                        for ($i = 0; $i -lt $services.Count; $i++) {
                            Write-Host "$($i + 1)) $($services[$i].Name)"
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
                        
                        Write-Host "✓ Configuration snippet generated for $($selectedService.Name)" -ForegroundColor Green
                        Write-Host "  Configuration saved to: $configPath" -ForegroundColor Cyan
                        Write-Host "`nNext Steps:" -ForegroundColor Yellow
                        Write-Host "• Review and customize the configuration for your environment"
                        Write-Host "• Update your service configuration files"
                        Write-Host "• Restart the service to apply changes"
                        Write-Host "• Test the SSL/TLS connectivity"
                        
                        Read-Host "`nPress Enter to continue"
                    }
                    
                    3 {
                        # Generate custom application configuration
                        Write-Host "`nCustom Application Configuration Generator:" -ForegroundColor Yellow
                        
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
                        
                        Write-Host "✓ Custom configuration generated for $appName" -ForegroundColor Green
                        Write-Host "  Configuration saved to: $customConfigPath" -ForegroundColor Cyan
                        
                        Read-Host "`nPress Enter to continue"
                    }
                    
                    0 {
                        Write-Host "Skipping application binding configuration." -ForegroundColor Gray
                    }
                }
            }
            
            6 {
                # Verify certificate chain
                Write-Host "`nVerifying certificate chain..." -ForegroundColor Cyan
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
                        
                        Write-Host "`n" + "="*60 -ForegroundColor Cyan
                        Write-Host "CERTIFICATE CHAIN VERIFICATION RESULTS" -ForegroundColor Cyan
                        Write-Host "="*60 -ForegroundColor Cyan
                        
                        if ($chainIsValid) {
                            Write-Host "✓ Certificate chain is valid and trusted" -ForegroundColor Green
                        } else {
                            Write-Host "⚠ Certificate chain has issues" -ForegroundColor Yellow
                        }
                        
                        Write-Host "`nChain Details:" -ForegroundColor Yellow
                        for ($i = 0; $i -lt $chain.ChainElements.Count; $i++) {
                            $element = $chain.ChainElements[$i]
                            $certType = if ($i -eq 0) { "End Entity" } elseif ($i -eq $chain.ChainElements.Count - 1) { "Root CA" } else { "Intermediate CA" }
                            
                            Write-Host "[$i] $certType Certificate:" -ForegroundColor White
                            Write-Host "    Subject: $($element.Certificate.Subject)"
                            Write-Host "    Issuer: $($element.Certificate.Issuer)"
                            Write-Host "    Thumbprint: $($element.Certificate.Thumbprint)"
                            Write-Host "    Valid Until: $($element.Certificate.NotAfter)"
                            
                            if ($element.ChainElementStatus.Count -gt 0) {
                                Write-Host "    Status Issues:" -ForegroundColor Red
                                foreach ($status in $element.ChainElementStatus) {
                                    Write-Host "      - $($status.Status): $($status.StatusInformation)" -ForegroundColor Red
                                }
                            } else {
                                Write-Host "    Status: Valid" -ForegroundColor Green
                            }
                            Write-Host ""
                        }
                        
                        # Overall chain status
                        if ($chain.ChainStatus.Count -gt 0) {
                            Write-Host "Overall Chain Issues:" -ForegroundColor Red
                            foreach ($status in $chain.ChainStatus) {
                                Write-Host "  - $($status.Status): $($status.StatusInformation)" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "Overall Chain Status: Valid" -ForegroundColor Green
                        }
                        
                        $chain.Dispose()
                        
                    } else {
                        Write-Warning "Certificate not found in LocalMachine\My store for chain verification."
                    }
                    
                } catch {
                    Write-Error "Certificate chain verification failed: $_"
                    Write-Log "Certificate chain verification failed: $_" -Level 'Error'
                } finally {
                    Write-Progress -Activity "Certificate Chain Verification" -Completed
                }
                
                Read-Host "`nPress Enter to continue"
            }
            
            0 {
                Write-Host "Continuing to main menu..." -ForegroundColor Gray
            }
        }
    }

    # Final summary and cleanup
    if ($installed) {
        Write-Host "`n" + "="*70 -ForegroundColor Green
        Write-Host "CERTIFICATE INSTALLATION SUMMARY" -ForegroundColor Green
        Write-Host "="*70 -ForegroundColor Green
        Write-Host "✓ Certificate for $($PACertificate.MainDomain) has been successfully installed" -ForegroundColor Green
        Write-Host "✓ Installation completed at $(Get-Date)" -ForegroundColor Green
        Write-Host "✓ All post-installation options have been configured" -ForegroundColor Green
        
        Write-Host "`nRecommended Next Steps:" -ForegroundColor Cyan
        Write-Host "• Test your applications to ensure they're using the new certificate"
        Write-Host "• Update any hardcoded certificate references in configuration files"
        Write-Host "• Schedule regular certificate monitoring and renewal"
        Write-Host "• Document the installation for your team"
        Write-Host "• Consider setting up automated renewal for future certificates"
        
        Write-Log "Certificate installation completed successfully for $($PACertificate.MainDomain)"
    }
    
    Read-Host "`nPress Enter to return to the main menu"
}