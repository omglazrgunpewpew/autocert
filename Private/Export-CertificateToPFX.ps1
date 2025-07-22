# Functions/CertificateInstallation/Export-CertificateToPFX.ps1
<#
    .SYNOPSIS
        Exports certificate as PFX file
    .DESCRIPTION
        Exports a Let's Encrypt certificate as a password-protected PFX file
        with path validation and user preference management.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to export
    .PARAMETER Settings
        Script settings object for default path preferences
    .PARAMETER Force
        Forces overwrite of existing files
    .OUTPUTS
        Returns $true if export successful, $false otherwise
    .EXAMPLE
        Export-CertificateToPFX -PACertificate $cert -Settings $settings
        Export-CertificateToPFX -PACertificate $cert -Settings $settings -Force
#>
function Export-CertificateToPFX
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate,

        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter()]
        [switch]$Force
    )

    Write-Host -Object "`nExporting certificate as PFX file..." -ForegroundColor Cyan
    Write-ProgressHelper -Activity "Certificate Export" -Status "Configuring export options..." -PercentComplete 25

    # Determine export path
    $defaultPath = $Settings.DefaultPFXLocation
    if (-not $defaultPath)
    {
        $defaultPath = [Environment]::GetFolderPath("Desktop")
    }

    $defaultFileName = "$($PACertificate.MainDomain.Replace('*', 'wildcard')).pfx"
    $defaultCertPath = Join-Path $defaultPath $defaultFileName

    $certPath = Read-Host "`nEnter path for PFX file (default: $defaultCertPath) or 0 to go back"
    if ($certPath -eq '0')
    {
        return $false
    }
    if (-not $certPath)
    {
        $certPath = $defaultCertPath
    }

    # Validate and create directory if needed
    $certDir = Split-Path $certPath -Parent
    if (-not (Test-Path $certDir))
    {
        try
        {
            New-Item -ItemType Directory -Path $certDir -Force | Out-Null
            Write-Information -MessageData "Created directory: $certDir" -InformationAction Continue
        } catch
        {
            Write-Error -Message "Failed to create directory: $certDir"
            Read-Host "`nPress Enter to continue"
            return $false
        }
    }

    # Check if file already exists
    if ((Test-Path $certPath) -and -not $Force)
    {
        $overwrite = Read-Host "`nFile exists. Overwrite? (Y/N)"
        if ($overwrite -notmatch '^[Yy]$')
        {
            return $false
        }
    }

    Write-ProgressHelper -Activity "Certificate Export" -Status "Setting password..." -PercentComplete 40

    # Get password for PFX
    $certPassword = Read-Host "`nEnter password for PFX file (leave blank for no password) or 0 to go back" -AsSecureString
    $passwordString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($certPassword))
    if ($passwordString -eq '0')
    {
        return $false
    }

    Write-ProgressHelper -Activity "Certificate Export" -Status "Exporting certificate..." -PercentComplete 60

    try
    {
        # Export with retry logic
        if ($PSCmdlet.ShouldProcess("$certPath", "Export certificate as PFX"))
        {
            Invoke-WithRetry -ScriptBlock {
                Export-PACertificate -MainDomain $PACertificate.MainDomain -Type PFX -Path $certPath -Password $certPassword
            } -MaxAttempts 3 -InitialDelaySeconds 2 `
                -OperationName "PFX export" `
                -SuccessCondition { Test-Path $certPath }
        }

        Write-ProgressHelper -Activity "Certificate Export" -Status "Export complete" -PercentComplete 100

        # Verify export and show details
        $fileInfo = Get-Item $certPath
        Write-Information -MessageData "`nOK Certificate exported" -InformationAction Continue
        Write-Warning -Message "`nExport Details:"
        Write-Host -Object "  File: $certPath"
        Write-Host -Object "  Size: $($fileInfo.Length) bytes"
        Write-Host -Object "  Created: $($fileInfo.CreationTime)"
        Write-Host -Object "  Password Protected: $(if ($passwordString) { 'Yes' } else { 'No' })"

        Write-Log "Certificate exported as PFX to $certPath"

        # Update default path setting
        $savePathPreference = Read-Host "`nSave this directory as default PFX location? (Y/N)"
        if ($savePathPreference -match '^[Yy]$')
        {
            $Settings.DefaultPFXLocation = Split-Path $certPath -Parent
            Save-ScriptSettings -Settings $Settings
            Write-Information -MessageData "Default PFX location updated." -InformationAction Continue
        }

        return $true
    } catch
    {
        $msg = "Failed to export certificate as PFX: $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'
        Read-Host "`nPress Enter to continue"
        return $false
    } finally
    {
        Write-Progress -Activity "Certificate Export" -Completed
    }
}
