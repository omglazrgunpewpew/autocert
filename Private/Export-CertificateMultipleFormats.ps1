# Functions/CertificateInstallation/Export-CertificateMultipleFormats.ps1
<#
    .SYNOPSIS
        Exports certificate in multiple formats
    .DESCRIPTION
        Exports a Let's Encrypt certificate in multiple formats including PFX,
        PEM files, full chain, and creates metadata for comprehensive backup.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to export
    .OUTPUTS
        Returns $true if export successful, $false otherwise
    .EXAMPLE
        Export-CertificateMultipleFormats -PACertificate $cert
#>
function Export-CertificateMultipleFormat {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    Write-Host -Object "`nExporting certificate in multiple formats..." -ForegroundColor Cyan

    $exportDir = Read-Host "`nEnter directory for exports (default: Desktop) or 0 to go back"
    if ($exportDir -eq '0') {
        return $false
    }
    if (-not $exportDir) {
        $exportDir = [Environment]::GetFolderPath("Desktop")
    }

    # Create export directory if needed
    if (-not (Test-Path $exportDir)) {
        try {
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
            Write-Information -MessageData "Created directory: $exportDir" -InformationAction Continue
        }
        catch {
            Write-Error -Message "Failed to create directory: $exportDir"
            Read-Host "`nPress Enter to continue"
            return $false
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

        if ($PSCmdlet.ShouldProcess("$pfxPath", "Export PFX")) {
            Export-PACertificate -MainDomain $PACertificate.MainDomain -Type PFX -Path $pfxPath -Password $password
            $exportResults += "PFX: $pfxPath"
        }

        # Export individual PEM files
        Write-ProgressHelper -Activity "Multi-Format Export" -Status "Exporting PEM files..." -PercentComplete 50
        $pemContent = Get-CertificatePEMContent -Certificate $PACertificate -IncludeKey

        if ($pemContent.Success) {
            $certPemPath = Join-Path $exportDir "${baseName}_${timestamp}_cert.pem"
            $keyPemPath = Join-Path $exportDir "${baseName}_${timestamp}_key.pem"

            if ($PSCmdlet.ShouldProcess("$certPemPath", "Export certificate PEM")) {
                Set-Content -Path $certPemPath -Value $pemContent.CertContent -Encoding ASCII
                $exportResults += "Certificate PEM: $certPemPath"
            }

            if ($PSCmdlet.ShouldProcess("$keyPemPath", "Export private key PEM")) {
                Set-Content -Path $keyPemPath -Value $pemContent.KeyContent -Encoding ASCII
                $exportResults += "Private Key PEM: $keyPemPath"
            }
        }

        # Export full chain if available
        Write-ProgressHelper -Activity "Multi-Format Export" -Status "Exporting full chain..." -PercentComplete 75
        if ($PACertificate.FullChainFile -and (Test-Path $PACertificate.FullChainFile)) {
            $fullChainPath = Join-Path $exportDir "${baseName}_${timestamp}_fullchain.pem"

            if ($PSCmdlet.ShouldProcess("$fullChainPath", "Export full chain PEM")) {
                Copy-Item -Path $PACertificate.FullChainFile -Destination $fullChainPath
                $exportResults += "Full Chain PEM: $fullChainPath"
            }
        }

        # Create metadata file
        Write-ProgressHelper -Activity "Multi-Format Export" -Status "Creating metadata..." -PercentComplete 90
        $metadataPath = Join-Path $exportDir "${baseName}_${timestamp}_metadata.json"

        $metadata = @{
            Domain        = $PACertificate.MainDomain
            AllDomains    = $PACertificate.AllSANs
            Subject       = $PACertificate.Certificate.Subject
            Issuer        = $PACertificate.Certificate.Issuer
            Thumbprint    = $PACertificate.Certificate.Thumbprint
            ValidFrom     = $PACertificate.Certificate.NotBefore
            ValidUntil    = $PACertificate.Certificate.NotAfter
            ExportDate    = Get-Date
            ExportedFiles = $exportResults
        }

        if ($PSCmdlet.ShouldProcess("$metadataPath", "Create metadata file")) {
            $metadata | ConvertTo-Json -Depth 10 | Set-Content -Path $metadataPath
            $exportResults += "Metadata: $metadataPath"
        }

        Write-ProgressHelper -Activity "Multi-Format Export" -Status "Export complete" -PercentComplete 100

        Write-Host -Object "`nOK Multi-format export completed" -ForegroundColor Green
        Write-Warning -Message "`nExported Files:"
        $exportResults | ForEach-Object { Write-Host -Object "  $_" }

        Write-Log "Multi-format export completed for $($PACertificate.MainDomain)"
        return $true

    }
    catch {
        Write-Error -Message "Multi-format export failed: $_"
        Write-Log "Multi-format export failed for $($PACertificate.MainDomain): $_" -Level 'Error'
        Read-Host "`nPress Enter to continue"
        return $false
    }
    finally {
        Write-Progress -Activity "Multi-Format Export" -Completed
    }
}

# Backward compatibility wrapper (pluralized name expected by calling code)
if (-not (Get-Command Export-CertificateMultipleFormats -ErrorAction SilentlyContinue)) {
    function Export-CertificateMultipleFormats {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [Parameter(Mandatory = $true)]
            [object]$PACertificate
        )
        Export-CertificateMultipleFormat -PACertificate $PACertificate
    }
}
