# Main.ps1
<#
    .SYNOPSIS
        Main script for certificate management capabilities.

    .DESCRIPTION
        This script provides an interface for Let's Encrypt certificate management
        using Posh-ACME with error handling, caching, DNS provider auto-detection,
        and renewal scheduling.

    .PARAMETER RenewAll
        Runs in non-interactive mode to renew all certificates that need renewal.

    .PARAMETER NonInteractive
        Runs without user interaction (for scheduled tasks).

    .PARAMETER Force
        Forces operations even if they might not be necessary.

    .PARAMETER ConfigTest
        Runs configuration validation and exits.

    .PARAMETER LogLevel
        Sets the logging level (Debug, Info, Warning, Error).

    .NOTES
        Must be run as Administrator for certificate store operations.
        Compatible with PowerShell 5.1 and PowerShell 7+.

    .EXAMPLE
        .\Main.ps1
        Run in interactive mode

    .EXAMPLE
        .\Main.ps1 -RenewAll -NonInteractive
        Run automatic renewal (for scheduled tasks)

    .EXAMPLE
        .\Main.ps1 -ConfigTest
        Validate configuration and exit
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
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning -Message "Administrator privileges required for certificate operations."
    Write-Warning -Message "Please run this script as an administrator."

    if (-not $NonInteractive) {
        Read-Host "Press Enter to exit"
    }
    Exit 1
}

# Set error handling and preferences
$ErrorActionPreference = 'Stop'
$ProgressPreference = if ($NonInteractive) { 'SilentlyContinue' } else { 'Continue' }
$VerbosePreference = if ($LogLevel -eq 'Debug') { 'Continue' } else { 'SilentlyContinue' }

# Initialize script-wide variables
$script:LoadedModules = @()
$script:InitializationErrors = @()

# Module loading with dependency tracking
function Initialize-ScriptModules {
    [CmdletBinding()]
    param()

    try {
        if (-not $NonInteractive) {
            Write-Information -MessageData "Loading certificate management system..." -InformationAction Continue
            Write-ProgressHelper -Activity "System Initialization" -Status "Loading core modules..." -PercentComplete 10
        }

        # Define module loading order with dependencies
        $moduleLoadOrder = @(
            @{ Path = "$PSScriptRoot\Core\Logging.ps1"; Name = "Logging"; Critical = $true },
            @{ Path = "$PSScriptRoot\Core\Helpers.ps1"; Name = "Helpers"; Critical = $true },
            @{ Path = "$PSScriptRoot\Core\Initialize-PoshAcme.ps1"; Name = "PoshACME Initialization"; Critical = $true },
            @{ Path = "$PSScriptRoot\Core\ConfigurationManager.ps1"; Name = "Configuration Manager"; Critical = $true },
            @{ Path = "$PSScriptRoot\Core\CircuitBreaker.ps1"; Name = "Circuit Breaker"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\HealthMonitor.ps1"; Name = "Health Monitor"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\BackupManager.ps1"; Name = "Backup Manager"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\NotificationManager.ps1"; Name = "Notification Manager"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\CertificateCache.ps1"; Name = "Certificate Cache"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\DNSProviderDetection.ps1"; Name = "DNS Provider Detection"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\RenewalConfig.ps1"; Name = "Renewal Configuration"; Critical = $false },
            # UI modules
            @{ Path = "$PSScriptRoot\UI\MainMenu.ps1"; Name = "Main Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\UI\CertificateMenu.ps1"; Name = "Certificate Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\UI\CredentialMenu.ps1"; Name = "Credential Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\UI\HelpSystem.ps1"; Name = "Help System"; Critical = $false },
            # Utilities modules
            @{ Path = "$PSScriptRoot\Utilities\ErrorHandling.ps1"; Name = "Error Handling"; Critical = $true },
            @{ Path = "$PSScriptRoot\Utilities\HealthCheck.ps1"; Name = "Health Check"; Critical = $false },
            @{ Path = "$PSScriptRoot\Utilities\Configuration.ps1"; Name = "Configuration Validation"; Critical = $true },
            @{ Path = "$PSScriptRoot\Utilities\RenewalManager.ps1"; Name = "Renewal Manager"; Critical = $false },
            @{ Path = "$PSScriptRoot\Utilities\ModuleManager.ps1"; Name = "Module Manager"; Critical = $false },
            # Function modules
            @{ Path = "$PSScriptRoot\Functions\Register-Certificate.ps1"; Name = "Certificate Registration"; Critical = $true },
            @{ Path = "$PSScriptRoot\Functions\Install-Certificate.ps1"; Name = "Certificate Installation"; Critical = $true },
            @{ Path = "$PSScriptRoot\Functions\Revoke-Certificate.ps1"; Name = "Certificate Revocation"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Remove-Certificate.ps1"; Name = "Certificate Removal"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Get-ExistingCertificates.ps1"; Name = "Certificate Listing"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Set-AutomaticRenewal.ps1"; Name = "Automatic Renewal"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Show-Options.ps1"; Name = "Options"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Update-AllCertificates.ps1"; Name = "Certificate Updates"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Manage-Credentials.ps1"; Name = "Credential Management"; Critical = $false }
        )

        $totalModules = $moduleLoadOrder.Count
        $loadedCount = 0

        foreach ($module in $moduleLoadOrder) {
            try {
                if (Test-Path $module.Path) {
                    . $module.Path
                    $script:LoadedModules += $module.Name
                    $loadedCount++

                    if (-not $NonInteractive) {
                        $percentComplete = [math]::Round(($loadedCount / $totalModules) * 80) + 10
                        Write-ProgressHelper -Activity "System Initialization" -Status "Loaded: $($module.Name)" -PercentComplete $percentComplete
                    }

                    Write-Verbose "Loaded module: $($module.Name)"
                } else {
                    $errorMsg = "Module file not found: $($module.Path)"
                    $script:InitializationErrors += $errorMsg

                    if ($module.Critical) {
                        throw $errorMsg
                    } else {
                        Write-Warning -Message $errorMsg
                    }
                }
            } catch {
                $errorMsg = "Failed to load module '$($module.Name)': $($_.Exception.Message)"
                $script:InitializationErrors += $errorMsg

                if ($module.Critical) {
                    throw $errorMsg
                } else {
                    Write-Warning -Message $errorMsg
                }
            }
        }

        if (-not $NonInteractive) {
            Write-ProgressHelper -Activity "System Initialization" -Status "Finalizing..." -PercentComplete 95
        }

        # Verify critical functions are available
        $criticalFunctions = @('Register-Certificate', 'Install-Certificate', 'Write-Log', 'Show-Menu', 'Show-CertificateManagementMenu', 'Show-CredentialManagementMenu', 'Show-Help', 'Test-SystemHealth')
        foreach ($func in $criticalFunctions) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                throw "Critical function '$func' is not available"
            }
        }

        if (-not $NonInteractive) {
            Write-ProgressHelper -Activity "System Initialization" -Status "Complete" -PercentComplete 100
            Write-Progress -Activity "System Initialization" -Completed
        }

        Write-Log "Certificate management system loaded (Version: $script:ScriptVersion)" -Level 'Info'
        Write-Log "Loaded modules: $($script:LoadedModules -join ', ')" -Level 'Debug'

        if ($script:InitializationErrors.Count -gt 0) {
            Write-Log "Initialization warnings: $($script:InitializationErrors.Count)" -Level 'Warning'
        }

        return $true

    } catch {
        $criticalError = "Failed to load required modules: $($_.Exception.Message)"
        Write-Error -Message $criticalError

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $criticalError -Level 'Error'
        }

        Write-Error -Message "Please ensure all script files are present and accessible."
        Write-Error -Message "Missing modules will prevent the system from functioning correctly."

        if (-not $NonInteractive) {
            Read-Host "Press Enter to exit"
        }

        return $false
    }
}

# Configuration validation function
function Test-SystemConfiguration {
    [CmdletBinding()]
    param()

    Write-Host -Object "Running configuration validation..." -ForegroundColor Cyan

    $configIssues = @()
    $configWarnings = @()

    try {
        # Test PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 5) {
            $configIssues += "PowerShell version $($PSVersionTable.PSVersion) is not supported. Minimum version 5.1 required."
        }

        # Test Posh-ACME module
        if (-not (Get-Module -Name Posh-ACME -ListAvailable)) {
            $configIssues += "Posh-ACME module not found. Run 'Install-Module Posh-ACME' to install."
        }

        # Test script files
        $requiredFiles = @(
            "$PSScriptRoot\Core\Logging.ps1",
            "$PSScriptRoot\Core\Helpers.ps1",
            "$PSScriptRoot\Functions\Register-Certificate.ps1",
            "$PSScriptRoot\Functions\Install-Certificate.ps1"
        )

        foreach ($file in $requiredFiles) {
            if (-not (Test-Path $file)) {
                $configIssues += "Required file missing: $file"
            }
        }

        # Test write permissions
        try {
            $testPath = "$env:LOCALAPPDATA\Posh-ACME\config_test.tmp"
            New-Item -Path (Split-Path $testPath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            "test" | Out-File -FilePath $testPath -ErrorAction Stop
            Remove-Item $testPath -Force -ErrorAction SilentlyContinue
        } catch {
            $configIssues += "Insufficient write permissions to %LOCALAPPDATA%\Posh-ACME\"
        }

        # Test internet connectivity
        try {
            $response = Invoke-WebRequest -Uri "https://acme-v02.api.letsencrypt.org/directory" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            if ($response.StatusCode -ne 200) {
                $configWarnings += "Let's Encrypt API accessibility issue (Status: $($response.StatusCode))"
            }
        } catch {
            $configWarnings += "Cannot reach Let's Encrypt API: $($_.Exception.Message)"
        }

        # Display results
        Write-Host -Object "`nConfiguration Validation Results:" -ForegroundColor Cyan

        if ($configIssues.Count -eq 0) {
            Write-Information -MessageData "✓ Configuration validation passed" -InformationAction Continue
        } else {
            Write-Error -Message "✗ Configuration issues found:"
            $configIssues | ForEach-Object { Write-Error -Message "  • $_" }
        }

        if ($configWarnings.Count -gt 0) {
            Write-Warning -Message "⚠ Configuration warnings:"
            $configWarnings | ForEach-Object { Write-Warning -Message "  • $_" }
        }

        return ($configIssues.Count -eq 0)

    } catch {
        Write-Error -Message "Configuration validation failed: $($_.Exception.Message)"
        return $false
    }
}

