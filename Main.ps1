# Main.ps1 - Refactored
<#
    .SYNOPSIS
        AutoCert Let's Encrypt Certificate Management System

    .DESCRIPTION
        This script provides an interface for Let's Encrypt certificate management
        using Posh-ACME with error handling, certificate caching,
        DNS provider auto-detection, renewal scheduling, and system health monitoring.

    .PARAMETER RenewAll
        Runs in non-interactive mode to renew all certificates that need renewal.
        This mode is designed for scheduled tasks and automation.

    .PARAMETER NonInteractive
        Runs without user interaction (for scheduled tasks).
        Suppresses progress bars and user prompts.

    .PARAMETER Force
        Forces operations even if they might not be necessary.
        Use with caution as it bypasses safety checks.

    .PARAMETER ConfigTest
        Runs configuration validation and exits.
        Returns exit code 0 for success, 1 for failure.

    .PARAMETER LogLevel
        Sets the logging level (Debug, Info, Warning, Error).
        Default is 'Info'. Debug provides verbose output.

    .NOTES
        Version: 2.0.0
        Author: AutoCert Development Team
        Requires: PowerShell 5.1+, Posh-ACME module

        This script requires Administrator privileges for certificate store operations.

    .EXAMPLE
        .\Main.ps1
        Runs the interactive certificate management interface.

    .EXAMPLE
        .\Main.ps1 -RenewAll -NonInteractive
        Runs automatic renewal check for all certificates (for scheduled tasks).

    .EXAMPLE
        .\Main.ps1 -ConfigTest
        Validate configuration and exit with status code.
#>

[CmdletBinding()]
param(
    [switch]$RenewAll,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$ConfigTest,
    [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
    [string]$LogLevel = 'Info'
)

# Script metadata
$script:ScriptVersion = "2.0.0"
$script:ScriptName = "AutoCert Certificate Management System"
$script:StartTime = Get-Date

# Ensure script runs with administrative privileges for certificate operations
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning -Message "Administrator privileges recommended for full certificate operations."
    if ($ConfigTest) {
        Write-Warning -Message "Continuing configuration test without elevation (some store tests will be skipped)."
    }
    else {
        Write-Warning -Message "Please run this script as an administrator."
        if (-not $NonInteractive) {
            Read-Host "Press Enter to exit"
        }
        exit 1
    }
}

# Auto-detect testing/development environment
# Check if we're running from the development repository
$repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\Posh-ACME'
if ((Test-Path $repoModulePath) -and -not $env:AUTOCERT_TESTING_MODE) {
    Write-Verbose "Development environment detected: Setting testing mode to prevent module updates"
    $env:AUTOCERT_TESTING_MODE = $true
    $env:POSHACME_SKIP_UPGRADE_CHECK = $true
}

# Set error handling and preferences
$ErrorActionPreference = 'Stop'
$ProgressPreference = if ($NonInteractive) { 'SilentlyContinue' } else { 'Continue' }
$VerbosePreference = if ($LogLevel -eq 'Debug') { 'Continue' } else { 'SilentlyContinue' }

# Initialize script-wide variables
$script:LoadedModules = @()
$script:InitializationErrors = @()

# Load core system modules
try {
    . "$PSScriptRoot\Core\SystemInitialization.ps1"
    . "$PSScriptRoot\Core\RenewalOperations.ps1"
    . "$PSScriptRoot\Core\SystemDiagnostics.ps1"
    . "$PSScriptRoot\Core\RenewalConfig.ps1"
}
catch {
    Write-Error -Message "Failed to load core system modules: $($_.Exception.Message)"
    Write-Error -Message "Please ensure all Core module files are present and accessible."
    if (-not $NonInteractive) {
        Read-Host "Press Enter to exit"
    }
    exit 1
}

