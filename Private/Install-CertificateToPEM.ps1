# Functions/CertificateInstallation/Install-CertificateToPEM.ps1
<#
    .SYNOPSIS
        Installs certificate as PEM files for Recording Server
    .DESCRIPTION
        Extracts and saves certificate and private key as PEM files
        to the Recording Server certificate directory.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to install
    .OUTPUTS
        Returns $true if installation successful, $false otherwise
    .EXAMPLE
        Install-CertificateToPEM -PACertificate $cert
#>
function Install-CertificateToPEM
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    Write-Host -Object "`nInstalling certificate to Recording Server..." -ForegroundColor Cyan
    Write-ProgressHelper -Activity "Certificate Installation" -Status "Locating Recording Server directory..." -PercentComplete 25

    $certDir = Get-RSCertFolder
    if ($null -eq $certDir)
    {
        Write-Error -Message "Recording Server certificate directory not found."
        Read-Host "`nPress Enter to continue"
        return $false
    }

    Write-Information -MessageData "Using Recording Server directory: $certDir" -InformationAction Continue
    Write-ProgressHelper -Activity "Certificate Installation" -Status "Extracting certificate content..." -PercentComplete 40

    # Extract certificate and key content
    $pemContent = Get-CertificatePEMContent -Certificate $PACertificate -IncludeKey
    if (-not $pemContent.Success)
    {
        Write-Error -Message "Failed to extract certificate content: $($pemContent.ErrorMessage)"
        Read-Host "`nPress Enter to continue"
        return $false
    }

    Write-ProgressHelper -Activity "Certificate Installation" -Status "Saving PEM files..." -PercentComplete 60

    try
    {
        # Save PEM files with auto-versioning
        if ($PSCmdlet.ShouldProcess("$certDir", "Save PEM files for $($PACertificate.MainDomain)"))
        {
            $result = Save-PEMFiles -directory $certDir `
                -certContent $pemContent.CertContent `
                -keyContent $pemContent.KeyContent
        }

        if ($result)
        {
            Write-ProgressHelper -Activity "Certificate Installation" -Status "Installation complete" -PercentComplete 100
            Write-Information -MessageData "`nOK Certificate and private key saved" -InformationAction Continue
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
            Write-Host -Object "- Restart the Recording Server service"
            Write-Host -Object "- Update configuration files with new certificate paths"
            Write-Host -Object "- Test HTTPS connectivity"

            return $true
        }
    } catch
    {
        Write-Error -Message "Failed to save PEM files: $($_.Exception.Message)"
        Read-Host "`nPress Enter to continue"
        return $false
    } finally
    {
        Write-Progress -Activity "Certificate Installation" -Completed
    }

    return $false
}