# Renewal mode for scheduled tasks
if ($RenewAll) {
    # Initialize modules for renewal mode
    $moduleLoadSuccess = Initialize-ScriptModules
    if (-not $moduleLoadSuccess) {
        Exit 1
    }

    Write-Host -Object "Running in automatic renewal mode..." -ForegroundColor Cyan
    Write-Log "Starting automatic renewal process (Version: $script:ScriptVersion)" -Level 'Info'

    try {
        # Load renewal configuration
        $config = Get-RenewalConfig

        # Get all certificates and check renewal status
        $orders = Get-PAOrder
        if (-not $orders) {
            Write-Warning -Message "No certificates found to renew."
            Write-Log "No certificates found for renewal" -Level 'Warning'
            Exit 0
        }

        Write-Information -MessageData "Found $($orders.Count) certificate(s) to check for renewal." -InformationAction Continue

        $renewalCount = 0
        $errorCount = 0
        $skippedCount = 0
        $results = @()

        foreach ($order in $orders) {
            $mainDomain = $order.MainDomain
            Write-Host -Object "`nProcessing certificate for $mainDomain..." -ForegroundColor Cyan

            try {
                # Get certificate details with caching
                $cert = Get-CachedPACertificate -MainDomain $mainDomain -Force:$Force

                # Check if renewal is needed
                $renewalThreshold = (Get-Date).AddDays($config.RenewalThresholdDays)
                $needsRenewal = $cert.Certificate.NotAfter -le $renewalThreshold

                if (-not $needsRenewal -and -not $Force) {
                    Write-Information -MessageData "Certificate for $mainDomain is still valid until $($cert.Certificate.NotAfter). Skipping renewal." -InformationAction Continue
                    $skippedCount++

                    $results += @{
                        Domain          = $mainDomain
                        Status          = "Skipped"
                        ExpiryDate      = $cert.Certificate.NotAfter
                        DaysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                    }
                    continue
                }

                # Perform renewal with retry logic
                Write-Warning -Message "Renewing certificate for $mainDomain..."
                Write-Log "Starting renewal for $mainDomain" -Level 'Info'

                $startTime = Get-Date

                # Use retry logic for renewal
                $newCert = Invoke-WithRetry -ScriptBlock {
                    # Clear cache to force fresh retrieval
                    Clear-CertificateCache

                    # Trigger renewal using New-PACertificate with -Force
                    $renewed = New-PACertificate -MainDomain $mainDomain -Force -Verbose

                    # Verify renewal was successful
                    if (-not $renewed -or -not $renewed.CertFile) {
                        throw "Certificate renewal did not produce a valid certificate"
                    }

                    return $renewed
                } -MaxAttempts $config.MaxRetries -InitialDelaySeconds ($config.RetryDelayMinutes * 60) `
                  -OperationName "Certificate renewal for $mainDomain" `
                  -SuccessCondition { $null -ne $_ }

                if ($newCert) {
                    $duration = (Get-Date) - $startTime
                    Write-Information -MessageData "Certificate for $mainDomain renewed in $($duration.TotalMinutes.ToString('F1')) minutes." -InformationAction Continue
                    Write-Log "Certificate for $mainDomain renewed" -Level 'Success'

                    $renewalCount++

                    # Attempt to reinstall certificate if it was previously installed
                    try {
                        # Check if certificate exists in local machine store
                        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                        $store.Open("ReadOnly")
                        $existingCert = $store.Certificates | Where-Object {
                            $_.Subject -like "*$mainDomain*" -or $_.Subject -like "*$($mainDomain.Replace('*.', ''))*"
                        }
                        $store.Close()

                        if ($existingCert) {
                            Write-Host -Object "Reinstalling renewed certificate to certificate store..." -ForegroundColor Cyan
                            Install-PACertificate -PACertificate $newCert -StoreLocation LocalMachine
                            Write-Information -MessageData "Certificate reinstalled." -InformationAction Continue
                        }
                    } catch {
                        Write-Warning -Message "Certificate renewed but reinstallation failed: $($_.Exception.Message)"
                        Write-Log "Certificate reinstallation failed for $mainDomain : $($_.Exception.Message)" -Level 'Warning'
                    }

                    $results += @{
                        Domain           = $mainDomain
                        Status           = "Renewed"
                        ExpiryDate       = $newCert.Certificate.NotAfter
                        DaysUntilExpiry  = ($newCert.Certificate.NotAfter - (Get-Date)).Days
                        RenewalDuration  = $duration
                    }
                }

            } catch {
                Write-Error -Message "Error renewing certificate for ${mainDomain}: $($_.Exception.Message)"
                Write-Log "Error renewing certificate for ${mainDomain}: $($_.Exception.Message)" -Level 'Error'
                $errorCount++

                $results += @{
                    Domain      = $mainDomain
                    Status      = "Failed"
                    Error       = $_.Exception.Message
                    ExpiryDate  = if ($cert) { $cert.Certificate.NotAfter } else { "Unknown" }
                }

                # Send notification if email is configured
                if ($config.EmailNotifications -and $config.NotificationEmail) {
                    $subject = "Certificate Renewal Failed: $mainDomain"
                    $body = "Certificate renewal failed for $mainDomain with error: $($_.Exception.Message)"
                    Send-RenewalNotification -Subject $subject -Body $body -ToEmail $config.NotificationEmail
                }
            }
        }

        # Generate renewal summary
        Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
        Write-Host -Object "AUTOMATIC RENEWAL SUMMARY" -ForegroundColor Cyan
        Write-Host -Object "="*60 -ForegroundColor Cyan
        Write-Host -Object "Certificates processed: $($orders.Count)" -ForegroundColor White
        Write-Information -MessageData "Successful renewals: $renewalCount" -InformationAction Continue
        Write-Warning -Message "Skipped (still valid): $skippedCount"
        Write-Error -Message "Failed renewals: $errorCount"
        Write-Host -Object "Completion time: $(Get-Date)" -ForegroundColor White
        Write-Host -Object "Total runtime: $((Get-Date) - $script:StartTime)" -ForegroundColor White

        # Results
        if ($results.Count -gt 0) {
            Write-Host -Object "`nResults:" -ForegroundColor Cyan
            foreach ($result in $results) {
                $color = switch ($result.Status) {
                    "Renewed" { "Green" }
                    "Skipped" { "Yellow" }
                    "Failed" { "Red" }
                    default { "White" }
                }

                $statusLine = "$($result.Domain): $($result.Status)"
                if ($result.Status -eq "Failed" -and $result.Error) {
                    $statusLine += " - $($result.Error)"
                } elseif ($result.ExpiryDate -ne "Unknown") {
                    $statusLine += " (expires: $($result.ExpiryDate), $($result.DaysUntilExpiry) days)"
                }

                Write-Host -Object "  $statusLine" -ForegroundColor $color
            }
        }

        # Send summary email if configured
        if ($config.EmailNotifications -and $config.NotificationEmail -and ($renewalCount -gt 0 -or $errorCount -gt 0)) {
            $subject = "Certificate Renewal Summary - $renewalCount renewed, $errorCount failed"

            # Generate detailed HTML results for email
            $htmlResults = ConvertTo-HtmlFragment -InputObject $results

            $body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        h2 { color: #333; }
        .summary { margin-bottom: 20px; }
        .summary-table { border-collapse: collapse; width: 400px; }
        .summary-table td { padding: 5px; border: 1px solid #ddd; }
        .summary-label { font-weight: bold; }
        .results-table { border-collapse: collapse; width: 100%; }
        .results-table th, .results-table td { padding: 8px; text-align: left; border: 1px solid #ddd; }
        .results-table th { background-color: #f2f2f2; }
        .status-renewed { color: green; }
        .status-skipped { color: orange; }
        .status-failed { color: red; }
    </style>
</head>
<body>
    <h2>Certificate Renewal Summary</h2>
    <div class="summary">
        <table class="summary-table">
            <tr><td class="summary-label">Processed</td><td>$($orders.Count) certificates</td></tr>
            <tr><td class="summary-label">Renewed</td><td>$renewalCount</td></tr>
            <tr><td class="summary-label">Skipped</td><td>$skippedCount</td></tr>
            <tr><td class="summary-label">Failed</td><td>$errorCount</td></tr>
        </table>
    </div>
    <h3>Results:</h3>
    $htmlResults
    <p>Completion Time: $(Get-Date -Format 'u')</p>
    <p>Runtime: $((Get-Date) - $script:StartTime)</p>
</body>
</html>
"@
            Send-RenewalNotification -Subject $subject -Body $body -ToEmail $config.NotificationEmail -BodyAsHtml
        }

        Write-Log "Automatic renewal completed - Renewed: $renewalCount, Failed: $errorCount, Skipped: $skippedCount" -Level 'Info'

        # Exit with appropriate code
        if ($errorCount -gt 0) {
            Exit 1  # Indicate some failures occurred
        } else {
            Exit 0  # Success
        }

    } catch {
        $msg = "Critical error during automatic renewal: $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'

        # Send critical error notification
        $config = Get-RenewalConfig
        if ($config.EmailNotifications -and $config.NotificationEmail) {
            Send-RenewalNotification -Subject "Critical Certificate Renewal Error" -Body $msg -ToEmail $config.NotificationEmail
        }

        Exit 1
    }
}

# Configuration test mode
if ($ConfigTest) {
    Write-Host -Object "AutoCert Certificate Management System - Configuration Test" -ForegroundColor Cyan
    Write-Host -Object "Version: $script:ScriptVersion" -ForegroundColor Gray

    $configValid = Test-SystemConfiguration

    if ($configValid) {
        Write-Information -MessageData "`nConfiguration test passed." -InformationAction Continue
        Exit 0
    } else {
        Write-Error -Message "`nConfiguration test failed."
        Exit 1
    }
}

# Interactive mode functions
function Show-Menu {
    Clear-Host

    # Initialize ACME server if function is available
    if (Get-Command Initialize-ACMEServer -ErrorAction SilentlyContinue) {
        Initialize-ACMEServer
    }

    # Display header with system information
    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Write-Host -Object "    AUTOCERT LET'S ENCRYPT CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host -Object "                            Version $script:ScriptVersion" -ForegroundColor Gray
    Write-Host -Object "="*70 -ForegroundColor Cyan

    # Show current ACME server
    try {
        $currentServer = (Get-PAServer).Name
        Write-Warning -Message "ACME Server: $currentServer"
    } catch {
        Write-Error -Message "ACME Server: Not configured"
    }

    # Show certificate summary with status
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config
            $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
            $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count

            Write-Information -MessageData "Certificates: $($orders.Count) total" -InformationAction Continue
            if ($needsRenewal -gt 0) {
                Write-Warning -Message "             $needsRenewal need renewal"
            }
            if ($expiringSoon -gt 0) {
                Write-Error -Message "             $expiringSoon expire within 7 days"
            }
        } else {
            Write-Host -Object "Certificates: None configured" -ForegroundColor Gray
        }
    } catch {
        Write-Host -Object "Certificates: Status unavailable" -ForegroundColor Gray
    }

    # Show system status
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            $taskStatus = switch ($task.State) {
                "Ready" { "Configured" }
                "Running" { "Running" }
                "Disabled" { "Disabled" }
                default { $task.State }
            }
            Write-Host -Object "Auto-Renewal: $taskStatus" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
        } else {
            Write-Host -Object "Auto-Renewal: Not configured" -ForegroundColor Yellow
        }
    } catch {
        Write-Host -Object "Auto-Renewal: Status unavailable" -ForegroundColor Gray
    }

    Write-Host -Object "`nAvailable Actions:" -ForegroundColor White
    Write-Information -MessageData "1. Register a new certificate" -InformationAction Continue
    Write-Host -Object "2. Install existing certificate" -ForegroundColor Cyan
    Write-Warning -Message "3. Configure automatic renewal"
    Write-Host -Object "4. View and Manage existing certificates" -ForegroundColor Magenta
    Write-Host -Object "5. Options" -ForegroundColor Blue
    Write-Host -Object "6. Manage Credentials" -ForegroundColor DarkCyan
    Write-Host -Object "7. System health check" -ForegroundColor DarkGreen
    Write-Host -Object "S. Help / About" -ForegroundColor Gray
    Write-Host -Object "0. Exit" -ForegroundColor DarkRed
    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
}

# Credential management menu

