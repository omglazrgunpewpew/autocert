# Functions/CertificateInstallation/Install-CertificateToStore.ps1
<#
    .SYNOPSIS
        Installs certificate to Windows Certificate Store
    .DESCRIPTION
        Handles installation of Let's Encrypt certificates to Windows certificate stores
        with support for exportable/non-exportable keys and user preference management.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to install
    .PARAMETER Settings
        Script settings object for preference management
    .PARAMETER StoreLocation
        Certificate store location (LocalMachine, CurrentUser)
    .PARAMETER StoreName
        Certificate store name (My, WebHosting, etc.)
    .OUTPUTS
        Returns $true if installation successful, $false otherwise
    .EXAMPLE
        Install-CertificateToStore -PACertificate $cert -Settings $settings
        Install-CertificateToStore -PACertificate $cert -Settings $settings -StoreLocation CurrentUser -StoreName My
#>
function Install-CertificateToStore
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate,

        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter()]
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$StoreLocation = 'LocalMachine',

        [Parameter()]
        [string]$StoreName = 'My'
    )

    Write-Host -Object "`nInstalling certificate to $StoreLocation\$StoreName store..." -ForegroundColor Cyan
    Write-ProgressHelper -Activity "Certificate Installation" -Status "Preparing certificate store installation..." -PercentComplete 25

    # Handle exportable key preference
    $exportableChoice = $null
    if ($null -ne $Settings.AlwaysExportable)
    {
        $usePreference = Read-Host "`nUse saved preference (Private Key Exportable: $($Settings.AlwaysExportable))? (Y/N/0 to go back)"
        if ($usePreference -eq '0')
        {
            return $false
        }
        if ($usePreference -match '^[Yy]$')
        {
            $exportableChoice = if ($Settings.AlwaysExportable) { 'Y' } else { 'N' }
        }
    }

    if (-not $exportableChoice)
    {
        $exportableChoice = Read-Host "`nMake private key exportable? (Y/N/0 to go back)"
        if ($exportableChoice -eq '0')
        {
            return $false
        }

        # Offer to save preference
        $savePreference = Read-Host "Save this as your default preference? (Y/N)"
        if ($savePreference -match '^[Yy]$')
        {
            $Settings.AlwaysExportable = $exportableChoice -match '^[Yy]$'
            Save-ScriptSettings -Settings $Settings
            Write-Information -MessageData "Preference saved." -InformationAction Continue
        }
    }

    $isNotExportable = $exportableChoice -match '^[Nn]$'
    Write-ProgressHelper -Activity "Certificate Installation" -Status "Installing to certificate store..." -PercentComplete 50

    try
    {
        # Prepare installation parameters
        $installParams = @{
            PACertificate = $PACertificate
            StoreLocation = $StoreLocation
            Verbose       = $true
        }

        if ($StoreName -ne 'My')
        {
            $installParams['StoreName'] = $StoreName
        }

        if ($isNotExportable)
        {
            $installParams['NotExportable'] = $true
        }

        # Install with retry logic
        if ($PSCmdlet.ShouldProcess("$($PACertificate.MainDomain)", "Install certificate to $StoreLocation\$StoreName"))
        {
            Invoke-WithRetry -ScriptBlock {
                Install-PACertificate @installParams
            } -MaxAttempts 3 -InitialDelaySeconds 2 `
                -OperationName "Certificate installation to $StoreLocation\$StoreName store" `
                -SuccessCondition { $? }
        }

        Write-ProgressHelper -Activity "Certificate Installation" -Status "Installation complete" -PercentComplete 100

        # Verify installation
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $StoreLocation)
        $store.Open("ReadOnly")
        $installedCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $PACertificate.Certificate.Thumbprint }
        $store.Close()

        if ($installedCert)
        {
            Write-Information -MessageData "`nOK Certificate installed to $StoreLocation\$StoreName store" -InformationAction Continue
            Write-Warning -Message "`nInstallation Details:"
            Write-Host -Object "  Store: $StoreLocation\$StoreName"
            Write-Host -Object "  Private Key Exportable: $(-not $isNotExportable)"
            Write-Host -Object "  Thumbprint: $($PACertificate.Certificate.Thumbprint)"
            Write-Host -Object "  Subject: $($PACertificate.Certificate.Subject)"
            Write-Log "Certificate installed to $StoreLocation\$StoreName for $($PACertificate.MainDomain)"
            return $true
        } else
        {
            throw "Certificate installation verification failed"
        }
    } catch
    {
        $msg = "Failed to install certificate to $StoreLocation\$StoreName store: $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'
        Write-Warning -Message "`nTroubleshooting suggestions:"
        Write-Host -Object "- Ensure you're running as Administrator"
        Write-Host -Object "- Check if the certificate store is accessible"
        Write-Host -Object "- Verify the certificate is valid and not corrupted"
        Read-Host "`nPress Enter to continue"
        return $false
    } finally
    {
        Write-Progress -Activity "Certificate Installation" -Completed
    }
}