# Renewal mode for scheduled tasks
if ($RenewAll) {
    # Initialize modules for renewal mode
    $moduleLoadSuccess = Initialize-ScriptModule -NonInteractive:$NonInteractive
    if (-not $moduleLoadSuccess) {
        exit 1
    }

    Write-Information -MessageData "Running in automatic renewal mode..." -InformationAction Continue
    Write-AutoCertLog "Starting automatic renewal process (Version: $script:ScriptVersion)" -Level 'Info'

    $exitCode = Invoke-AutomaticRenewal -Force:$Force -NonInteractive:$NonInteractive
    exit $exitCode
}

# Configuration test mode
if ($ConfigTest) {
    Write-Information -MessageData "AutoCert Certificate Management System - Configuration Test" -InformationAction Continue
    Write-Information -MessageData "Version: $script:ScriptVersion" -InformationAction Continue

    # Load basic modules needed for configuration test
    try {
        . "$PSScriptRoot\Core\Logging.ps1"
        . "$PSScriptRoot\Core\Initialize-PoshAcme.ps1"
    }
    catch {
        Write-Error -Message "Failed to load basic modules for configuration test: $($_.Exception.Message)"
        exit 1
    }

    $configValid = Test-SystemConfiguration

    if ($configValid) {
        Write-Information -MessageData "`nConfiguration test passed." -InformationAction Continue
        exit 0
    }
    else {
        Write-Error -Message "`nConfiguration test failed."
        exit 1
    }
}

# Interactive mode functions
function Invoke-SingleCertificateManagement {
    <#
    .SYNOPSIS
        Manages a single certificate with interactive options

    .DESCRIPTION
        Provides a sub-menu for managing individual certificates
        including renewal, installation, revocation, and viewing details.

    .PARAMETER CertificateOrder
        The certificate order object to manage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$CertificateOrder
    )

    while ($true) {
        Clear-Host
        $mainDomain = $CertificateOrder.MainDomain
        Write-Information -MessageData ("`n" + "=" * 70) -InformationAction Continue
        Write-Information -MessageData "    MANAGING CERTIFICATE: $mainDomain" -InformationAction Continue
        Write-Information -MessageData ("=" * 70) -InformationAction Continue

        try {
            $certDetails = Get-PACertificate -MainDomain $mainDomain
            $daysUntilExpiry = ($certDetails.Certificate.NotAfter - (Get-Date)).Days
            Write-Information -MessageData "Status: Valid" -InformationAction Continue
            Write-Information -MessageData "Expires: $($certDetails.Certificate.NotAfter) ($daysUntilExpiry days remaining)" -InformationAction Continue
            Write-Information -MessageData "Thumbprint: $($certDetails.Thumbprint)" -InformationAction Continue
            Write-Information -MessageData "SANs: $($certDetails.SANs -join ', ')" -InformationAction Continue
        }
        catch {
            Write-Error -Message "Status: Could not retrieve certificate details."
        }

        Write-Information -MessageData "`nAvailable Actions for ${mainDomain}:" -InformationAction Continue
        Write-Warning -Message "1. Force Renew"
        Write-Information -MessageData "2. Re-install Certificate" -InformationAction Continue
        Write-Error -Message "3. Revoke Certificate"
        Write-Information -MessageData "4. View Details" -InformationAction Continue
        Write-Information -MessageData "0. Return to Main Menu" -InformationAction Continue
        Write-Information -MessageData ("`n" + "=" * 70) -InformationAction Continue

        $choice = Read-Host "Enter your choice for '$mainDomain'"

        switch ($choice) {
            '1' {
                Write-Warning -Message "Forcing renewal for $mainDomain..."
                try {
                    $renewed = New-PACertificate -MainDomain $mainDomain -Force
                    if ($renewed) {
                        Write-Information -MessageData "Certificate for $mainDomain renewed." -InformationAction Continue
                    }
                    else {
                        Write-Warning -Message "Renewal failed. Check logs for details."
                    }
                }
                catch {
                    Write-Error -Message "An error occurred during renewal: $($_.Exception.Message)"
                }
                Read-Host "Press Enter to continue"
            }
            '2' {
                # Call existing Install-Certificate function
                try {
                    $cert = Get-PACertificate -MainDomain $mainDomain
                    if ($cert) {
                        Install-Certificate -PACertificate $cert
                    }
                    else {
                        Write-Warning -Message "Certificate not found for $mainDomain"
                    }
                }
                catch {
                    Write-Error -Message "Failed to install certificate: $($_.Exception.Message)"
                }
                Read-Host "Press Enter to continue"
            }
            '3' {
                # Call existing Revoke-Certificate function
                Write-Warning -Message "Note: This will show all certificates available for revocation."
                Revoke-Certificate
                Read-Host "Press Enter to continue"
                return # Exit sub-menu after revoke
            }
            '4' {
                Get-PAOrder -MainDomain $mainDomain | Format-List
                Read-Host "Press Enter to continue"
            }
            '0' { return }
            default { Write-Warning -Message "Invalid option. Please try again." }
        }
    }
}

