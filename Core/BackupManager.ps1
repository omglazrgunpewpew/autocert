# Core/BackupManager.ps1
<#
    .SYNOPSIS
        Backup and recovery system for certificates and configurations.
#>
function Initialize-BackupSystem {
    [CmdletBinding()]
    param(
        [string]$BackupRootPath = "$env:LOCALAPPDATA\AutoCert\Backups"
    )
    $backupStructure = @(
        'Certificates',
        'Configurations',
        'Logs',
        'Metadata'
    )
    foreach ($folder in $backupStructure) {
        $folderPath = Join-Path $BackupRootPath $folder
        if (-not (Test-Path $folderPath)) {
            New-Item -ItemType Directory -Path $folderPath -Force | Out-Null
        }
    }
    # Create backup retention policy file
    $retentionPolicy = @{
        DailyBackups = 7
        WeeklyBackups = 4
        MonthlyBackups = 12
        MaxBackupSizeGB = 10
        CompressBackups = $true
        EncryptBackups = $true
        BackupSchedule = @{
            Daily = @{ Hour = 2; Minute = 30 }
            Weekly = @{ DayOfWeek = 'Sunday'; Hour = 3; Minute = 0 }
            Monthly = @{ DayOfMonth = 1; Hour = 4; Minute = 0 }
        }
    }
    $policyPath = Join-Path $BackupRootPath "retention_policy.json"
    $retentionPolicy | ConvertTo-Json -Depth 10 | Set-Content -Path $policyPath
    Write-Log "Backup system initialized at: $BackupRootPath" -Level 'Info'
    return $BackupRootPath
}
function New-CertificateBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Domain,
        [string]$BackupPath,
        [SecureString]$Password,
        [switch]$IncludePrivateKey,
        [switch]$Compress,
        [hashtable]$Metadata = @{}
    )
    if (-not $BackupPath) {
        $BackupPath = "$env:LOCALAPPDATA\AutoCert\Backups\Certificates"
    }
    if (-not $Password) {
        # Generate cryptographically secure password
        $secureBytes = New-Object byte[] 32
        [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($secureBytes)
        $securePassword = [System.Convert]::ToBase64String($secureBytes)
        # Create secure string directly without using ConvertTo-SecureString with plain text
        $Password = New-Object System.Security.SecureString
        $securePassword.ToCharArray() | ForEach-Object { $Password.AppendChar($_) }
        $Password.MakeReadOnly()
        # Store password hash for backup verification (not password itself)
        $passwordHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($securePassword))
        $passwordHashString = [System.Convert]::ToBase64String($passwordHash)
        Write-Log "Backup password hash: $passwordHashString" -Level 'Info'
    }
    try {
        # Create backup directory structure
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFolder = Join-Path $BackupPath "$Domain\$timestamp"
        New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
        # Get certificate from Posh-ACME
        $cert = Get-PACertificate -MainDomain $Domain -ErrorAction Stop
        if (-not $cert) {
            throw "Certificate not found for domain: $Domain"
        }
        # Create backup manifest
        $manifest = @{
            Domain = $Domain
            BackupDate = Get-Date
            BackupVersion = "2.0.0"
            CertificateThumbprint = $cert.Thumbprint
            ExpirationDate = $cert.NotAfter
            SubjectAlternativeNames = $cert.AllSANs
            BackupType = if ($IncludePrivateKey) { "Complete" } else { "PublicOnly" }
            Files = @()
            Metadata = $Metadata
        }
        # Backup certificate files
        $certFiles = @(
            @{ Source = $cert.CertFile; Destination = "certificate.crt"; Type = "Certificate" },
            @{ Source = $cert.ChainFile; Destination = "chain.crt"; Type = "Chain" },
            @{ Source = $cert.FullChainFile; Destination = "fullchain.crt"; Type = "FullChain" }
        )
        if ($IncludePrivateKey) {
            $certFiles += @{ Source = $cert.KeyFile; Destination = "private.key"; Type = "PrivateKey" }
        }
        foreach ($file in $certFiles) {
            if (Test-Path $file.Source) {
                $destinationPath = Join-Path $backupFolder $file.Destination
                Copy-Item -Path $file.Source -Destination $destinationPath -Force
                $manifest.Files += @{
                    FileName = $file.Destination
                    Type = $file.Type
                    Size = (Get-Item $destinationPath).Length
                    Hash = (Get-FileHash $destinationPath -Algorithm SHA256).Hash
                }
            }
        }
        # Create PFX export for easy restoration
        if ($IncludePrivateKey) {
            $pfxPath = Join-Path $backupFolder "certificate.pfx"
            $securePassword = $Password
            try {
                Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePassword | Out-Null
                $manifest.Files += @{
                    FileName = "certificate.pfx"
                    Type = "PFX"
                    Size = (Get-Item $pfxPath).Length
                    Hash = (Get-FileHash $pfxPath -Algorithm SHA256).Hash
                    PasswordProtected = $true
                }
            } catch {
                Write-Log "Failed to create PFX export: $($_.Exception.Message)" -Level 'Warning'
            }
        }
        # Save manifest
        $manifestPath = Join-Path $backupFolder "manifest.json"
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath
        # Compress if requested
        if ($Compress) {
            $archivePath = "$backupFolder.zip"
            Compress-Archive -Path $backupFolder -DestinationPath $archivePath -Force
            Remove-Item -Path $backupFolder -Recurse -Force
            $backupFolder = $archivePath
        }
        Write-Log "Certificate backup created for $Domain at: $backupFolder" -Level 'Info'
        return @{
            BackupPath = $backupFolder
            Manifest = $manifest
            PasswordLength = $Password.Length
        }
    } catch {
        Write-Log "Failed to create certificate backup for $Domain`: $($_.Exception.Message)" -Level 'Error'
        throw
    }
}
function Restore-CertificateFromBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [SecureString]$Password,
        [switch]$InstallToStore,
        [switch]$UpdateIISBindings,
        [switch]$Force
    )
    try {
        # Check if backup is compressed
        $isCompressed = $BackupPath.EndsWith('.zip')
        $workingPath = $BackupPath
        if ($isCompressed) {
            $tempPath = Join-Path $env:TEMP "AutoCert_Restore_$(Get-Date -Format 'yyyyMMddHHmmss')"
            Expand-Archive -Path $BackupPath -DestinationPath $tempPath -Force
            $workingPath = $tempPath
        }
        # Load manifest
        $manifestPath = Join-Path $workingPath "manifest.json"
        if (-not (Test-Path $manifestPath)) {
            throw "Backup manifest not found: $manifestPath"
        }
        $manifest = Get-Content $manifestPath | ConvertFrom-Json
        # Validate backup integrity
        foreach ($file in $manifest.Files) {
            $filePath = Join-Path $workingPath $file.FileName
            if (-not (Test-Path $filePath)) {
                throw "Backup file missing: $($file.FileName)"
            }
            $currentHash = (Get-FileHash $filePath -Algorithm SHA256).Hash
            if ($currentHash -ne $file.Hash) {
                throw "Backup file corrupted: $($file.FileName)"
            }
        }
        Write-Log "Backup validation passed for domain: $($manifest.Domain)" -Level 'Info'
        # Restore PFX if available
        $pfxFile = $manifest.Files | Where-Object { $_.Type -eq "PFX" } | Select-Object -First 1
        if ($pfxFile) {
            $pfxPath = Join-Path $workingPath $pfxFile.FileName
            if (-not $Password) {
                $Password = Read-Host "Enter password for PFX file" -AsSecureString
            }
            if ($InstallToStore) {
                $cert = Import-PfxCertificate -FilePath $pfxPath -CertStoreLocation Cert:\LocalMachine\My -Password $Password
                Write-Log "Certificate restored to certificate store with thumbprint: $($cert.Thumbprint)" -Level 'Info'
                if ($UpdateIISBindings) {
                    Update-IISBindingsForCertificate -Domain $manifest.Domain -CertificateThumbprint $cert.Thumbprint
                }
            }
        }
        # Restore individual files to Posh-ACME directory structure
        $poshAcmeDir = (Get-PAServer).Folder
        $certDir = Join-Path $poshAcmeDir $manifest.Domain
        if (-not (Test-Path $certDir)) {
            New-Item -ItemType Directory -Path $certDir -Force | Out-Null
        }
        $fileMapping = @{
            "certificate.crt" = "cert.cer"
            "chain.crt" = "chain.cer"
            "fullchain.crt" = "fullchain.cer"
            "private.key" = "cert.key"
        }
        foreach ($file in $manifest.Files) {
            if ($fileMapping.ContainsKey($file.FileName)) {
                $sourcePath = Join-Path $workingPath $file.FileName
                $destinationPath = Join-Path $certDir $fileMapping[$file.FileName]
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
            }
        }
        # Cleanup temporary files
        if ($isCompressed -and (Test-Path $tempPath)) {
            Remove-Item -Path $tempPath -Recurse -Force
        }
        Write-Log "Certificate restore completed for domain: $($manifest.Domain)" -Level 'Info'
        return $manifest
    } catch {
        Write-Log "Failed to restore certificate from backup: $($_.Exception.Message)" -Level 'Error'
        throw
    }
}
function Get-BackupHistory {
    [CmdletBinding()]
    param(
        [string]$Domain,
        [string]$BackupPath = "$env:LOCALAPPDATA\AutoCert\Backups\Certificates",
        [int]$MaxResults = 50
    )
    $backups = @()
    try {
        if ($Domain) {
            $domainPath = Join-Path $BackupPath $Domain
            if (Test-Path $domainPath) {
                $backupFolders = Get-ChildItem -Path $domainPath -Directory | Sort-Object Name -Descending
                foreach ($folder in ($backupFolders | Select-Object -First $MaxResults)) {
                    $manifestPath = Join-Path $folder.FullName "manifest.json"
                    if (Test-Path $manifestPath) {
                        $manifest = Get-Content $manifestPath | ConvertFrom-Json
                        $backups += @{
                            Domain = $manifest.Domain
                            BackupDate = $manifest.BackupDate
                            BackupPath = $folder.FullName
                            BackupType = $manifest.BackupType
                            Size = (Get-ChildItem $folder.FullName -Recurse | Measure-Object -Property Length -Sum).Sum
                            ExpirationDate = $manifest.ExpirationDate
                            FileCount = $manifest.Files.Count
                        }
                    }
                }
            }
        } else {
            # Get all domain backups
            $domainFolders = Get-ChildItem -Path $BackupPath -Directory
            foreach ($domainFolder in $domainFolders) {
                $domainBackups = Get-BackupHistory -Domain $domainFolder.Name -BackupPath $BackupPath -MaxResults ($MaxResults / $domainFolders.Count)
                $backups += $domainBackups
            }
        }
        return $backups | Sort-Object BackupDate -Descending | Select-Object -First $MaxResults
    } catch {
        Write-Log "Failed to get backup history: $($_.Exception.Message)" -Level 'Error'
        return @()
    }
}
function Remove-OldBackups {
    [CmdletBinding()]
    param(
        [string]$BackupPath = "$env:LOCALAPPDATA\AutoCert\Backups",
        [int]$DaysToKeep = 30,
        [switch]$WhatIf
    )
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $removedCount = 0
        $totalSizeFreed = 0
        $backupFolders = Get-ChildItem -Path $BackupPath -Recurse -Directory | Where-Object {
            $_.Name -match '^\d{8}_\d{6}$' -and $_.CreationTime -lt $cutoffDate
        }
        foreach ($folder in $backupFolders) {
            $folderSize = (Get-ChildItem $folder.FullName -Recurse | Measure-Object -Property Length -Sum).Sum
            if ($WhatIf) {
                Write-Warning -Message "Would remove: $($folder.FullName) ($([math]::Round($folderSize / 1MB, 2)) MB)"
            } else {
                Write-Log "Removing old backup: $($folder.FullName)" -Level 'Info'
                Remove-Item -Path $folder.FullName -Recurse -Force
                $removedCount++
                $totalSizeFreed += $folderSize
            }
        }
        if (-not $WhatIf) {
            Write-Log "Removed $removedCount old backups, freed $([math]::Round($totalSizeFreed / 1MB, 2)) MB" -Level 'Info'
        }
        return @{
            RemovedCount = $removedCount
            SizeFreedMB = [math]::Round($totalSizeFreed / 1MB, 2)
        }
    } catch {
        Write-Log "Failed to remove old backups: $($_.Exception.Message)" -Level 'Error'
        throw
    }
}
function Test-BackupIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [switch]$Detailed
    )
    try {
        $results = @{
            IsValid = $true
            Errors = @()
            Warnings = @()
            Details = @()
        }
        # Check if backup exists
        if (-not (Test-Path $BackupPath)) {
            $results.IsValid = $false
            $results.Errors += "Backup path not found: $BackupPath"
            return $results
        }
        # Handle compressed backups
        $isCompressed = $BackupPath.EndsWith('.zip')
        $workingPath = $BackupPath
        if ($isCompressed) {
            $tempPath = Join-Path $env:TEMP "AutoCert_Integrity_$(Get-Date -Format 'yyyyMMddHHmmss')"
            try {
                Expand-Archive -Path $BackupPath -DestinationPath $tempPath -Force
                $workingPath = $tempPath
            } catch {
                $results.IsValid = $false
                $results.Errors += "Failed to extract compressed backup: $($_.Exception.Message)"
                return $results
            }
        }
        # Load and validate manifest
        $manifestPath = Join-Path $workingPath "manifest.json"
        if (-not (Test-Path $manifestPath)) {
            $results.IsValid = $false
            $results.Errors += "Manifest file not found"
        } else {
            try {
                $manifest = Get-Content $manifestPath | ConvertFrom-Json
                $results.Details += "Manifest loaded"
                # Validate each file
                foreach ($file in $manifest.Files) {
                    $filePath = Join-Path $workingPath $file.FileName
                    if (-not (Test-Path $filePath)) {
                        $results.IsValid = $false
                        $results.Errors += "File missing: $($file.FileName)"
                        continue
                    }
                    # Check file size
                    $actualSize = (Get-Item $filePath).Length
                    if ($actualSize -ne $file.Size) {
                        $results.IsValid = $false
                        $results.Errors += "File size mismatch for $($file.FileName): Expected $($file.Size), Actual $actualSize"
                    }
                    # Check file hash
                    $actualHash = (Get-FileHash $filePath -Algorithm SHA256).Hash
                    if ($actualHash -ne $file.Hash) {
                        $results.IsValid = $false
                        $results.Errors += "Hash mismatch for $($file.FileName): File may be corrupted"
                    } else {
                        $results.Details += "File validated: $($file.FileName)"
                    }
                }
            } catch {
                $results.IsValid = $false
                $results.Errors += "Failed to parse manifest: $($_.Exception.Message)"
            }
        }
        # Cleanup temporary files
        if ($isCompressed -and (Test-Path $tempPath)) {
            Remove-Item -Path $tempPath -Recurse -Force
        }
        return $results
    } catch {
        return @{
            IsValid = $false
            Errors = @("Integrity check failed: $($_.Exception.Message)")
            Warnings = @()
            Details = @()
        }
    }
}