function Invoke-SingleCertificateManagement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$CertificateOrder
    )

    while ($true) {
        Clear-Host
        $mainDomain = $CertificateOrder.MainDomain
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
        Write-Host -Object "    MANAGING CERTIFICATE: $mainDomain" -ForegroundColor Cyan
        Write-Host -Object "="*70 -ForegroundColor Cyan

        try {
            $certDetails = Get-PACertificate -MainDomain $mainDomain
            $daysUntilExpiry = ($certDetails.Certificate.NotAfter - (Get-Date)).Days
            Write-Information -MessageData "Status: Valid" -InformationAction Continue
            Write-Host -Object "Expires: $($certDetails.Certificate.NotAfter) ($daysUntilExpiry days remaining)" -ForegroundColor $(if ($daysUntilExpiry -lt 30) { "Yellow" } else { "Green" })
            Write-Host -Object "Thumbprint: $($certDetails.Thumbprint)" -ForegroundColor Gray
            Write-Host -Object "SANs: $($certDetails.SANs -join ', ')" -ForegroundColor Gray
        } catch {
            Write-Error -Message "Status: Could not retrieve certificate details."
        }

        Write-Host -Object "`nAvailable Actions for ${mainDomain}:" -ForegroundColor White
        Write-Warning -Message "1. Force Renew"
        Write-Host -Object "2. Re-install Certificate" -ForegroundColor Cyan
        Write-Error -Message "3. Revoke Certificate"
        Write-Host -Object "4. View Details" -ForegroundColor Magenta
        Write-Host -Object "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice for '$mainDomain'"

        switch ($choice) {
            '1' {
                Write-Warning -Message "Forcing renewal for $mainDomain..."
                try {
                    $renewed = New-PACertificate -MainDomain $mainDomain -Force
                    if ($renewed) {
                        Write-Information -MessageData "Certificate for $mainDomain renewed." -InformationAction Continue
                    } else {
                        Write-Warning -Message "Renewal failed. Check logs for details."
                    }
                } catch {
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
                    } else {
                        Write-Warning -Message "Certificate not found for $mainDomain"
                    }
                } catch {
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

# Help function
function Show-Help {
    Clear-Host
    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Write-Host -Object "    HELP / ABOUT - CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host -Object "                            Version $script:ScriptVersion" -ForegroundColor Gray
    Write-Host -Object "="*70 -ForegroundColor Cyan

    Write-Host -Object "`nThis tool manages Let's Encrypt certificates using Posh-ACME." -ForegroundColor Gray
    Write-Host -Object "Developed for production environments with automation capabilities." -ForegroundColor Gray

    Write-Warning -Message "`nKey Features:"
    Write-Information -MessageData "• Automatic DNS provider detection with 10+ supported providers" -InformationAction Continue
    Write-Information -MessageData "• Error handling with exponential backoff retry logic" -InformationAction Continue
    Write-Information -MessageData "• Certificate caching" -InformationAction Continue
    Write-Information -MessageData "• Renewal scheduling with randomization" -InformationAction Continue
    Write-Information -MessageData "• Certificate installation targets (IIS, stores, files)" -InformationAction Continue
    Write-Information -MessageData "• Logging and monitoring" -InformationAction Continue
    Write-Information -MessageData "• Email notifications" -InformationAction Continue
    Write-Information -MessageData "• System health checks" -InformationAction Continue
    Write-Host -Object "• Certificate export (PFX, PEM, full-chain)" -ForegroundColor Green

    Write-Warning -Message "`nMenu Options:"
    Write-Host -Object " 1) Register: Obtain certificates with DNS validation"
    Write-Host -Object " 2) Install: Deploy certificates to targets"
    Write-Host -Object " 3) Renewal: Set up renewal scheduling"
    Write-Host -Object " 4) Manage: Certificate management submenu including:"
    Write-Host -Object "    • View certificates with status"
    Write-Host -Object "    • Certificate management (renew, reinstall, view details)"
    Write-Host -Object "    • Bulk renewal operations"
    Write-Host -Object "    • Certificate export"
    Write-Host -Object "    • Certificate revocation"
    Write-Host -Object "    • Certificate deletion"
    Write-Host -Object " 5) Options: ACME server settings and configurations"
    Write-Host -Object " 6) Credentials: DNS provider credential management"
    Write-Host -Object " 7) Health: System status and diagnostics"
    Write-Host -Object " S) Help: This information screen"
    Write-Host -Object " 0) Exit: Close application"

    Write-Warning -Message "`nSupported DNS Providers:"
    Write-Host -Object "• Cloudflare, AWS Route53, Azure DNS, Google Cloud DNS"
    Write-Host -Object "• DigitalOcean, DNS Made Easy, Namecheap, GoDaddy"
    Write-Host -Object "• Linode, Vultr, Hetzner, OVH, and many more"
    Write-Host -Object "• Manual DNS (compatible with any DNS provider)"

    Write-Warning -Message "`nInstallation Targets:"
    Write-Host -Object "• Windows Certificate Store (LocalMachine/CurrentUser)"
    Write-Host -Object "• IIS websites with binding configuration"
    Write-Host -Object "• PEM files for Linux/Apache/Nginx servers"
    Write-Host -Object "• PFX files with password protection"
    Write-Host -Object "• Certificate export for compatibility"

    Write-Warning -Message "`nBest Practices:"
    Write-Host -Object "• Run as Administrator for certificate store operations"
    Write-Host -Object "• Test certificates in Let's Encrypt staging before production"
    Write-Host -Object "• Set up renewal at least 30 days before expiry"
    Write-Host -Object "• Keep backups of certificates"
    Write-Host -Object "• Monitor renewal logs and configure email notifications"
    Write-Host -Object "• Use system health checks to validate configuration"
    Write-Host -Object "• Document certificate deployment procedures"

    Write-Warning -Message "`nCommand Line Usage:"
    Write-Host -Object "• .\Main.ps1                    # Interactive mode"
    Write-Host -Object "• .\Main.ps1 -RenewAll          # Manual renewal check"
    Write-Host -Object "• .\Main.ps1 -ConfigTest        # Validate configuration"
    Write-Host -Object "• .\Main.ps1 -RenewAll -NonInteractive  # Scheduled task mode"

    Write-Warning -Message "`nTroubleshooting:"
    Write-Host -Object "• Check log files in %LOCALAPPDATA%\\Posh-ACME\\"
    Write-Host -Object "• Run system health check (option 8) for diagnostics"
    Write-Host -Object "• Verify DNS provider credentials and permissions"
    Write-Host -Object "• Ensure Windows Event Log source is registered"
    Write-Host -Object "• Test internet connectivity to Let's Encrypt API"

    Write-Host -Object "`nSupport Information:" -ForegroundColor Gray
    Write-Host -Object "• Script Version: $script:ScriptVersion"
    Write-Host -Object "• PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Host -Object "• Loaded Modules: $($script:LoadedModules.Count)"
    Write-Host -Object "• Session Started: $($script:StartTime)"

    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Read-Host "Press Enter to return to the main menu"
}

# System health check
function Test-SystemHealth {
    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    SYSTEM HEALTH CHECK" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    $healthIssues = @()
    $healthWarnings = @()

    Write-Warning -Message "`nRunning system health check..."
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking components..." -PercentComplete 10

    # Check PowerShell version
    Write-Host -Object "`n1. PowerShell Environment:" -ForegroundColor Cyan
    $psVersion = $PSVersionTable.PSVersion
    Write-Information -MessageData "   Version: $psVersion" -InformationAction Continue
    Write-Information -MessageData "   Edition: $($PSVersionTable.PSEdition)" -InformationAction Continue
    Write-Information -MessageData "   Platform: $($PSVersionTable.Platform)" -InformationAction Continue

    if ($psVersion.Major -lt 5) {
        $healthIssues += "PowerShell version $psVersion is not supported. Minimum version 5.1 required."
    } elseif ($psVersion.Major -eq 5 -and $psVersion.Minor -eq 0) {
        $healthWarnings += "PowerShell 5.0 detected. Version 5.1 or later recommended for best compatibility."
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking modules..." -PercentComplete 20

    # Check Posh-ACME module
    Write-Host -Object "`n2. Posh-ACME Module:" -ForegroundColor Cyan
    try {
        $poshAcmeModule = Get-Module -Name Posh-ACME -ListAvailable | Select-Object -First 1
        if ($poshAcmeModule) {
            Write-Information -MessageData "   Installed: Version $($poshAcmeModule.Version)" -InformationAction Continue
            Write-Host -Object "   Path: $($poshAcmeModule.ModuleBase)" -ForegroundColor Gray

            # Test module import
            Import-Module Posh-ACME -Force
            Write-Information -MessageData "   Status: Loaded" -InformationAction Continue

            # Check for newer version
            try {
                $latestVersion = (Find-Module -Name Posh-ACME -ErrorAction SilentlyContinue).Version
                if ($latestVersion -and $latestVersion -gt $poshAcmeModule.Version) {
                    $healthWarnings += "Newer version of Posh-ACME available: $latestVersion (current: $($poshAcmeModule.Version))"
                }
            } catch {
                Write-Verbose "Could not check for newer Posh-ACME version"
            }
        } else {
            $healthIssues += "Posh-ACME module not found"
        }
    } catch {
        $healthIssues += "Failed to load Posh-ACME module: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking script modules..." -PercentComplete 30

    # Check script modules
    Write-Host -Object "`n3. Script Modules:" -ForegroundColor Cyan
    Write-Information -MessageData "   Loaded Modules: $($script:LoadedModules.Count)" -InformationAction Continue
    $script:LoadedModules | ForEach-Object { Write-Host -Object "   • $_" -ForegroundColor Gray }

    if ($script:InitializationErrors.Count -gt 0) {
        Write-Warning -Message "   Initialization Errors: $($script:InitializationErrors.Count)"
        $script:InitializationErrors | ForEach-Object { $healthWarnings += "Module loading: $_" }
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking ACME connectivity..." -PercentComplete 40

    # Check ACME server connectivity
    Write-Host -Object "`n4. ACME Server Connectivity:" -ForegroundColor Cyan
    try {
        $server = Get-PAServer
        if ($server) {
            Write-Information -MessageData "   Server: $($server.Name)" -InformationAction Continue
            Write-Information -MessageData "   URL: $($server.location)" -InformationAction Continue

            # Test connectivity with timeout
            $connectivityTest = Invoke-WithRetry -ScriptBlock {
                $response = Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                return $response
            } -MaxAttempts 3 -InitialDelaySeconds 2 -OperationName "ACME server connectivity test"

            Write-Information -MessageData "   Connectivity: OK (Status: $($connectivityTest.StatusCode))" -InformationAction Continue
            Write-Host -Object "   Response Time: $((Measure-Command { Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 5 }).TotalMilliseconds.ToString('F0')) ms" -ForegroundColor Gray
        } else {
            $healthWarnings += "No ACME server configured"
        }
    } catch {
        $healthIssues += "ACME server connectivity failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking certificates..." -PercentComplete 50

    # Check certificate status
    Write-Host -Object "`n5. Certificate Status:" -ForegroundColor Cyan
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config

            Write-Information -MessageData "   Total Certificates: $($orders.Count)" -InformationAction Continue

            $expiringSoon = $renewalStatus | Where-Object { $_.NeedsRenewal }
            $criticallyExpiring = $renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }

            if ($criticallyExpiring) {
                Write-Error -Message "   Critically Expiring: $($criticallyExpiring.Count)"
                foreach ($cert in $criticallyExpiring) {
                    Write-Error -Message "     • $($cert.Domain) (expires in $($cert.DaysUntilExpiry) days)"
                    $healthIssues += "Certificate $($cert.Domain) expires in $($cert.DaysUntilExpiry) days"
                }
            }

            if ($expiringSoon -and $expiringSoon.Count -gt $criticallyExpiring.Count) {
                $soonCount = $expiringSoon.Count - $criticallyExpiring.Count
                Write-Warning -Message "   Expiring Soon: $soonCount"
                foreach ($cert in ($expiringSoon | Where-Object { $_.DaysUntilExpiry -gt 7 })) {
                    Write-Warning -Message "     • $($cert.Domain) (expires in $($cert.DaysUntilExpiry) days)"
                }
                $healthWarnings += "$soonCount certificate(s) need renewal within $($config.RenewalThresholdDays) days"
            }

            if (-not $expiringSoon) {
                Write-Information -MessageData "   All certificates valid" -InformationAction Continue
            }

            # Check certificate integrity
            $integrityIssues = 0
            foreach ($order in $orders) {
                try {
                    $cert = Get-CachedPACertificate -MainDomain $order.MainDomain
                    if (-not $cert.Certificate) {
                        $integrityIssues++
                    }
                } catch {
                    $integrityIssues++
                }
            }

            if ($integrityIssues -gt 0) {
                $healthWarnings += "$integrityIssues certificate(s) have integrity issues"
            }

        } else {
            Write-Host -Object "   No certificates configured" -ForegroundColor Gray
        }
    } catch {
        $healthWarnings += "Certificate status check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking file system..." -PercentComplete 60

    # Check file system permissions and paths
    Write-Host -Object "`n6. File System:" -ForegroundColor Cyan
    try {
        $appDataPath = "$env:LOCALAPPDATA\Posh-ACME"
        if (Test-Path $appDataPath) {
            Write-Information -MessageData "   Data Directory: $appDataPath" -InformationAction Continue

            # Check directory size
            $dirSize = (Get-ChildItem $appDataPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $dirSizeMB = [math]::Round($dirSize / 1MB, 2)
            Write-Host -Object "   Directory Size: $dirSizeMB MB" -ForegroundColor Gray

            # Test write permissions
            $testFile = Join-Path $appDataPath "health_check_test.tmp"
            try {
                "health check test" | Out-File -FilePath $testFile
                Remove-Item $testFile -Force
                Write-Information -MessageData "   Write Permissions: OK" -InformationAction Continue
            } catch {
                $healthIssues += "Cannot write to Posh-ACME data directory"
            }
        } else {
            $healthWarnings += "Posh-ACME data directory does not exist"
        }

        # Check certificate stores
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
        try {
            $store.Open("ReadOnly")
            $certCount = $store.Certificates.Count
            Write-Information -MessageData "   Certificate Store: $certCount certificates in LocalMachine\\My" -InformationAction Continue

            # Test store write access
            try {
                $testStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                $testStore.Open("ReadWrite")
                $testStore.Close()
                Write-Information -MessageData "   Store Write Access: OK" -InformationAction Continue
            } catch {
                $healthWarnings += "Limited access to certificate store (may affect installation)"
            }
        } catch {
            $healthIssues += "Cannot access certificate store"
        } finally {
            $store.Close()
        }

    } catch {
        $healthWarnings += "File system check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking scheduled tasks..." -PercentComplete 70

    # Check scheduled tasks and automation
    Write-Host -Object "`n7. Automatic Renewal:" -ForegroundColor Cyan
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            Write-Information -MessageData "   Scheduled Task: Configured" -InformationAction Continue
            Write-Host -Object "   State: $($task.State)" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
            Write-Host -Object "   Last Run: $($task.LastRunTime)" -ForegroundColor Gray
            Write-Host -Object "   Next Run: $($task.NextRunTime)" -ForegroundColor Gray
            Write-Host -Object "   Last Result: $($task.LastTaskResult)" -ForegroundColor $(if ($task.LastTaskResult -eq 0) { "Green" } else { "Red" })

            if ($task.State -ne "Ready") {
                $healthWarnings += "Scheduled task is not in Ready state: $($task.State)"
            }

            if ($task.LastTaskResult -ne 0 -and $task.LastTaskResult -ne 267009) { # 267009 = never run
                $healthWarnings += "Scheduled task last execution failed (code: $($task.LastTaskResult))"
            }
        } else {
            Write-Warning -Message "   Scheduled Task: Not configured"
            $healthWarnings += "Automatic renewal not configured"
        }

        # Check task schedule validity
        if ($task) {
            $config = Get-RenewalConfig
            if ($config.UseRandomization -and $config.RandomizationWindow -gt 1440) {
                $healthWarnings += "Renewal randomization window is too large ($($config.RandomizationWindow) minutes)"
            }
        }
    } catch {
        $healthWarnings += "Scheduled task check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking network and DNS..." -PercentComplete 80

    # Check network connectivity and DNS
    Write-Host -Object "`n8. Network and DNS:" -ForegroundColor Cyan
    try {
        # Test internet connectivity
        $internetHosts = @("8.8.8.8", "1.1.1.1", "208.67.222.222")
        $connectableHosts = 0

        foreach ($testHost in $internetHosts) {
            if (Test-Connection -ComputerName $testHost -Count 1 -Quiet -TimeoutSec 3) {
                $connectableHosts++
            }
        }

        if ($connectableHosts -gt 0) {
            Write-Information -MessageData "   Internet Connectivity: OK ($connectableHosts/$($internetHosts.Count) DNS servers reachable)" -InformationAction Continue
        } else {
            $healthIssues += "No internet connectivity detected"
        }

        # Test DNS resolution
        try {
            Resolve-DnsName -Name "letsencrypt.org" -Type A -ErrorAction Stop | Out-Null
            Write-Information -MessageData "   DNS Resolution: OK" -InformationAction Continue
        } catch {
            $healthIssues += "DNS resolution failed: $($_.Exception.Message)"
        }

        # Check proxy settings
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            Write-Warning -Message "   Proxy: Enabled ($($proxySettings.ProxyServer))"
            $healthWarnings += "Proxy is enabled, may affect ACME operations"
        } else {
            Write-Information -MessageData "   Proxy: Direct connection" -InformationAction Continue
        }

    } catch {
        $healthWarnings += "Network check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking event logging..." -PercentComplete 90

    # Check event logging
    Write-Host -Object "`n9. Event Logging:" -ForegroundColor Cyan
    try {
        # Test event log source registration
        $eventSources = Get-WinEvent -ListProvider "Certificate Management" -ErrorAction SilentlyContinue
        if ($eventSources) {
            Write-Information -MessageData "   Event Source: Registered" -InformationAction Continue
        } else {
            Write-Warning -Message "   Event Source: Not registered"
            $healthWarnings += "Event log source 'Certificate Management' not registered"
        }

        # Test event log writing
        try {
            New-EventLog -LogName Application -Source "Certificate Management" -ErrorAction SilentlyContinue
            Write-EventLog -LogName Application -Source "Certificate Management" -EventId 9999 -Message "Health check test event" -ErrorAction Stop
            Write-Information -MessageData "   Event Writing: OK" -InformationAction Continue
        } catch {
            $healthWarnings += "Cannot write to event log: $($_.Exception.Message)"
        }

    } catch {
        $healthWarnings += "Event logging check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Finalizing health check..." -PercentComplete 95

    # Check system resources
    Write-Host -Object "`n10. System Resources:" -ForegroundColor Cyan
    try {
        $memory = Get-CimInstance -ClassName Win32_ComputerSystem
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        Write-Information -MessageData "   Total Memory: $totalMemoryGB GB" -InformationAction Continue

        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $memoryUsage = [math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 1)
        Write-Host -Object "   Memory Usage: $memoryUsage%" -ForegroundColor $(if ($memoryUsage -lt 80) { "Green" } else { "Yellow" })

        if ($memoryUsage -gt 90) {
            $healthWarnings += "High memory usage detected: $memoryUsage%"
        }

        # Check available disk space
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
        $diskUsage = [math]::Round((($totalSpaceGB - $freeSpaceGB) / $totalSpaceGB) * 100, 1)

        Write-Host -Object "   Disk Space: $freeSpaceGB GB free ($diskUsage% used)" -ForegroundColor $(if ($diskUsage -lt 80) { "Green" } else { "Yellow" })

        if ($freeSpaceGB -lt 1) {
            $healthIssues += "Low disk space: Only $freeSpaceGB GB free"
        } elseif ($freeSpaceGB -lt 5) {
            $healthWarnings += "Limited disk space: $freeSpaceGB GB free"
        }

    } catch {
        $healthWarnings += "System resource check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Health check complete" -PercentComplete 100
    Write-Progress -Activity "System Health Check" -Completed

    # Display comprehensive summary
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "HEALTH CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    if ($healthIssues.Count -eq 0 -and $healthWarnings.Count -eq 0) {
        Write-Information -MessageData "✓ System health: EXCELLENT" -InformationAction Continue
        Write-Information -MessageData "  All components are functioning optimally." -InformationAction Continue
        Write-Information -MessageData "  No issues or warnings detected." -InformationAction Continue
    } elseif ($healthIssues.Count -eq 0) {
        Write-Warning -Message "⚠ System health: GOOD (with warnings)"
        Write-Warning -Message "  System is functional but some optimization is recommended."
        Write-Warning -Message "`n  Warnings detected:"
        $healthWarnings | ForEach-Object { Write-Warning -Message "    • $_" }
    } else {
        Write-Error -Message "✗ System health: NEEDS ATTENTION"
        Write-Error -Message "  Critical issues require immediate attention."
        Write-Error -Message "`n  Critical issues:"
        $healthIssues | ForEach-Object { Write-Error -Message "    • $_" }

        if ($healthWarnings.Count -gt 0) {
            Write-Warning -Message "`n  Additional warnings:"
            $healthWarnings | ForEach-Object { Write-Warning -Message "    • $_" }
        }
    }

    # Health score calculation
    $issueScore = $healthIssues.Count * 3
    $warningScore = $healthWarnings.Count * 1
    $healthScore = [math]::Max(0, 100 - $issueScore - $warningScore)

    Write-Host -Object "`nHealth Score: $healthScore/100" -ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
    Write-Warning -Message "Issues: $($healthIssues.Count) critical, $($healthWarnings.Count) warnings" -ForegroundColor White
    Write-Host -Object "Check completed: $(Get-Date)" -ForegroundColor Gray
    Write-Host -Object "Check duration: $((Get-Date) - $script:StartTime)" -ForegroundColor Gray

    # Recommendations based on health status
    if ($healthIssues.Count -gt 0 -or $healthWarnings.Count -gt 0) {
        Write-Host -Object "`nRecommended Actions:" -ForegroundColor Cyan

        if ($healthIssues.Count -gt 0) {
            Write-Error -Message "• Address critical issues immediately before proceeding"
            Write-Host -Object "• Run configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor Red
        }

        if ($healthWarnings.Count -gt 0) {
            Write-Warning -Message "• Review warnings and optimize system configuration"
            Write-Warning -Message "• Consider setting up monitoring for detected issues"
        }

        Write-Host -Object "• Check log files for additional details" -ForegroundColor White
        Write-Host -Object "• Verify network connectivity and DNS resolution" -ForegroundColor White
        Write-Host -Object "• Ensure sufficient system resources are available" -ForegroundColor White
    }

    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan

    # Log health check results
    Write-Log "System health check completed - Score: $healthScore/100, Issues: $($healthIssues.Count), Warnings: $($healthWarnings.Count)" -Level 'Info'

    Read-Host "Press Enter to return to the main menu"
}

# Error handling wrapper for menu operations
function Invoke-MenuOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        [Parameter(Mandatory = $true)]
        [string]$OperationName
    )

    try {
        Write-Host -Object "`nStarting $OperationName..." -ForegroundColor Cyan
        Write-ProgressHelper -Activity "Certificate Management" -Status "Preparing $OperationName..." -PercentComplete 0

        $startTime = Get-Date
        & $Operation
        $duration = (Get-Date) - $startTime

        Write-Information -MessageData "`n$OperationName completed in $($duration.TotalSeconds.ToString('F1')) seconds." -InformationAction Continue
        Write-Log "$OperationName completed" -Level 'Success'

    } catch {
        $errorMsg = "$OperationName failed: $($_.Exception.Message)"
        Write-Error -Message $errorMsg
        Write-Log $errorMsg -Level 'Error'

        # Error reporting
        Write-Error -Message "`nError Details:"
        Write-Error -Message "  Operation: $OperationName"
        Write-Error -Message "  Error: $($_.Exception.Message)"
        Write-Error -Message "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"

        # Provide context-specific troubleshooting
        Write-Warning -Message "`nTroubleshooting suggestions:"
        switch ($OperationName) {
            "certificate registration" {
                Write-Warning -Message "• Check DNS provider credentials and permissions"
                Write-Warning -Message "• Verify domain ownership and DNS propagation"
                Write-Warning -Message "• Test internet connectivity to ACME servers"
            }
            "certificate installation" {
                Write-Warning -Message "• Ensure script is running as Administrator"
                Write-Warning -Message "• Check certificate store permissions"
                Write-Warning -Message "• Verify certificate file integrity"
            }
            default {
                Write-Warning -Message "• Check the log files for detailed error information"
                Write-Warning -Message "• Run system health check to identify configuration issues"
                Write-Warning -Message "• Verify all required modules are loaded correctly"
            }
        }

    } finally {
        Write-Progress -Activity "Certificate Management" -Completed
    }
}

# Main script execution starts here
try {
    # Initialize system
    $moduleLoadSuccess = Initialize-ScriptModules
    if (-not $moduleLoadSuccess) {
        Exit 1
    }

    # Main interactive loop
    while ($true) {
        Show-Menu
        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            '1' { Register-Certificate }
            '2' { Install-Certificate }
            '3' { Set-AutomaticRenewal }
            '4' {
                Show-CertificateManagementMenu
            }
            '5' { Show-Options }
            '6' { Show-CredentialManagementMenu }
            '7' { Test-SystemHealth }
            'S' { Show-Help }
            '0' {
                Write-Warning -Message "Exiting..."
                Exit 0
            }
            default {
                Write-Warning -Message "Invalid option. Please try again."
                Read-Host "Press Enter to continue"
            }
        }
    }

} catch {
    $criticalError = "Critical application error: $($_.Exception.Message)"
    Write-Error -Message $criticalError

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $criticalError -Level 'Error'
    }

    Write-Error -Message "`nThe application encountered a critical error and must exit."
    Write-Warning -Message "Error details have been logged for troubleshooting."

    # Error information
    Write-Error -Message "`nError Information:"
    Write-Error -Message "  Message: $($_.Exception.Message)"
    Write-Error -Message "  Type: $($_.Exception.GetType().Name)"
    Write-Error -Message "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"
    Write-Host -Object "  Time: $(Get-Date)" -ForegroundColor Red

    Write-Warning -Message "`nTroubleshooting Resources:"
    Write-Host -Object "• Log files: $env:LOCALAPPDATA\Posh-ACME\certificate_script.log" -ForegroundColor Yellow
    Write-Host -Object "• Run configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor Yellow
    Write-Warning -Message "• Check system health: .\Main.ps1 and select option 8"
    Write-Warning -Message "• Verify all script files are present and accessible"

    if (-not $NonInteractive) {
        Read-Host "Press Enter to exit"
    }
    Exit 1

} finally {
    # Cleanup and final logging
    $sessionDuration = (Get-Date) - $script:StartTime
    Write-Log "Application session ended (Duration: $sessionDuration, Version: $script:ScriptVersion)" -Level 'Info'

    # Clear any sensitive data from memory
    if (Get-Variable -Name "cert*" -ErrorAction SilentlyContinue) {
        Remove-Variable -Name "cert*" -Force -ErrorAction SilentlyContinue
    }

# Clean up progress indicators
Write-Progress -Activity "Certificate Management" -Completed -ErrorAction SilentlyContinue
}

# Certificate management menu
function Show-CertificateManagementMenu {
    while ($true) {
        Clear-Host
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
        Write-Host -Object "    CERTIFICATE MANAGEMENT" -ForegroundColor Cyan
        Write-Host -Object "="*70 -ForegroundColor Cyan

        # Show current certificate summary
        try {
            $orders = Get-PAOrder
            if ($orders) {
                $config = Get-RenewalConfig
                $renewalStatus = Get-CertificateRenewalStatus -Config $config
                $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
                $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count
                $total = $orders.Count

                Write-Information -MessageData "Certificate Summary:" -InformationAction Continue
                Write-Host -Object "  Total certificates: $total" -ForegroundColor White
                if ($needsRenewal -gt 0) {
                    Write-Warning -Message "  Certificates needing renewal: $needsRenewal"
                }
                if ($expiringSoon -gt 0) {
                    Write-Error -Message "  Expiring within 7 days: $expiringSoon"
                }
                Write-Information -MessageData "" -InformationAction Continue
            } else {
                Write-Warning -Message "No certificates found."
                Write-Information -MessageData "" -InformationAction Continue
            }
        } catch {
            Write-Error -Message "Could not retrieve certificate summary."
            Write-Information -MessageData "" -InformationAction Continue
        }

        Write-Host -Object "Available Actions:" -ForegroundColor White
        Write-Information -MessageData "1. View all certificates (detailed list)" -InformationAction Continue
        Write-Host -Object "2. Manage individual certificate" -ForegroundColor Cyan
        Write-Warning -Message "3. Bulk renewal check"
        Write-Host -Object "4. Export certificates" -ForegroundColor Blue
        Write-Error -Message "5. Revoke a certificate"
        Write-Error -Message "6. Delete a certificate"
        Write-Host -Object "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            '1' {
                # View all certificates in detailed list format
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    ALL CERTIFICATES - DETAILED VIEW" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                Get-ExistingCertificates
                Read-Host "`nPress Enter to continue"
            }
            '2' {
                # Manage individual certificate - show selection menu
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    SELECT CERTIFICATE TO MANAGE" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Invoke-SingleCertificateManagement -CertificateOrder $selectedOrder
                } else {
                    Write-Warning -Message "No certificate selected."
                    Read-Host "Press Enter to continue"
                }
            }
            '3' {
                # Bulk renewal check
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    BULK RENEWAL CHECK" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                try {
                    $orders = Get-PAOrder
                    if ($orders) {
                        $config = Get-RenewalConfig
                        $renewalStatus = Get-CertificateRenewalStatus -Config $config

                        Write-Information -MessageData "Renewal Status Summary:" -InformationAction Continue
                        foreach ($status in $renewalStatus) {
                            $color = if ($status.NeedsRenewal) {
                                if ($status.DaysUntilExpiry -le 7) { "Red" } else { "Yellow" }
                            } else { "Green" }

                            $statusText = if ($status.NeedsRenewal) { "NEEDS RENEWAL" } else { "OK" }
                            Write-Host -Object "  $($status.Domain): $statusText (expires in $($status.DaysUntilExpiry) days)" -ForegroundColor $color
                        }

                        $needsRenewal = $renewalStatus | Where-Object { $_.NeedsRenewal }
                        if ($needsRenewal) {
                            Write-Warning -Message "`nWould you like to renew all certificates that need renewal? (y/n)"
                            $renewChoice = Read-Host
                            if ($renewChoice -eq 'y' -or $renewChoice -eq 'Y') {
                                Write-Information -MessageData "Starting $(# Main.ps1
<#
    .SYNOPSIS
        Main script for certificate management capabilities.

    .DESCRIPTION
        This script provides an interface for Let's Encrypt certificate management
        using Posh-ACME with error handling, caching, DNS provider auto-detection,
        and renewal scheduling.

    .PARAMETER RenewAll
        Runs in non-interactive mode to renew all certificates that need renewal.

    .PARAMETER NonInteractive
        Runs without user interaction (for scheduled tasks).

    .PARAMETER Force
        Forces operations even if they might not be necessary.

    .PARAMETER ConfigTest
        Runs configuration validation and exits.

    .PARAMETER LogLevel
        Sets the logging level (Debug, Info, Warning, Error).

    .NOTES
        Must be run as Administrator for certificate store operations.
        Compatible with PowerShell 5.1 and PowerShell 7+.

    .EXAMPLE
        .\Main.ps1
        Run in interactive mode

    .EXAMPLE
        .\Main.ps1 -RenewAll -NonInteractive
        Run automatic renewal (for scheduled tasks)

    .EXAMPLE
        .\Main.ps1 -ConfigTest
        Validate configuration and exit
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
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning -Message "Administrator privileges required for certificate operations."
    Write-Warning -Message "Please run this script as an administrator."

    if (-not $NonInteractive) {
        Read-Host "Press Enter to exit"
    }
    Exit 1
}

# Set error handling and preferences
$ErrorActionPreference = 'Stop'
$ProgressPreference = if ($NonInteractive) { 'SilentlyContinue' } else { 'Continue' }
$VerbosePreference = if ($LogLevel -eq 'Debug') { 'Continue' } else { 'SilentlyContinue' }

# Initialize script-wide variables
$script:LoadedModules = @()
$script:InitializationErrors = @()

# Module loading with dependency tracking
function Initialize-ScriptModules {
    [CmdletBinding()]
    param()

    try {
        if (-not $NonInteractive) {
            Write-Information -MessageData "Loading certificate management system..." -InformationAction Continue
            Write-ProgressHelper -Activity "System Initialization" -Status "Loading core modules..." -PercentComplete 10
        }

        # Define module loading order with dependencies
        $moduleLoadOrder = @(
            @{ Path = "$PSScriptRoot\Core\Logging.ps1"; Name = "Logging"; Critical = $true },
            @{ Path = "$PSScriptRoot\Core\Helpers.ps1"; Name = "Helpers"; Critical = $true },
            @{ Path = "$PSScriptRoot\Core\Initialize-PoshAcme.ps1"; Name = "PoshACME Initialization"; Critical = $true },
            @{ Path = "$PSScriptRoot\Core\ConfigurationManager.ps1"; Name = "Configuration Manager"; Critical = $true },
            @{ Path = "$PSScriptRoot\Core\CircuitBreaker.ps1"; Name = "Circuit Breaker"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\HealthMonitor.ps1"; Name = "Health Monitor"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\BackupManager.ps1"; Name = "Backup Manager"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\NotificationManager.ps1"; Name = "Notification Manager"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\CertificateCache.ps1"; Name = "Certificate Cache"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\DNSProviderDetection.ps1"; Name = "DNS Provider Detection"; Critical = $false },
            @{ Path = "$PSScriptRoot\Core\RenewalConfig.ps1"; Name = "Renewal Configuration"; Critical = $false },
            # UI modules
            @{ Path = "$PSScriptRoot\UI\MainMenu.ps1"; Name = "Main Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\UI\CertificateMenu.ps1"; Name = "Certificate Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\UI\CredentialMenu.ps1"; Name = "Credential Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\UI\HelpSystem.ps1"; Name = "Help System"; Critical = $false },
            # Utilities modules
            @{ Path = "$PSScriptRoot\Utilities\ErrorHandling.ps1"; Name = "Error Handling"; Critical = $true },
            @{ Path = "$PSScriptRoot\Utilities\HealthCheck.ps1"; Name = "Health Check"; Critical = $false },
            @{ Path = "$PSScriptRoot\Utilities\Configuration.ps1"; Name = "Configuration Validation"; Critical = $true },
            @{ Path = "$PSScriptRoot\Utilities\RenewalManager.ps1"; Name = "Renewal Manager"; Critical = $false },
            @{ Path = "$PSScriptRoot\Utilities\ModuleManager.ps1"; Name = "Module Manager"; Critical = $false },
            # Function modules
            @{ Path = "$PSScriptRoot\Functions\Register-Certificate.ps1"; Name = "Certificate Registration"; Critical = $true },
            @{ Path = "$PSScriptRoot\Functions\Install-Certificate.ps1"; Name = "Certificate Installation"; Critical = $true },
            @{ Path = "$PSScriptRoot\Functions\Revoke-Certificate.ps1"; Name = "Certificate Revocation"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Remove-Certificate.ps1"; Name = "Certificate Removal"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Get-ExistingCertificates.ps1"; Name = "Certificate Listing"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Set-AutomaticRenewal.ps1"; Name = "Automatic Renewal"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Show-Options.ps1"; Name = "Options"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Update-AllCertificates.ps1"; Name = "Certificate Updates"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Manage-Credentials.ps1"; Name = "Credential Management"; Critical = $false }
        )

        $totalModules = $moduleLoadOrder.Count
        $loadedCount = 0

        foreach ($module in $moduleLoadOrder) {
            try {
                if (Test-Path $module.Path) {
                    . $module.Path
                    $script:LoadedModules += $module.Name
                    $loadedCount++

                    if (-not $NonInteractive) {
                        $percentComplete = [math]::Round(($loadedCount / $totalModules) * 80) + 10
                        Write-ProgressHelper -Activity "System Initialization" -Status "Loaded: $($module.Name)" -PercentComplete $percentComplete
                    }

                    Write-Verbose "Loaded module: $($module.Name)"
                } else {
                    $errorMsg = "Module file not found: $($module.Path)"
                    $script:InitializationErrors += $errorMsg

                    if ($module.Critical) {
                        throw $errorMsg
                    } else {
                        Write-Warning -Message $errorMsg
                    }
                }
            } catch {
                $errorMsg = "Failed to load module '$($module.Name)': $($_.Exception.Message)"
                $script:InitializationErrors += $errorMsg

                if ($module.Critical) {
                    throw $errorMsg
                } else {
                    Write-Warning -Message $errorMsg
                }
            }
        }

        if (-not $NonInteractive) {
            Write-ProgressHelper -Activity "System Initialization" -Status "Finalizing..." -PercentComplete 95
        }

        # Verify critical functions are available
        $criticalFunctions = @('Register-Certificate', 'Install-Certificate', 'Write-Log', 'Show-Menu', 'Show-CertificateManagementMenu', 'Show-CredentialManagementMenu', 'Show-Help', 'Test-SystemHealth')
        foreach ($func in $criticalFunctions) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                throw "Critical function '$func' is not available"
            }
        }

        if (-not $NonInteractive) {
            Write-ProgressHelper -Activity "System Initialization" -Status "Complete" -PercentComplete 100
            Write-Progress -Activity "System Initialization" -Completed
        }

        Write-Log "Certificate management system loaded (Version: $script:ScriptVersion)" -Level 'Info'
        Write-Log "Loaded modules: $($script:LoadedModules -join ', ')" -Level 'Debug'

        if ($script:InitializationErrors.Count -gt 0) {
            Write-Log "Initialization warnings: $($script:InitializationErrors.Count)" -Level 'Warning'
        }

        return $true

    } catch {
        $criticalError = "Failed to load required modules: $($_.Exception.Message)"
        Write-Error -Message $criticalError

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $criticalError -Level 'Error'
        }

        Write-Error -Message "Please ensure all script files are present and accessible."
        Write-Error -Message "Missing modules will prevent the system from functioning correctly."

        if (-not $NonInteractive) {
            Read-Host "Press Enter to exit"
        }

        return $false
    }
}

# Configuration validation function
function Test-SystemConfiguration {
    [CmdletBinding()]
    param()

    Write-Host -Object "Running configuration validation..." -ForegroundColor Cyan

    $configIssues = @()
    $configWarnings = @()

    try {
        # Test PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 5) {
            $configIssues += "PowerShell version $($PSVersionTable.PSVersion) is not supported. Minimum version 5.1 required."
        }

        # Test Posh-ACME module
        if (-not (Get-Module -Name Posh-ACME -ListAvailable)) {
            $configIssues += "Posh-ACME module not found. Run 'Install-Module Posh-ACME' to install."
        }

        # Test script files
        $requiredFiles = @(
            "$PSScriptRoot\Core\Logging.ps1",
            "$PSScriptRoot\Core\Helpers.ps1",
            "$PSScriptRoot\Functions\Register-Certificate.ps1",
            "$PSScriptRoot\Functions\Install-Certificate.ps1"
        )

        foreach ($file in $requiredFiles) {
            if (-not (Test-Path $file)) {
                $configIssues += "Required file missing: $file"
            }
        }

        # Test write permissions
        try {
            $testPath = "$env:LOCALAPPDATA\Posh-ACME\config_test.tmp"
            New-Item -Path (Split-Path $testPath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            "test" | Out-File -FilePath $testPath -ErrorAction Stop
            Remove-Item $testPath -Force -ErrorAction SilentlyContinue
        } catch {
            $configIssues += "Insufficient write permissions to %LOCALAPPDATA%\Posh-ACME\"
        }

        # Test internet connectivity
        try {
            $response = Invoke-WebRequest -Uri "https://acme-v02.api.letsencrypt.org/directory" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            if ($response.StatusCode -ne 200) {
                $configWarnings += "Let's Encrypt API accessibility issue (Status: $($response.StatusCode))"
            }
        } catch {
            $configWarnings += "Cannot reach Let's Encrypt API: $($_.Exception.Message)"
        }

        # Display results
        Write-Host -Object "`nConfiguration Validation Results:" -ForegroundColor Cyan

        if ($configIssues.Count -eq 0) {
            Write-Information -MessageData "✓ Configuration validation passed" -InformationAction Continue
        } else {
            Write-Error -Message "✗ Configuration issues found:"
            $configIssues | ForEach-Object { Write-Error -Message "  • $_" }
        }

        if ($configWarnings.Count -gt 0) {
            Write-Warning -Message "⚠ Configuration warnings:"
            $configWarnings | ForEach-Object { Write-Warning -Message "  • $_" }
        }

        return ($configIssues.Count -eq 0)

    } catch {
        Write-Error -Message "Configuration validation failed: $($_.Exception.Message)"
        return $false
    }
}

# Renewal mode for scheduled tasks
if ($RenewAll) {
    # Initialize modules for renewal mode
    $moduleLoadSuccess = Initialize-ScriptModules
    if (-not $moduleLoadSuccess) {
        Exit 1
    }

    Write-Host -Object "Running in automatic renewal mode..." -ForegroundColor Cyan
    Write-Log "Starting automatic renewal process (Version: $script:ScriptVersion)" -Level 'Info'

    try {
        # Load renewal configuration
        $config = Get-RenewalConfig

        # Get all certificates and check renewal status
        $orders = Get-PAOrder
        if (-not $orders) {
            Write-Warning -Message "No certificates found to renew."
            Write-Log "No certificates found for renewal" -Level 'Warning'
            Exit 0
        }

        Write-Information -MessageData "Found $($orders.Count) certificate(s) to check for renewal." -InformationAction Continue

        $renewalCount = 0
        $errorCount = 0
        $skippedCount = 0
        $results = @()

        foreach ($order in $orders) {
            $mainDomain = $order.MainDomain
            Write-Host -Object "`nProcessing certificate for $mainDomain..." -ForegroundColor Cyan

            try {
                # Get certificate details with caching
                $cert = Get-CachedPACertificate -MainDomain $mainDomain -Force:$Force

                # Check if renewal is needed
                $renewalThreshold = (Get-Date).AddDays($config.RenewalThresholdDays)
                $needsRenewal = $cert.Certificate.NotAfter -le $renewalThreshold

                if (-not $needsRenewal -and -not $Force) {
                    Write-Information -MessageData "Certificate for $mainDomain is still valid until $($cert.Certificate.NotAfter). Skipping renewal." -InformationAction Continue
                    $skippedCount++

                    $results += @{
                        Domain          = $mainDomain
                        Status          = "Skipped"
                        ExpiryDate      = $cert.Certificate.NotAfter
                        DaysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                    }
                    continue
                }

                # Perform renewal with retry logic
                Write-Warning -Message "Renewing certificate for $mainDomain..."
                Write-Log "Starting renewal for $mainDomain" -Level 'Info'

                $startTime = Get-Date

                # Use retry logic for renewal
                $newCert = Invoke-WithRetry -ScriptBlock {
                    # Clear cache to force fresh retrieval
                    Clear-CertificateCache

                    # Trigger renewal using New-PACertificate with -Force
                    $renewed = New-PACertificate -MainDomain $mainDomain -Force -Verbose

                    # Verify renewal was successful
                    if (-not $renewed -or -not $renewed.CertFile) {
                        throw "Certificate renewal did not produce a valid certificate"
                    }

                    return $renewed
                } -MaxAttempts $config.MaxRetries -InitialDelaySeconds ($config.RetryDelayMinutes * 60) `
                  -OperationName "Certificate renewal for $mainDomain" `
                  -SuccessCondition { $null -ne $_ }

                if ($newCert) {
                    $duration = (Get-Date) - $startTime
                    Write-Information -MessageData "Certificate for $mainDomain renewed in $($duration.TotalMinutes.ToString('F1')) minutes." -InformationAction Continue
                    Write-Log "Certificate for $mainDomain renewed" -Level 'Success'

                    $renewalCount++

                    # Attempt to reinstall certificate if it was previously installed
                    try {
                        # Check if certificate exists in local machine store
                        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                        $store.Open("ReadOnly")
                        $existingCert = $store.Certificates | Where-Object {
                            $_.Subject -like "*$mainDomain*" -or $_.Subject -like "*$($mainDomain.Replace('*.', ''))*"
                        }
                        $store.Close()

                        if ($existingCert) {
                            Write-Host -Object "Reinstalling renewed certificate to certificate store..." -ForegroundColor Cyan
                            Install-PACertificate -PACertificate $newCert -StoreLocation LocalMachine
                            Write-Information -MessageData "Certificate reinstalled." -InformationAction Continue
                        }
                    } catch {
                        Write-Warning -Message "Certificate renewed but reinstallation failed: $($_.Exception.Message)"
                        Write-Log "Certificate reinstallation failed for $mainDomain : $($_.Exception.Message)" -Level 'Warning'
                    }

                    $results += @{
                        Domain           = $mainDomain
                        Status           = "Renewed"
                        ExpiryDate       = $newCert.Certificate.NotAfter
                        DaysUntilExpiry  = ($newCert.Certificate.NotAfter - (Get-Date)).Days
                        RenewalDuration  = $duration
                    }
                }

            } catch {
                Write-Error -Message "Error renewing certificate for ${mainDomain}: $($_.Exception.Message)"
                Write-Log "Error renewing certificate for ${mainDomain}: $($_.Exception.Message)" -Level 'Error'
                $errorCount++

                $results += @{
                    Domain      = $mainDomain
                    Status      = "Failed"
                    Error       = $_.Exception.Message
                    ExpiryDate  = if ($cert) { $cert.Certificate.NotAfter } else { "Unknown" }
                }

                # Send notification if email is configured
                if ($config.EmailNotifications -and $config.NotificationEmail) {
                    $subject = "Certificate Renewal Failed: $mainDomain"
                    $body = "Certificate renewal failed for $mainDomain with error: $($_.Exception.Message)"
                    Send-RenewalNotification -Subject $subject -Body $body -ToEmail $config.NotificationEmail
                }
            }
        }

        # Generate renewal summary
        Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
        Write-Host -Object "AUTOMATIC RENEWAL SUMMARY" -ForegroundColor Cyan
        Write-Host -Object "="*60 -ForegroundColor Cyan
        Write-Host -Object "Certificates processed: $($orders.Count)" -ForegroundColor White
        Write-Information -MessageData "Successful renewals: $renewalCount" -InformationAction Continue
        Write-Warning -Message "Skipped (still valid): $skippedCount"
        Write-Error -Message "Failed renewals: $errorCount"
        Write-Host -Object "Completion time: $(Get-Date)" -ForegroundColor White
        Write-Host -Object "Total runtime: $((Get-Date) - $script:StartTime)" -ForegroundColor White

        # Results
        if ($results.Count -gt 0) {
            Write-Host -Object "`nResults:" -ForegroundColor Cyan
            foreach ($result in $results) {
                $color = switch ($result.Status) {
                    "Renewed" { "Green" }
                    "Skipped" { "Yellow" }
                    "Failed" { "Red" }
                    default { "White" }
                }

                $statusLine = "$($result.Domain): $($result.Status)"
                if ($result.Status -eq "Failed" -and $result.Error) {
                    $statusLine += " - $($result.Error)"
                } elseif ($result.ExpiryDate -ne "Unknown") {
                    $statusLine += " (expires: $($result.ExpiryDate), $($result.DaysUntilExpiry) days)"
                }

                Write-Host -Object "  $statusLine" -ForegroundColor $color
            }
        }

        # Send summary email if configured
        if ($config.EmailNotifications -and $config.NotificationEmail -and ($renewalCount -gt 0 -or $errorCount -gt 0)) {
            $subject = "Certificate Renewal Summary - $renewalCount renewed, $errorCount failed"

            # Generate detailed HTML results for email
            $htmlResults = ConvertTo-HtmlFragment -InputObject $results

            $body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        h2 { color: #333; }
        .summary { margin-bottom: 20px; }
        .summary-table { border-collapse: collapse; width: 400px; }
        .summary-table td { padding: 5px; border: 1px solid #ddd; }
        .summary-label { font-weight: bold; }
        .results-table { border-collapse: collapse; width: 100%; }
        .results-table th, .results-table td { padding: 8px; text-align: left; border: 1px solid #ddd; }
        .results-table th { background-color: #f2f2f2; }
        .status-renewed { color: green; }
        .status-skipped { color: orange; }
        .status-failed { color: red; }
    </style>
</head>
<body>
    <h2>Certificate Renewal Summary</h2>
    <div class="summary">
        <table class="summary-table">
            <tr><td class="summary-label">Processed</td><td>$($orders.Count) certificates</td></tr>
            <tr><td class="summary-label">Renewed</td><td>$renewalCount</td></tr>
            <tr><td class="summary-label">Skipped</td><td>$skippedCount</td></tr>
            <tr><td class="summary-label">Failed</td><td>$errorCount</td></tr>
        </table>
    </div>
    <h3>Results:</h3>
    $htmlResults
    <p>Completion Time: $(Get-Date -Format 'u')</p>
    <p>Runtime: $((Get-Date) - $script:StartTime)</p>
</body>
</html>
"@
            Send-RenewalNotification -Subject $subject -Body $body -ToEmail $config.NotificationEmail -BodyAsHtml
        }

        Write-Log "Automatic renewal completed - Renewed: $renewalCount, Failed: $errorCount, Skipped: $skippedCount" -Level 'Info'

        # Exit with appropriate code
        if ($errorCount -gt 0) {
            Exit 1  # Indicate some failures occurred
        } else {
            Exit 0  # Success
        }

    } catch {
        $msg = "Critical error during automatic renewal: $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'

        # Send critical error notification
        $config = Get-RenewalConfig
        if ($config.EmailNotifications -and $config.NotificationEmail) {
            Send-RenewalNotification -Subject "Critical Certificate Renewal Error" -Body $msg -ToEmail $config.NotificationEmail
        }

        Exit 1
    }
}

# Configuration test mode
if ($ConfigTest) {
    Write-Host -Object "AutoCert Certificate Management System - Configuration Test" -ForegroundColor Cyan
    Write-Host -Object "Version: $script:ScriptVersion" -ForegroundColor Gray

    $configValid = Test-SystemConfiguration

    if ($configValid) {
        Write-Information -MessageData "`nConfiguration test passed." -InformationAction Continue
        Exit 0
    } else {
        Write-Error -Message "`nConfiguration test failed."
        Exit 1
    }
}

# Interactive mode functions
function Show-Menu {
    Clear-Host

    # Initialize ACME server if function is available
    if (Get-Command Initialize-ACMEServer -ErrorAction SilentlyContinue) {
        Initialize-ACMEServer
    }

    # Display header with system information
    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Write-Host -Object "    AUTOCERT LET'S ENCRYPT CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host -Object "                            Version $script:ScriptVersion" -ForegroundColor Gray
    Write-Host -Object "="*70 -ForegroundColor Cyan

    # Show current ACME server
    try {
        $currentServer = (Get-PAServer).Name
        Write-Warning -Message "ACME Server: $currentServer"
    } catch {
        Write-Error -Message "ACME Server: Not configured"
    }

    # Show certificate summary with status
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config
            $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
            $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count

            Write-Information -MessageData "Certificates: $($orders.Count) total" -InformationAction Continue
            if ($needsRenewal -gt 0) {
                Write-Warning -Message "             $needsRenewal need renewal"
            }
            if ($expiringSoon -gt 0) {
                Write-Error -Message "             $expiringSoon expire within 7 days"
            }
        } else {
            Write-Host -Object "Certificates: None configured" -ForegroundColor Gray
        }
    } catch {
        Write-Host -Object "Certificates: Status unavailable" -ForegroundColor Gray
    }

    # Show system status
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            $taskStatus = switch ($task.State) {
                "Ready" { "Configured" }
                "Running" { "Running" }
                "Disabled" { "Disabled" }
                default { $task.State }
            }
            Write-Host -Object "Auto-Renewal: $taskStatus" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
        } else {
            Write-Host -Object "Auto-Renewal: Not configured" -ForegroundColor Yellow
        }
    } catch {
        Write-Host -Object "Auto-Renewal: Status unavailable" -ForegroundColor Gray
    }

    Write-Host -Object "`nAvailable Actions:" -ForegroundColor White
    Write-Information -MessageData "1. Register a new certificate" -InformationAction Continue
    Write-Host -Object "2. Install existing certificate" -ForegroundColor Cyan
    Write-Warning -Message "3. Configure automatic renewal"
    Write-Host -Object "4. View and Manage existing certificates" -ForegroundColor Magenta
    Write-Host -Object "5. Options" -ForegroundColor Blue
    Write-Host -Object "6. Manage Credentials" -ForegroundColor DarkCyan
    Write-Host -Object "7. System health check" -ForegroundColor DarkGreen
    Write-Host -Object "S. Help / About" -ForegroundColor Gray
    Write-Host -Object "0. Exit" -ForegroundColor DarkRed
    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
}

# Credential management menu
function Show-CredentialManagementMenu {
    while ($true) {
        Clear-Host
        Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    CREDENTIAL MANAGEMENT" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    # List stored credentials
    $credentials = Get-StoredCredential
    if ($credentials.Count -eq 0) {
        Write-Warning -Message "No credentials found. You can add new ones."
    } else {
        Write-Information -MessageData "Stored Credentials:" -InformationAction Continue
        foreach ($cred in $credentials) {
            Write-Host -Object "  • $($cred.Target)" -ForegroundColor White
        }
    }

    Write-Host -Object "`nAvailable Actions:" -ForegroundColor White
    Write-Information -MessageData "1. Add new credential" -InformationAction Continue
    Write-Error -Message "2. Remove credential"
    Write-Host -Object "3. Test credential" -ForegroundColor Cyan
    Write-Host -Object "0. Return to Main Menu" -ForegroundColor DarkRed
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan

    $choice = Read-Host "Enter your choice"

    switch ($choice) {
        '1' {
            # Add new credential
            $target = Read-Host "Enter credential target (e.g., DNS provider name)"
            $username = Read-Host "Enter username" -AsSecureString
            $password = Read-Host "Enter password" -AsSecureString

            try {
                $cred = New-Object System.Management.Automation.PSCredential ($username, $password)
                $null = $cred | Export-Clixml -Path "$env:LOCALAPPDATA\Posh-ACME\credentials.xml" -Force
                Write-Information -MessageData "Credential added." -InformationAction Continue
            } catch {
                Write-Error -Message "Failed to add credential: $($_.Exception.Message)"
            }

            Read-Host "Press Enter to continue"
        }
        '2' {
            # Remove credential
            $target = Read-Host "Enter credential target to remove"

            try {
                $cred = Get-StoredCredential -Target $target
                if ($cred) {
                    Remove-StoredCredential -Target $target
                    Write-Information -MessageData "Credential removed." -InformationAction Continue
                } else {
                    Write-Warning -Message "Credential not found."
                }
            } catch {
                Write-Error -Message "Failed to remove credential: $($_.Exception.Message)"
            }

            Read-Host "Press Enter to continue"
        }
        '3' {
            # Test credential
            $target = Read-Host "Enter credential target to test"

            try {
                $cred = Get-StoredCredential -Target $target
                if ($cred) {
                    # Attempt to use credential (e.g., test DNS resolution)
                    $username = $cred.UserName
                    $password = $cred.GetNetworkCredential().Password

                    # Display credential information (password masked for security)
                    Write-Information -MessageData "Credential for ${target}:" -InformationAction Continue
                    Write-Host -Object "  Username: $username" -ForegroundColor White
                    Write-Warning -Message "  Password: ******* (hidden for security)"
                } else {
                    Write-Warning -Message "Credential not found."
                }
            } catch {
                Write-Error -Message "Failed to test credential: $($_.Exception.Message)"
            }

            Read-Host "Press Enter to continue"
        }
        '0' { return }
        default {
            Write-Warning -Message "Invalid option. Please try again."
            Read-Host "Press Enter to continue"
        }
    }
    }
}

function Invoke-SingleCertificateManagement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$CertificateOrder
    )

    while ($true) {
        Clear-Host
        $mainDomain = $CertificateOrder.MainDomain
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
        Write-Host -Object "    MANAGING CERTIFICATE: $mainDomain" -ForegroundColor Cyan
        Write-Host -Object "="*70 -ForegroundColor Cyan

        try {
            $certDetails = Get-PACertificate -MainDomain $mainDomain
            $daysUntilExpiry = ($certDetails.Certificate.NotAfter - (Get-Date)).Days
            Write-Information -MessageData "Status: Valid" -InformationAction Continue
            Write-Host -Object "Expires: $($certDetails.Certificate.NotAfter) ($daysUntilExpiry days remaining)" -ForegroundColor $(if ($daysUntilExpiry -lt 30) { "Yellow" } else { "Green" })
            Write-Host -Object "Thumbprint: $($certDetails.Thumbprint)" -ForegroundColor Gray
            Write-Host -Object "SANs: $($certDetails.SANs -join ', ')" -ForegroundColor Gray
        } catch {
            Write-Error -Message "Status: Could not retrieve certificate details."
        }

        Write-Host -Object "`nAvailable Actions for ${mainDomain}:" -ForegroundColor White
        Write-Warning -Message "1. Force Renew"
        Write-Host -Object "2. Re-install Certificate" -ForegroundColor Cyan
        Write-Error -Message "3. Revoke Certificate"
        Write-Host -Object "4. View Details" -ForegroundColor Magenta
        Write-Host -Object "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice for '$mainDomain'"

        switch ($choice) {
            '1' {
                Write-Warning -Message "Forcing renewal for $mainDomain..."
                try {
                    $renewed = New-PACertificate -MainDomain $mainDomain -Force
                    if ($renewed) {
                        Write-Information -MessageData "Certificate for $mainDomain renewed." -InformationAction Continue
                    } else {
                        Write-Warning -Message "Renewal failed. Check logs for details."
                    }
                } catch {
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
                    } else {
                        Write-Warning -Message "Certificate not found for $mainDomain"
                    }
                } catch {
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

# Help function
function Show-Help {
    Clear-Host
    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Write-Host -Object "    HELP / ABOUT - CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host -Object "                            Version $script:ScriptVersion" -ForegroundColor Gray
    Write-Host -Object "="*70 -ForegroundColor Cyan

    Write-Host -Object "`nThis tool manages Let's Encrypt certificates using Posh-ACME." -ForegroundColor Gray
    Write-Host -Object "Developed for production environments with automation capabilities." -ForegroundColor Gray

    Write-Warning -Message "`nKey Features:"
    Write-Information -MessageData "• Automatic DNS provider detection with 10+ supported providers" -InformationAction Continue
    Write-Information -MessageData "• Error handling with exponential backoff retry logic" -InformationAction Continue
    Write-Information -MessageData "• Certificate caching" -InformationAction Continue
    Write-Information -MessageData "• Renewal scheduling with randomization" -InformationAction Continue
    Write-Information -MessageData "• Certificate installation targets (IIS, stores, files)" -InformationAction Continue
    Write-Information -MessageData "• Logging and monitoring" -InformationAction Continue
    Write-Information -MessageData "• Email notifications" -InformationAction Continue
    Write-Information -MessageData "• System health checks" -InformationAction Continue
    Write-Host -Object "• Certificate export (PFX, PEM, full-chain)" -ForegroundColor Green

    Write-Warning -Message "`nMenu Options:"
    Write-Host -Object " 1) Register: Obtain certificates with DNS validation"
    Write-Host -Object " 2) Install: Deploy certificates to targets"
    Write-Host -Object " 3) Renewal: Set up renewal scheduling"
    Write-Host -Object " 4) Manage: Certificate management submenu including:"
    Write-Host -Object "    • View certificates with status"
    Write-Host -Object "    • Certificate management (renew, reinstall, view details)"
    Write-Host -Object "    • Bulk renewal operations"
    Write-Host -Object "    • Certificate export"
    Write-Host -Object "    • Certificate revocation"
    Write-Host -Object "    • Certificate deletion"
    Write-Host -Object " 5) Options: ACME server settings and configurations"
    Write-Host -Object " 6) Credentials: DNS provider credential management"
    Write-Host -Object " 7) Health: System status and diagnostics"
    Write-Host -Object " S) Help: This information screen"
    Write-Host -Object " 0) Exit: Close application"

    Write-Warning -Message "`nSupported DNS Providers:"
    Write-Host -Object "• Cloudflare, AWS Route53, Azure DNS, Google Cloud DNS"
    Write-Host -Object "• DigitalOcean, DNS Made Easy, Namecheap, GoDaddy"
    Write-Host -Object "• Linode, Vultr, Hetzner, OVH, and many more"
    Write-Host -Object "• Manual DNS (compatible with any DNS provider)"

    Write-Warning -Message "`nInstallation Targets:"
    Write-Host -Object "• Windows Certificate Store (LocalMachine/CurrentUser)"
    Write-Host -Object "• IIS websites with binding configuration"
    Write-Host -Object "• PEM files for Linux/Apache/Nginx servers"
    Write-Host -Object "• PFX files with password protection"
    Write-Host -Object "• Certificate export for compatibility"

    Write-Warning -Message "`nBest Practices:"
    Write-Host -Object "• Run as Administrator for certificate store operations"
    Write-Host -Object "• Test certificates in Let's Encrypt staging before production"
    Write-Host -Object "• Set up renewal at least 30 days before expiry"
    Write-Host -Object "• Keep backups of certificates"
    Write-Host -Object "• Monitor renewal logs and configure email notifications"
    Write-Host -Object "• Use system health checks to validate configuration"
    Write-Host -Object "• Document certificate deployment procedures"

    Write-Warning -Message "`nCommand Line Usage:"
    Write-Host -Object "• .\Main.ps1                    # Interactive mode"
    Write-Host -Object "• .\Main.ps1 -RenewAll          # Manual renewal check"
    Write-Host -Object "• .\Main.ps1 -ConfigTest        # Validate configuration"
    Write-Host -Object "• .\Main.ps1 -RenewAll -NonInteractive  # Scheduled task mode"

    Write-Warning -Message "`nTroubleshooting:"
    Write-Host -Object "• Check log files in %LOCALAPPDATA%\\Posh-ACME\\"
    Write-Host -Object "• Run system health check (option 8) for diagnostics"
    Write-Host -Object "• Verify DNS provider credentials and permissions"
    Write-Host -Object "• Ensure Windows Event Log source is registered"
    Write-Host -Object "• Test internet connectivity to Let's Encrypt API"

    Write-Host -Object "`nSupport Information:" -ForegroundColor Gray
    Write-Host -Object "• Script Version: $script:ScriptVersion"
    Write-Host -Object "• PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Host -Object "• Loaded Modules: $($script:LoadedModules.Count)"
    Write-Host -Object "• Session Started: $($script:StartTime)"

    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Read-Host "Press Enter to return to the main menu"
}

# System health check
function Test-SystemHealth {
    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    SYSTEM HEALTH CHECK" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    $healthIssues = @()
    $healthWarnings = @()

    Write-Warning -Message "`nRunning system health check..."
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking components..." -PercentComplete 10

    # Check PowerShell version
    Write-Host -Object "`n1. PowerShell Environment:" -ForegroundColor Cyan
    $psVersion = $PSVersionTable.PSVersion
    Write-Information -MessageData "   Version: $psVersion" -InformationAction Continue
    Write-Information -MessageData "   Edition: $($PSVersionTable.PSEdition)" -InformationAction Continue
    Write-Information -MessageData "   Platform: $($PSVersionTable.Platform)" -InformationAction Continue

    if ($psVersion.Major -lt 5) {
        $healthIssues += "PowerShell version $psVersion is not supported. Minimum version 5.1 required."
    } elseif ($psVersion.Major -eq 5 -and $psVersion.Minor -eq 0) {
        $healthWarnings += "PowerShell 5.0 detected. Version 5.1 or later recommended for best compatibility."
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking modules..." -PercentComplete 20

    # Check Posh-ACME module
    Write-Host -Object "`n2. Posh-ACME Module:" -ForegroundColor Cyan
    try {
        $poshAcmeModule = Get-Module -Name Posh-ACME -ListAvailable | Select-Object -First 1
        if ($poshAcmeModule) {
            Write-Information -MessageData "   Installed: Version $($poshAcmeModule.Version)" -InformationAction Continue
            Write-Host -Object "   Path: $($poshAcmeModule.ModuleBase)" -ForegroundColor Gray

            # Test module import
            Import-Module Posh-ACME -Force
            Write-Information -MessageData "   Status: Loaded" -InformationAction Continue

            # Check for newer version
            try {
                $latestVersion = (Find-Module -Name Posh-ACME -ErrorAction SilentlyContinue).Version
                if ($latestVersion -and $latestVersion -gt $poshAcmeModule.Version) {
                    $healthWarnings += "Newer version of Posh-ACME available: $latestVersion (current: $($poshAcmeModule.Version))"
                }
            } catch {
                Write-Verbose "Could not check for newer Posh-ACME version"
            }
        } else {
            $healthIssues += "Posh-ACME module not found"
        }
    } catch {
        $healthIssues += "Failed to load Posh-ACME module: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking script modules..." -PercentComplete 30

    # Check script modules
    Write-Host -Object "`n3. Script Modules:" -ForegroundColor Cyan
    Write-Information -MessageData "   Loaded Modules: $($script:LoadedModules.Count)" -InformationAction Continue
    $script:LoadedModules | ForEach-Object { Write-Host -Object "   • $_" -ForegroundColor Gray }

    if ($script:InitializationErrors.Count -gt 0) {
        Write-Warning -Message "   Initialization Errors: $($script:InitializationErrors.Count)"
        $script:InitializationErrors | ForEach-Object { $healthWarnings += "Module loading: $_" }
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking ACME connectivity..." -PercentComplete 40

    # Check ACME server connectivity
    Write-Host -Object "`n4. ACME Server Connectivity:" -ForegroundColor Cyan
    try {
        $server = Get-PAServer
        if ($server) {
            Write-Information -MessageData "   Server: $($server.Name)" -InformationAction Continue
            Write-Information -MessageData "   URL: $($server.location)" -InformationAction Continue

            # Test connectivity with timeout
            $connectivityTest = Invoke-WithRetry -ScriptBlock {
                $response = Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                return $response
            } -MaxAttempts 3 -InitialDelaySeconds 2 -OperationName "ACME server connectivity test"

            Write-Information -MessageData "   Connectivity: OK (Status: $($connectivityTest.StatusCode))" -InformationAction Continue
            Write-Host -Object "   Response Time: $((Measure-Command { Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 5 }).TotalMilliseconds.ToString('F0')) ms" -ForegroundColor Gray
        } else {
            $healthWarnings += "No ACME server configured"
        }
    } catch {
        $healthIssues += "ACME server connectivity failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking certificates..." -PercentComplete 50

    # Check certificate status
    Write-Host -Object "`n5. Certificate Status:" -ForegroundColor Cyan
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config

            Write-Information -MessageData "   Total Certificates: $($orders.Count)" -InformationAction Continue

            $expiringSoon = $renewalStatus | Where-Object { $_.NeedsRenewal }
            $criticallyExpiring = $renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }

            if ($criticallyExpiring) {
                Write-Error -Message "   Critically Expiring: $($criticallyExpiring.Count)"
                foreach ($cert in $criticallyExpiring) {
                    Write-Error -Message "     • $($cert.Domain) (expires in $($cert.DaysUntilExpiry) days)"
                    $healthIssues += "Certificate $($cert.Domain) expires in $($cert.DaysUntilExpiry) days"
                }
            }

            if ($expiringSoon -and $expiringSoon.Count -gt $criticallyExpiring.Count) {
                $soonCount = $expiringSoon.Count - $criticallyExpiring.Count
                Write-Warning -Message "   Expiring Soon: $soonCount"
                foreach ($cert in ($expiringSoon | Where-Object { $_.DaysUntilExpiry -gt 7 })) {
                    Write-Warning -Message "     • $($cert.Domain) (expires in $($cert.DaysUntilExpiry) days)"
                }
                $healthWarnings += "$soonCount certificate(s) need renewal within $($config.RenewalThresholdDays) days"
            }

            if (-not $expiringSoon) {
                Write-Information -MessageData "   All certificates valid" -InformationAction Continue
            }

            # Check certificate integrity
            $integrityIssues = 0
            foreach ($order in $orders) {
                try {
                    $cert = Get-CachedPACertificate -MainDomain $order.MainDomain
                    if (-not $cert.Certificate) {
                        $integrityIssues++
                    }
                } catch {
                    $integrityIssues++
                }
            }

            if ($integrityIssues -gt 0) {
                $healthWarnings += "$integrityIssues certificate(s) have integrity issues"
            }

        } else {
            Write-Host -Object "   No certificates configured" -ForegroundColor Gray
        }
    } catch {
        $healthWarnings += "Certificate status check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking file system..." -PercentComplete 60

    # Check file system permissions and paths
    Write-Host -Object "`n6. File System:" -ForegroundColor Cyan
    try {
        $appDataPath = "$env:LOCALAPPDATA\Posh-ACME"
        if (Test-Path $appDataPath) {
            Write-Information -MessageData "   Data Directory: $appDataPath" -InformationAction Continue

            # Check directory size
            $dirSize = (Get-ChildItem $appDataPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $dirSizeMB = [math]::Round($dirSize / 1MB, 2)
            Write-Host -Object "   Directory Size: $dirSizeMB MB" -ForegroundColor Gray

            # Test write permissions
            $testFile = Join-Path $appDataPath "health_check_test.tmp"
            try {
                "health check test" | Out-File -FilePath $testFile
                Remove-Item $testFile -Force
                Write-Information -MessageData "   Write Permissions: OK" -InformationAction Continue
            } catch {
                $healthIssues += "Cannot write to Posh-ACME data directory"
            }
        } else {
            $healthWarnings += "Posh-ACME data directory does not exist"
        }

        # Check certificate stores
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
        try {
            $store.Open("ReadOnly")
            $certCount = $store.Certificates.Count
            Write-Information -MessageData "   Certificate Store: $certCount certificates in LocalMachine\\My" -InformationAction Continue

            # Test store write access
            try {
                $testStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                $testStore.Open("ReadWrite")
                $testStore.Close()
                Write-Information -MessageData "   Store Write Access: OK" -InformationAction Continue
            } catch {
                $healthWarnings += "Limited access to certificate store (may affect installation)"
            }
        } catch {
            $healthIssues += "Cannot access certificate store"
        } finally {
            $store.Close()
        }

    } catch {
        $healthWarnings += "File system check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking scheduled tasks..." -PercentComplete 70

    # Check scheduled tasks and automation
    Write-Host -Object "`n7. Automatic Renewal:" -ForegroundColor Cyan
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            Write-Information -MessageData "   Scheduled Task: Configured" -InformationAction Continue
            Write-Host -Object "   State: $($task.State)" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
            Write-Host -Object "   Last Run: $($task.LastRunTime)" -ForegroundColor Gray
            Write-Host -Object "   Next Run: $($task.NextRunTime)" -ForegroundColor Gray
            Write-Host -Object "   Last Result: $($task.LastTaskResult)" -ForegroundColor $(if ($task.LastTaskResult -eq 0) { "Green" } else { "Red" })

            if ($task.State -ne "Ready") {
                $healthWarnings += "Scheduled task is not in Ready state: $($task.State)"
            }

            if ($task.LastTaskResult -ne 0 -and $task.LastTaskResult -ne 267009) { # 267009 = never run
                $healthWarnings += "Scheduled task last execution failed (code: $($task.LastTaskResult))"
            }
        } else {
            Write-Warning -Message "   Scheduled Task: Not configured"
            $healthWarnings += "Automatic renewal not configured"
        }

        # Check task schedule validity
        if ($task) {
            $config = Get-RenewalConfig
            if ($config.UseRandomization -and $config.RandomizationWindow -gt 1440) {
                $healthWarnings += "Renewal randomization window is too large ($($config.RandomizationWindow) minutes)"
            }
        }
    } catch {
        $healthWarnings += "Scheduled task check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking network and DNS..." -PercentComplete 80

    # Check network connectivity and DNS
    Write-Host -Object "`n8. Network and DNS:" -ForegroundColor Cyan
    try {
        # Test internet connectivity
        $internetHosts = @("8.8.8.8", "1.1.1.1", "208.67.222.222")
        $connectableHosts = 0

        foreach ($testHost in $internetHosts) {
            if (Test-Connection -ComputerName $testHost -Count 1 -Quiet -TimeoutSec 3) {
                $connectableHosts++
            }
        }

        if ($connectableHosts -gt 0) {
            Write-Information -MessageData "   Internet Connectivity: OK ($connectableHosts/$($internetHosts.Count) DNS servers reachable)" -InformationAction Continue
        } else {
            $healthIssues += "No internet connectivity detected"
        }

        # Test DNS resolution
        try {
            Resolve-DnsName -Name "letsencrypt.org" -Type A -ErrorAction Stop | Out-Null
            Write-Information -MessageData "   DNS Resolution: OK" -InformationAction Continue
        } catch {
            $healthIssues += "DNS resolution failed: $($_.Exception.Message)"
        }

        # Check proxy settings
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            Write-Warning -Message "   Proxy: Enabled ($($proxySettings.ProxyServer))"
            $healthWarnings += "Proxy is enabled, may affect ACME operations"
        } else {
            Write-Information -MessageData "   Proxy: Direct connection" -InformationAction Continue
        }

    } catch {
        $healthWarnings += "Network check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking event logging..." -PercentComplete 90

    # Check event logging
    Write-Host -Object "`n9. Event Logging:" -ForegroundColor Cyan
    try {
        # Test event log source registration
        $eventSources = Get-WinEvent -ListProvider "Certificate Management" -ErrorAction SilentlyContinue
        if ($eventSources) {
            Write-Information -MessageData "   Event Source: Registered" -InformationAction Continue
        } else {
            Write-Warning -Message "   Event Source: Not registered"
            $healthWarnings += "Event log source 'Certificate Management' not registered"
        }

        # Test event log writing
        try {
            New-EventLog -LogName Application -Source "Certificate Management" -ErrorAction SilentlyContinue
            Write-EventLog -LogName Application -Source "Certificate Management" -EventId 9999 -Message "Health check test event" -ErrorAction Stop
            Write-Information -MessageData "   Event Writing: OK" -InformationAction Continue
        } catch {
            $healthWarnings += "Cannot write to event log: $($_.Exception.Message)"
        }

    } catch {
        $healthWarnings += "Event logging check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Finalizing health check..." -PercentComplete 95

    # Check system resources
    Write-Host -Object "`n10. System Resources:" -ForegroundColor Cyan
    try {
        $memory = Get-CimInstance -ClassName Win32_ComputerSystem
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        Write-Information -MessageData "   Total Memory: $totalMemoryGB GB" -InformationAction Continue

        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $memoryUsage = [math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 1)
        Write-Host -Object "   Memory Usage: $memoryUsage%" -ForegroundColor $(if ($memoryUsage -lt 80) { "Green" } else { "Yellow" })

        if ($memoryUsage -gt 90) {
            $healthWarnings += "High memory usage detected: $memoryUsage%"
        }

        # Check available disk space
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
        $diskUsage = [math]::Round((($totalSpaceGB - $freeSpaceGB) / $totalSpaceGB) * 100, 1)

        Write-Host -Object "   Disk Space: $freeSpaceGB GB free ($diskUsage% used)" -ForegroundColor $(if ($diskUsage -lt 80) { "Green" } else { "Yellow" })

        if ($freeSpaceGB -lt 1) {
            $healthIssues += "Low disk space: Only $freeSpaceGB GB free"
        } elseif ($freeSpaceGB -lt 5) {
            $healthWarnings += "Limited disk space: $freeSpaceGB GB free"
        }

    } catch {
        $healthWarnings += "System resource check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Health check complete" -PercentComplete 100
    Write-Progress -Activity "System Health Check" -Completed

    # Display comprehensive summary
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "HEALTH CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    if ($healthIssues.Count -eq 0 -and $healthWarnings.Count -eq 0) {
        Write-Information -MessageData "✓ System health: EXCELLENT" -InformationAction Continue
        Write-Information -MessageData "  All components are functioning optimally." -InformationAction Continue
        Write-Information -MessageData "  No issues or warnings detected." -InformationAction Continue
    } elseif ($healthIssues.Count -eq 0) {
        Write-Warning -Message "⚠ System health: GOOD (with warnings)"
        Write-Warning -Message "  System is functional but some optimization is recommended."
        Write-Warning -Message "`n  Warnings detected:"
        $healthWarnings | ForEach-Object { Write-Warning -Message "    • $_" }
    } else {
        Write-Error -Message "✗ System health: NEEDS ATTENTION"
        Write-Error -Message "  Critical issues require immediate attention."
        Write-Error -Message "`n  Critical issues:"
        $healthIssues | ForEach-Object { Write-Error -Message "    • $_" }

        if ($healthWarnings.Count -gt 0) {
            Write-Warning -Message "`n  Additional warnings:"
            $healthWarnings | ForEach-Object { Write-Warning -Message "    • $_" }
        }
    }

    # Health score calculation
    $issueScore = $healthIssues.Count * 3
    $warningScore = $healthWarnings.Count * 1
    $healthScore = [math]::Max(0, 100 - $issueScore - $warningScore)

    Write-Host -Object "`nHealth Score: $healthScore/100" -ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
    Write-Warning -Message "Issues: $($healthIssues.Count) critical, $($healthWarnings.Count) warnings" -ForegroundColor White
    Write-Host -Object "Check completed: $(Get-Date)" -ForegroundColor Gray
    Write-Host -Object "Check duration: $((Get-Date) - $script:StartTime)" -ForegroundColor Gray

    # Recommendations based on health status
    if ($healthIssues.Count -gt 0 -or $healthWarnings.Count -gt 0) {
        Write-Host -Object "`nRecommended Actions:" -ForegroundColor Cyan

        if ($healthIssues.Count -gt 0) {
            Write-Error -Message "• Address critical issues immediately before proceeding"
            Write-Host -Object "• Run configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor Red
        }

        if ($healthWarnings.Count -gt 0) {
            Write-Warning -Message "• Review warnings and optimize system configuration"
            Write-Warning -Message "• Consider setting up monitoring for detected issues"
        }

        Write-Host -Object "• Check log files for additional details" -ForegroundColor White
        Write-Host -Object "• Verify network connectivity and DNS resolution" -ForegroundColor White
        Write-Host -Object "• Ensure sufficient system resources are available" -ForegroundColor White
    }

    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan

    # Log health check results
    Write-Log "System health check completed - Score: $healthScore/100, Issues: $($healthIssues.Count), Warnings: $($healthWarnings.Count)" -Level 'Info'

    Read-Host "Press Enter to return to the main menu"
}

# Error handling wrapper for menu operations
function Invoke-MenuOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        [Parameter(Mandatory = $true)]
        [string]$OperationName
    )

    try {
        Write-Host -Object "`nStarting $OperationName..." -ForegroundColor Cyan
        Write-ProgressHelper -Activity "Certificate Management" -Status "Preparing $OperationName..." -PercentComplete 0

        $startTime = Get-Date
        & $Operation
        $duration = (Get-Date) - $startTime

        Write-Information -MessageData "`n$OperationName completed in $($duration.TotalSeconds.ToString('F1')) seconds." -InformationAction Continue
        Write-Log "$OperationName completed" -Level 'Success'

    } catch {
        $errorMsg = "$OperationName failed: $($_.Exception.Message)"
        Write-Error -Message $errorMsg
        Write-Log $errorMsg -Level 'Error'

        # Error reporting
        Write-Error -Message "`nError Details:"
        Write-Error -Message "  Operation: $OperationName"
        Write-Error -Message "  Error: $($_.Exception.Message)"
        Write-Error -Message "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"

        # Provide context-specific troubleshooting
        Write-Warning -Message "`nTroubleshooting suggestions:"
        switch ($OperationName) {
            "certificate registration" {
                Write-Warning -Message "• Check DNS provider credentials and permissions"
                Write-Warning -Message "• Verify domain ownership and DNS propagation"
                Write-Warning -Message "• Test internet connectivity to ACME servers"
            }
            "certificate installation" {
                Write-Warning -Message "• Ensure script is running as Administrator"
                Write-Warning -Message "• Check certificate store permissions"
                Write-Warning -Message "• Verify certificate file integrity"
            }
            default {
                Write-Warning -Message "• Check the log files for detailed error information"
                Write-Warning -Message "• Run system health check to identify configuration issues"
                Write-Warning -Message "• Verify all required modules are loaded correctly"
            }
        }

    } finally {
        Write-Progress -Activity "Certificate Management" -Completed
    }
}

# Main script execution starts here
try {
    # Initialize system
    $moduleLoadSuccess = Initialize-ScriptModules
    if (-not $moduleLoadSuccess) {
        Exit 1
    }

    # Main interactive loop
    while ($true) {
        Show-Menu
        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            '1' { Register-Certificate }
            '2' { Install-Certificate }
            '3' { Set-AutomaticRenewal }
            '4' {
                Show-CertificateManagementMenu
            }
            '5' { Show-Options }
            '6' { Show-CredentialManagementMenu }
            '7' { Test-SystemHealth }
            'S' { Show-Help }
            '0' {
                Write-Warning -Message "Exiting..."
                Exit 0
            }
            default {
                Write-Warning -Message "Invalid option. Please try again."
                Read-Host "Press Enter to continue"
            }
        }
    }

} catch {
    $criticalError = "Critical application error: $($_.Exception.Message)"
    Write-Error -Message $criticalError

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $criticalError -Level 'Error'
    }

    Write-Error -Message "`nThe application encountered a critical error and must exit."
    Write-Warning -Message "Error details have been logged for troubleshooting."

    # Error information
    Write-Error -Message "`nError Information:"
    Write-Error -Message "  Message: $($_.Exception.Message)"
    Write-Error -Message "  Type: $($_.Exception.GetType().Name)"
    Write-Error -Message "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"
    Write-Host -Object "  Time: $(Get-Date)" -ForegroundColor Red

    Write-Warning -Message "`nTroubleshooting Resources:"
    Write-Host -Object "• Log files: $env:LOCALAPPDATA\Posh-ACME\certificate_script.log" -ForegroundColor Yellow
    Write-Host -Object "• Run configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor Yellow
    Write-Warning -Message "• Check system health: .\Main.ps1 and select option 8"
    Write-Warning -Message "• Verify all script files are present and accessible"

    if (-not $NonInteractive) {
        Read-Host "Press Enter to exit"
    }
    Exit 1

} finally {
    # Cleanup and final logging
    $sessionDuration = (Get-Date) - $script:StartTime
    Write-Log "Application session ended (Duration: $sessionDuration, Version: $script:ScriptVersion)" -Level 'Info'

    # Clear any sensitive data from memory
    if (Get-Variable -Name "cert*" -ErrorAction SilentlyContinue) {
        Remove-Variable -Name "cert*" -Force -ErrorAction SilentlyContinue
    }

# Clean up progress indicators
Write-Progress -Activity "Certificate Management" -Completed -ErrorAction SilentlyContinue
}

# Certificate management menu
function Show-CertificateManagementMenu {
    while ($true) {
        Clear-Host
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
        Write-Host -Object "    CERTIFICATE MANAGEMENT" -ForegroundColor Cyan
        Write-Host -Object "="*70 -ForegroundColor Cyan

        # Show current certificate summary
        try {
            $orders = Get-PAOrder
            if ($orders) {
                $config = Get-RenewalConfig
                $renewalStatus = Get-CertificateRenewalStatus -Config $config
                $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
                $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count
                $total = $orders.Count

                Write-Information -MessageData "Certificate Summary:" -InformationAction Continue
                Write-Host -Object "  Total certificates: $total" -ForegroundColor White
                if ($needsRenewal -gt 0) {
                    Write-Warning -Message "  Certificates needing renewal: $needsRenewal"
                }
                if ($expiringSoon -gt 0) {
                    Write-Error -Message "  Expiring within 7 days: $expiringSoon"
                }
                Write-Information -MessageData "" -InformationAction Continue
            } else {
                Write-Warning -Message "No certificates found."
                Write-Information -MessageData "" -InformationAction Continue
            }
        } catch {
            Write-Error -Message "Could not retrieve certificate summary."
            Write-Information -MessageData "" -InformationAction Continue
        }

        Write-Host -Object "Available Actions:" -ForegroundColor White
        Write-Information -MessageData "1. View all certificates (detailed list)" -InformationAction Continue
        Write-Host -Object "2. Manage individual certificate" -ForegroundColor Cyan
        Write-Warning -Message "3. Bulk renewal check"
        Write-Host -Object "4. Export certificates" -ForegroundColor Blue
        Write-Error -Message "5. Revoke a certificate"
        Write-Error -Message "6. Delete a certificate"
        Write-Host -Object "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            '1' {
                # View all certificates in detailed list format
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    ALL CERTIFICATES - DETAILED VIEW" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                Get-ExistingCertificates
                Read-Host "`nPress Enter to continue"
            }
            '2' {
                # Manage individual certificate - show selection menu
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    SELECT CERTIFICATE TO MANAGE" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Invoke-SingleCertificateManagement -CertificateOrder $selectedOrder
                } else {
                    Write-Warning -Message "No certificate selected."
                    Read-Host "Press Enter to continue"
                }
            }
            '3' {
                # Bulk renewal check
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    BULK RENEWAL CHECK" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                try {
                    $orders = Get-PAOrder
                    if ($orders) {
                        $config = Get-RenewalConfig
                        $renewalStatus = Get-CertificateRenewalStatus -Config $config

                        Write-Information -MessageData "Renewal Status Summary:" -InformationAction Continue
                        foreach ($status in $renewalStatus) {
                            $color = if ($status.NeedsRenewal) {
                                if ($status.DaysUntilExpiry -le 7) { "Red" } else { "Yellow" }
                            } else { "Green" }

                            $statusText = if ($status.NeedsRenewal) { "NEEDS RENEWAL" } else { "OK" }
                            Write-Host -Object "  $($status.Domain): $statusText (expires in $($status.DaysUntilExpiry) days)" -ForegroundColor $color
                        }

                        $needsRenewal = $renewalStatus | Where-Object { $_.NeedsRenewal }
                        if ($needsRenewal) {
                            Write-Warning -Message "`nWould you like to renew all certificates that need renewal? (y/n)"
                            $renewChoice = Read-Host
                            if ($renewChoice -eq 'y' -or $renewChoice -eq 'Y') {
                                Write-Host -Object "Starting bulk renewal process..." -ForegroundColor Cyan
                                Update-AllCertificates -Force
                            }
                        }
                    } else {
                        Write-Warning -Message "No certificates found."
                    }
                } catch {
                    Write-Error -Message "Bulk renewal check failed: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '4' {
                # Export certificates
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    EXPORT CERTIFICATES" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                try {
                    $orders = Get-PAOrder
                    if ($orders) {
                        Write-Information -MessageData "Available certificates:" -InformationAction Continue
                        for ($i = 0; $i -lt $orders.Count; $i++) {
                            Write-Host -Object "  $($i + 1). $($orders[$i].MainDomain)" -ForegroundColor White
                        }
                        Write-Warning -Message "  A. All certificates"
                        Write-Error -Message "  0. Cancel"

                        $exportChoice = Read-Host "`nEnter your choice"

                        if ($exportChoice -eq 'A' -or $exportChoice -eq 'a') {
                            # Export all certificates
                            $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                            if ([string]::IsNullOrWhiteSpace($exportPath)) {
                                $exportPath = $PWD.Path
                            }

                            Write-Host -Object "Exporting all certificates to: $exportPath" -ForegroundColor Cyan
                            foreach ($order in $orders) {
                                try {
                                    $cert = Get-PACertificate -MainDomain $order.MainDomain
                                    $domainPath = Join-Path $exportPath $order.MainDomain
                                    New-Item -ItemType Directory -Path $domainPath -Force | Out-Null

                                    # Export certificate files if they exist
                                    if ($cert.CertFile -and (Test-Path $cert.CertFile)) {
                                        Copy-Item -Path $cert.CertFile -Destination (Join-Path $domainPath "cert.pem")
                                    }
                                    if ($cert.KeyFile -and (Test-Path $cert.KeyFile)) {
                                        Copy-Item -Path $cert.KeyFile -Destination (Join-Path $domainPath "key.pem")
                                    }
                                    if ($cert.ChainFile -and (Test-Path $cert.ChainFile)) {
                                        Copy-Item -Path $cert.ChainFile -Destination (Join-Path $domainPath "chain.pem")
                                    }
                                    if ($cert.FullChainFile -and (Test-Path $cert.FullChainFile)) {
                                        Copy-Item -Path $cert.FullChainFile -Destination (Join-Path $domainPath "fullchain.pem")
                                    }
                                    if ($cert.PfxFile -and (Test-Path $cert.PfxFile)) {
                                        Copy-Item -Path $cert.PfxFile -Destination (Join-Path $domainPath "cert.pfx")
                                    }

                                    Write-Information -MessageData "  Exported: $($order.MainDomain)" -InformationAction Continue
                                } catch {
                                    Write-Host -Object "  Failed to export: $($order.MainDomain) - $($_.Exception.Message)" -ForegroundColor Red
                                }
                            }
                            Write-Information -MessageData "Export completed." -InformationAction Continue
                        } elseif ($exportChoice -ge 1 -and $exportChoice -le $orders.Count) {
                            # Export specific certificate
                            $selectedOrder = $orders[$exportChoice - 1]
                            $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                            if ([string]::IsNullOrWhiteSpace($exportPath)) {
                                $exportPath = $PWD.Path
                            }

                            try {
                                $cert = Get-PACertificate -MainDomain $selectedOrder.MainDomain
                                $domainPath = Join-Path $exportPath $selectedOrder.MainDomain
                                New-Item -ItemType Directory -Path $domainPath -Force | Out-Null

                                # Export certificate files if they exist
                                if ($cert.CertFile -and (Test-Path $cert.CertFile)) {
                                    Copy-Item -Path $cert.CertFile -Destination (Join-Path $domainPath "cert.pem")
                                }
                                if ($cert.KeyFile -and (Test-Path $cert.KeyFile)) {
                                    Copy-Item -Path $cert.KeyFile -Destination (Join-Path $domainPath "key.pem")
                                }
                                if ($cert.ChainFile -and (Test-Path $cert.ChainFile)) {
                                    Copy-Item -Path $cert.ChainFile -Destination (Join-Path $domainPath "chain.pem")
                                }
                                if ($cert.FullChainFile -and (Test-Path $cert.FullChainFile)) {
                                    Copy-Item -Path $cert.FullChainFile -Destination (Join-Path $domainPath "fullchain.pem")
                                }
                                if ($cert.PfxFile -and (Test-Path $cert.PfxFile)) {
                                    Copy-Item -Path $cert.PfxFile -Destination (Join-Path $domainPath "cert.pfx")
                                }

                                Write-Information -MessageData "Certificate exported to: $domainPath" -InformationAction Continue
                            } catch {
                                Write-Error -Message "Failed to export certificate: $($_.Exception.Message)"
                            }
                        } elseif ($exportChoice -ne '0') {
                            Write-Error -Message "Invalid choice."
                        }
                    } else {
                        Write-Warning -Message "No certificates found to export."
                    }
                } catch {
                    Write-Error -Message "Export operation failed: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '5' {
                # Revoke a certificate
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    REVOKE CERTIFICATE" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                Write-Error -Message "Warning: Certificate revocation is permanent and cannot be undone!"
                Write-Warning -Message "Revoked certificates will be immediately invalid for all uses."
                Write-Information -MessageData "" -InformationAction Continue

                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Write-Warning -Message "`nYou have selected: $($selectedOrder.MainDomain)"
                    Write-Error -Message "Are you sure you want to revoke this certificate? (yes/no)"
                    $confirmation = Read-Host

                    if ($confirmation -eq 'yes') {
                        try {
                            # Note: Revoke-Certificate doesn't accept MainDomain parameter
                            # It will show a selection menu for the user
                            Write-Host -Object "Launching certificate revocation process..." -ForegroundColor Cyan
                            Revoke-Certificate
                            Write-Information -MessageData "Certificate revocation process completed." -InformationAction Continue
                        } catch {
                            Write-Error -Message "Failed to revoke certificate: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Warning -Message "Revocation cancelled."
                    }
                } else {
                    Write-Warning -Message "No certificate selected."
                }

                Read-Host "`nPress Enter to continue"
            }
            '6' {
                # Delete a certificate
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    DELETE CERTIFICATE" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                Write-Error -Message "Warning: This will permanently delete the certificate and all associated data!"
                Write-Warning -Message "The certificate will be removed from local storage and cannot be recovered."
                Write-Warning -Message "Consider revoking the certificate first if it's still valid."
                Write-Information -MessageData "" -InformationAction Continue

                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Write-Warning -Message "`nYou have selected: $($selectedOrder.MainDomain)"
                    Write-Error -Message "Are you sure you want to delete this certificate? (yes/no)"
                    $confirmation = Read-Host
                      if ($confirmation -eq 'yes') {
                        try {
                            # Note: Remove-Certificate doesn't accept MainDomain parameter
                            # It will show a selection menu for the user
                            Write-Host -Object "Launching certificate deletion process..." -ForegroundColor Cyan
                            Remove-Certificate
                            Write-Information -MessageData "Certificate deletion process completed." -InformationAction Continue
                        } catch {
                            Write-Error -Message "Failed to delete certificate: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Warning -Message "Deletion cancelled."
                    }
                } else {
                    Write-Warning -Message "No certificate selected."
                }

                Read-Host "`nPress Enter to continue"
            }
            '0' {
                return
            }
            default {
                Write-Warning -Message "Invalid option. Please try again."
                Read-Host "Press Enter to continue"
            }
        }
    }
}

.Name)" -InformationAction Continue -ForegroundColor Cyan
                                Update-AllCertificates -Force
                            }
                        }
                    } else {
                        Write-Warning -Message "No certificates found."
                    }
                } catch {
                    Write-Error -Message "Bulk renewal check failed: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '4' {
                # Export certificates
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    EXPORT CERTIFICATES" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                try {
                    $orders = Get-PAOrder
                    if ($orders) {
                        Write-Information -MessageData "Available certificates:" -InformationAction Continue
                        for ($i = 0; $i -lt $orders.Count; $i++) {
                            Write-Host -Object "  $($i + 1). $($orders[$i].MainDomain)" -ForegroundColor White
                        }
                        Write-Warning -Message "  A. All certificates"
                        Write-Error -Message "  0. Cancel"

                        $exportChoice = Read-Host "`nEnter your choice"

                        if ($exportChoice -eq 'A' -or $exportChoice -eq 'a') {
                            # Export all certificates
                            $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                            if ([string]::IsNullOrWhiteSpace($exportPath)) {
                                $exportPath = $PWD.Path
                            }

                            Write-Host -Object "Exporting all certificates to: $exportPath" -ForegroundColor Cyan
                            foreach ($order in $orders) {
                                try {
                                    $cert = Get-PACertificate -MainDomain $order.MainDomain
                                    $domainPath = Join-Path $exportPath $order.MainDomain
                                    New-Item -ItemType Directory -Path $domainPath -Force | Out-Null

                                    # Export certificate files if they exist
                                    if ($cert.CertFile -and (Test-Path $cert.CertFile)) {
                                        Copy-Item -Path $cert.CertFile -Destination (Join-Path $domainPath "cert.pem")
                                    }
                                    if ($cert.KeyFile -and (Test-Path $cert.KeyFile)) {
                                        Copy-Item -Path $cert.KeyFile -Destination (Join-Path $domainPath "key.pem")
                                    }
                                    if ($cert.ChainFile -and (Test-Path $cert.ChainFile)) {
                                        Copy-Item -Path $cert.ChainFile -Destination (Join-Path $domainPath "chain.pem")
                                    }
                                    if ($cert.FullChainFile -and (Test-Path $cert.FullChainFile)) {
                                        Copy-Item -Path $cert.FullChainFile -Destination (Join-Path $domainPath "fullchain.pem")
                                    }
                                    if ($cert.PfxFile -and (Test-Path $cert.PfxFile)) {
                                        Copy-Item -Path $cert.PfxFile -Destination (Join-Path $domainPath "cert.pfx")
                                    }

                                    Write-Information -MessageData "  Exported: $($order.MainDomain)" -InformationAction Continue
                                } catch {
                                    Write-Host -Object "  Failed to export: $($order.MainDomain) - $($_.Exception.Message)" -ForegroundColor Red
                                }
                            }
                            Write-Information -MessageData "Export completed." -InformationAction Continue
                        } elseif ($exportChoice -ge 1 -and $exportChoice -le $orders.Count) {
                            # Export specific certificate
                            $selectedOrder = $orders[$exportChoice - 1]
                            $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                            if ([string]::IsNullOrWhiteSpace($exportPath)) {
                                $exportPath = $PWD.Path
                            }

                            try {
                                $cert = Get-PACertificate -MainDomain $selectedOrder.MainDomain
                                $domainPath = Join-Path $exportPath $selectedOrder.MainDomain
                                New-Item -ItemType Directory -Path $domainPath -Force | Out-Null

                                # Export certificate files if they exist
                                if ($cert.CertFile -and (Test-Path $cert.CertFile)) {
                                    Copy-Item -Path $cert.CertFile -Destination (Join-Path $domainPath "cert.pem")
                                }
                                if ($cert.KeyFile -and (Test-Path $cert.KeyFile)) {
                                    Copy-Item -Path $cert.KeyFile -Destination (Join-Path $domainPath "key.pem")
                                }
                                if ($cert.ChainFile -and (Test-Path $cert.ChainFile)) {
                                    Copy-Item -Path $cert.ChainFile -Destination (Join-Path $domainPath "chain.pem")
                                }
                                if ($cert.FullChainFile -and (Test-Path $cert.FullChainFile)) {
                                    Copy-Item -Path $cert.FullChainFile -Destination (Join-Path $domainPath "fullchain.pem")
                                }
                                if ($cert.PfxFile -and (Test-Path $cert.PfxFile)) {
                                    Copy-Item -Path $cert.PfxFile -Destination (Join-Path $domainPath "cert.pfx")
                                }

                                Write-Information -MessageData "Certificate exported to: $domainPath" -InformationAction Continue
                            } catch {
                                Write-Error -Message "Failed to export certificate: $($_.Exception.Message)"
                            }
                        } elseif ($exportChoice -ne '0') {
                            Write-Error -Message "Invalid choice."
                        }
                    } else {
                        Write-Warning -Message "No certificates found to export."
                    }
                } catch {
                    Write-Error -Message "Export operation failed: $($_.Exception.Message)"
                }

                Read-Host "`nPress Enter to continue"
            }
            '5' {
                # Revoke a certificate
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    REVOKE CERTIFICATE" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                Write-Error -Message "Warning: Certificate revocation is permanent and cannot be undone!"
                Write-Warning -Message "Revoked certificates will be immediately invalid for all uses."
                Write-Information -MessageData "" -InformationAction Continue

                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Write-Warning -Message "`nYou have selected: $($selectedOrder.MainDomain)"
                    Write-Error -Message "Are you sure you want to revoke this certificate? (yes/no)"
                    $confirmation = Read-Host

                    if ($confirmation -eq 'yes') {
                        try {
                            # Note: Revoke-Certificate doesn't accept MainDomain parameter
                            # It will show a selection menu for the user
                            Write-Host -Object "Launching certificate revocation process..." -ForegroundColor Cyan
                            Revoke-Certificate
                            Write-Information -MessageData "Certificate revocation process completed." -InformationAction Continue
                        } catch {
                            Write-Error -Message "Failed to revoke certificate: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Warning -Message "Revocation cancelled."
                    }
                } else {
                    Write-Warning -Message "No certificate selected."
                }

                Read-Host "`nPress Enter to continue"
            }
            '6' {
                # Delete a certificate
                Clear-Host
                Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
                Write-Host -Object "    DELETE CERTIFICATE" -ForegroundColor Cyan
                Write-Host -Object "="*60 -ForegroundColor Cyan

                Write-Error -Message "Warning: This will permanently delete the certificate and all associated data!"
                Write-Warning -Message "The certificate will be removed from local storage and cannot be recovered."
                Write-Warning -Message "Consider revoking the certificate first if it's still valid."
                Write-Information -MessageData "" -InformationAction Continue

                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Write-Warning -Message "`nYou have selected: $($selectedOrder.MainDomain)"
                    Write-Error -Message "Are you sure you want to delete this certificate? (yes/no)"
                    $confirmation = Read-Host
                      if ($confirmation -eq 'yes') {
                        try {
                            # Note: Remove-Certificate doesn't accept MainDomain parameter
                            # It will show a selection menu for the user
                            Write-Host -Object "Launching certificate deletion process..." -ForegroundColor Cyan
                            Remove-Certificate
                            Write-Information -MessageData "Certificate deletion process completed." -InformationAction Continue
                        } catch {
                            Write-Error -Message "Failed to delete certificate: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Warning -Message "Deletion cancelled."
                    }
                } else {
                    Write-Warning -Message "No certificate selected."
                }

                Read-Host "`nPress Enter to continue"
            }
            '0' {
                return
            }
            default {
                Write-Warning -Message "Invalid option. Please try again."
                Read-Host "Press Enter to continue"
            }
        }
    }
}