# Main script execution starts here
try {
    # Initialize system
    $moduleLoadSuccess = Initialize-ScriptModule -NonInteractive:$NonInteractive
    if (-not $moduleLoadSuccess) {
        exit 1
    }

    # Main interactive loop
    while ($true) {
        Show-Menu
        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            '1' {
                Invoke-MenuOperation -Operation { Register-Certificate } -OperationName "certificate registration"
            }
            '2' {
                Invoke-MenuOperation -Operation { Install-Certificate } -OperationName "certificate installation"
            }
            '3' {
                Invoke-MenuOperation -Operation { Set-AutomaticRenewal } -OperationName "automatic renewal configuration"
            }
            '4' {
                Show-CertificateManagementMenu
            }
            '5' {
                Invoke-MenuOperation -Operation { Show-Options } -OperationName "options configuration"
            }
            '6' {
                Show-CredentialManagementMenu
            }
            '7' {
                Test-SystemHealth
            }
            '8' {
                Show-CompleteViewDeploymentMenu
            }
            'S' {
                Show-Help
            }
            '0' {
                Write-Warning -Message "Exiting..."
                exit 0
            }
            default {
                Write-Warning -Message "Invalid option. Please try again."
                Read-Host "Press Enter to continue"
            }
        }
    }

}
catch {
    $criticalError = "Critical application error: $($_.Exception.Message)"
    Write-Error -Message $criticalError

    if (Get-Command Write-AutoCertLog -ErrorAction SilentlyContinue) {
        Write-AutoCertLog $criticalError -Level 'Error'
    }

    Write-Error -Message "`nThe application encountered a critical error and must exit."
    Write-Warning -Message "Error details have been logged for troubleshooting."

    # Error information
    Write-Error -Message "`nError Information:"
    Write-Error -Message "  Message: $($_.Exception.Message)"
    Write-Error -Message "  Type: $($_.Exception.GetType().Name)"
    Write-Error -Message "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"
    Write-Error -Message "  Time: $(Get-Date)"

    Write-Warning -Message "`nTroubleshooting Resources:"
    Write-Information -MessageData "* Log files: $env:LOCALAPPDATA\Posh-ACME\certificate_script.log" -InformationAction Continue
    Write-Information -MessageData "* Run configuration test: .\Main.ps1 -ConfigTest" -InformationAction Continue
    Write-Warning -Message "* Check system health: .\Main.ps1 and select option 7"
    Write-Warning -Message "* Verify all script files are present and accessible"

    if (-not $NonInteractive) {
        Read-Host "Press Enter to exit"
    }
    exit 1

}
finally {
    # Cleanup and final logging
    $sessionDuration = (Get-Date) - $script:StartTime
    Write-AutoCertLog "Application session ended (Duration: $sessionDuration, Version: $script:ScriptVersion)" -Level 'Info'

    # Clear any sensitive data from memory
    if (Get-Variable -Name "cert*" -ErrorAction SilentlyContinue) {
        Remove-Variable -Name "cert*" -Force -ErrorAction SilentlyContinue
    }

    # Clean up progress indicators
    Write-Progress -Activity "Certificate Management" -Completed -ErrorAction SilentlyContinue
}




