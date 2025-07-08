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

# Ensure the script runs with administrative privileges for certificate operations
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "Administrator privileges required for certificate operations." -ForegroundColor Yellow
    Write-Host "Please run this script as an administrator." -ForegroundColor Yellow
    
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

# Enhanced module loading with dependency tracking
function Initialize-ScriptModules {
    [CmdletBinding()]
    param()
    
    try {
        if (-not $NonInteractive) {
            Write-Information "Loading certificate management system..." -InformationAction Continue
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
            @{ Path = "$PSScriptRoot\Functions\Register-Certificate.ps1"; Name = "Certificate Registration"; Critical = $true },
            @{ Path = "$PSScriptRoot\Functions\Install-Certificate.ps1"; Name = "Certificate Installation"; Critical = $true },
            @{ Path = "$PSScriptRoot\Functions\Revoke-Certificate.ps1"; Name = "Certificate Revocation"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Remove-Certificate.ps1"; Name = "Certificate Removal"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Get-ExistingCertificates.ps1"; Name = "Certificate Listing"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Set-AutomaticRenewal.ps1"; Name = "Automatic Renewal"; Critical = $false },
            @{ Path = "$PSScriptRoot\Functions\Show-AdvancedOptions.ps1"; Name = "Advanced Options"; Critical = $false },
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
                    
                    Write-Verbose "Successfully loaded module: $($module.Name)"
                } else {
                    $errorMsg = "Module file not found: $($module.Path)"
                    $script:InitializationErrors += $errorMsg
                    
                    if ($module.Critical) {
                        throw $errorMsg
                    } else {
                        Write-Warning $errorMsg
                    }
                }
            } catch {
                $errorMsg = "Failed to load module '$($module.Name)': $($_.Exception.Message)"
                $script:InitializationErrors += $errorMsg
                
                if ($module.Critical) {
                    throw $errorMsg
                } else {
                    Write-Warning $errorMsg
                }
            }
        }

        if (-not $NonInteractive) {
            Write-ProgressHelper -Activity "System Initialization" -Status "Finalizing..." -PercentComplete 95
        }

        # Verify critical functions are available
        $criticalFunctions = @('Register-Certificate', 'Install-Certificate', 'Write-Log')
        foreach ($func in $criticalFunctions) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                throw "Critical function '$func' is not available"
            }
        }

        if (-not $NonInteractive) {
            Write-ProgressHelper -Activity "System Initialization" -Status "Complete" -PercentComplete 100
            Write-Progress -Activity "System Initialization" -Completed
        }

        Write-Log "Certificate management system loaded successfully (Version: $script:ScriptVersion)" -Level 'Info'
        Write-Log "Loaded modules: $($script:LoadedModules -join ', ')" -Level 'Debug'
        
        if ($script:InitializationErrors.Count -gt 0) {
            Write-Log "Initialization warnings: $($script:InitializationErrors.Count)" -Level 'Warning'
        }

        return $true

    } catch {
        $criticalError = "Failed to load required modules: $($_.Exception.Message)"
        Write-Error $criticalError
        
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $criticalError -Level 'Error'
        }
        
        Write-Host "Please ensure all script files are present and accessible." -ForegroundColor Red
        Write-Host "Missing modules will prevent the system from functioning correctly." -ForegroundColor Red
        
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
    
    Write-Host "Running configuration validation..." -ForegroundColor Cyan
    
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
        Write-Host "`nConfiguration Validation Results:" -ForegroundColor Cyan
        
        if ($configIssues.Count -eq 0) {
            Write-Host "✓ Configuration validation passed" -ForegroundColor Green
        } else {
            Write-Host "✗ Configuration issues found:" -ForegroundColor Red
            $configIssues | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
        }
        
        if ($configWarnings.Count -gt 0) {
            Write-Host "⚠ Configuration warnings:" -ForegroundColor Yellow
            $configWarnings | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
        }
        
        return ($configIssues.Count -eq 0)
        
    } catch {
        Write-Error "Configuration validation failed: $($_.Exception.Message)"
        return $false
    }
}

# Enhanced renewal mode for scheduled tasks
if ($RenewAll) {
    # Initialize modules for renewal mode
    $moduleLoadSuccess = Initialize-ScriptModules
    if (-not $moduleLoadSuccess) {
        Exit 1
    }

    Write-Host "Running in automatic renewal mode..." -ForegroundColor Cyan
    Write-Log "Starting automatic renewal process (Version: $script:ScriptVersion)" -Level 'Info'

    try {
        # Load renewal configuration
        $config = Get-RenewalConfig
        
        # Get all certificates and check renewal status
        $orders = Get-PAOrder
        if (-not $orders) {
            Write-Host "No certificates found to renew." -ForegroundColor Yellow
            Write-Log "No certificates found for renewal" -Level 'Warning'
            Exit 0
        }

        Write-Host "Found $($orders.Count) certificate(s) to check for renewal." -ForegroundColor Green

        $renewalCount = 0
        $errorCount = 0
        $skippedCount = 0
        $results = @()

        foreach ($order in $orders) {
            $mainDomain = $order.MainDomain
            Write-Host "`nProcessing certificate for $mainDomain..." -ForegroundColor Cyan

            try {
                # Get certificate details with caching
                $cert = Get-CachedPACertificate -MainDomain $mainDomain -Force:$Force

                # Check if renewal is needed
                $renewalThreshold = (Get-Date).AddDays($config.RenewalThresholdDays)
                $needsRenewal = $cert.Certificate.NotAfter -le $renewalThreshold

                if (-not $needsRenewal -and -not $Force) {
                    Write-Host "Certificate for $mainDomain is still valid until $($cert.Certificate.NotAfter). Skipping renewal." -ForegroundColor Green
                    $skippedCount++
                    
                    $results += @{
                        Domain = $mainDomain
                        Status = "Skipped"
                        ExpiryDate = $cert.Certificate.NotAfter
                        DaysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                    }
                    continue
                }

                # Perform renewal with retry logic
                Write-Host "Renewing certificate for $mainDomain..." -ForegroundColor Yellow
                Write-Log "Starting renewal for $mainDomain" -Level 'Info'

                $startTime = Get-Date

                # Use enhanced retry logic for renewal
                $newCert = Invoke-WithRetry -ScriptBlock {
                    # Clear cache to force fresh retrieval
                    Clear-CertificateCache
                    
                    # Trigger renewal using New-PACertificate with -Force
                    $renewed = New-PACertificate -MainDomain $mainDomain -Force -Verbose
                    
                    # Verify the renewal was successful
                    if (-not $renewed -or -not $renewed.CertFile) {
                        throw "Certificate renewal did not produce a valid certificate"
                    }
                    
                    return $renewed
                } -MaxAttempts $config.MaxRetries -InitialDelaySeconds ($config.RetryDelayMinutes * 60) `
                  -OperationName "Certificate renewal for $mainDomain" `
                  -SuccessCondition { $null -ne $_ }

                if ($newCert) {
                    $duration = (Get-Date) - $startTime
                    Write-Host "Certificate for $mainDomain renewed successfully in $($duration.TotalMinutes.ToString('F1')) minutes." -ForegroundColor Green
                    Write-Log "Certificate for $mainDomain renewed successfully" -Level 'Success'
                    
                    $renewalCount++

                    # Attempt to reinstall the certificate if it was previously installed
                    try {
                        # Check if certificate exists in local machine store
                        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                        $store.Open("ReadOnly")
                        $existingCert = $store.Certificates | Where-Object { 
                            $_.Subject -like "*$mainDomain*" -or $_.Subject -like "*$($mainDomain.Replace('*.', ''))*"
                        }
                        $store.Close()

                        if ($existingCert) {
                            Write-Host "Reinstalling renewed certificate to certificate store..." -ForegroundColor Cyan
                            Install-PACertificate -PACertificate $newCert -StoreLocation LocalMachine
                            Write-Host "Certificate reinstalled successfully." -ForegroundColor Green
                        }
                    } catch {
                        Write-Warning "Certificate renewed but reinstallation failed: $($_.Exception.Message)"
                        Write-Log "Certificate reinstallation failed for $mainDomain : $($_.Exception.Message)" -Level 'Warning'
                    }

                    $results += @{
                        Domain = $mainDomain
                        Status = "Renewed"
                        ExpiryDate = $newCert.Certificate.NotAfter
                        DaysUntilExpiry = ($newCert.Certificate.NotAfter - (Get-Date)).Days
                        RenewalDuration = $duration
                    }
                }

            } catch {
                Write-Error "Error renewing certificate for ${mainDomain}: $($_.Exception.Message)"
                Write-Log "Error renewing certificate for ${mainDomain}: $($_.Exception.Message)" -Level 'Error'
                $errorCount++

                $results += @{
                    Domain = $mainDomain
                    Status = "Failed"
                    Error = $_.Exception.Message
                    ExpiryDate = if ($cert) { $cert.Certificate.NotAfter } else { "Unknown" }
                }

                # Send notification if email is configured
                if ($config.EmailNotifications -and $config.NotificationEmail) {
                    $subject = "Certificate Renewal Failed: $mainDomain"
                    $body = "Certificate renewal failed for $mainDomain with error: $($_.Exception.Message)"
                    Send-RenewalNotification -Subject $subject -Body $body -ToEmail $config.NotificationEmail
                }
            }
        }

        # Generate comprehensive renewal summary
        Write-Host "`n" + "="*60 -ForegroundColor Cyan
        Write-Host "AUTOMATIC RENEWAL SUMMARY" -ForegroundColor Cyan
        Write-Host "="*60 -ForegroundColor Cyan
        Write-Host "Certificates processed: $($orders.Count)" -ForegroundColor White
        Write-Host "Successful renewals: $renewalCount" -ForegroundColor Green
        Write-Host "Skipped (still valid): $skippedCount" -ForegroundColor Yellow
        Write-Host "Failed renewals: $errorCount" -ForegroundColor Red
        Write-Host "Completion time: $(Get-Date)" -ForegroundColor White
        Write-Host "Total runtime: $((Get-Date) - $script:StartTime)" -ForegroundColor White

        # Detailed results
        if ($results.Count -gt 0) {
            Write-Host "`nDetailed Results:" -ForegroundColor Cyan
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
                
                Write-Host "  $statusLine" -ForegroundColor $color
            }
        }

        # Send summary email if configured
        if ($config.EmailNotifications -and $config.NotificationEmail -and ($renewalCount -gt 0 -or $errorCount -gt 0)) {
            $subject = "Certificate Renewal Summary - $renewalCount renewed, $errorCount failed"
            $body = @"
Certificate Renewal Summary
==========================

Processed: $($orders.Count) certificates
Renewed: $renewalCount
Skipped: $skippedCount  
Failed: $errorCount

Detailed Results:
$($results | ForEach-Object { "$($_.Domain): $($_.Status)" } | Out-String)

Completion Time: $(Get-Date)
Runtime: $((Get-Date) - $script:StartTime)
"@
            Send-RenewalNotification -Subject $subject -Body $body -ToEmail $config.NotificationEmail
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
        Write-Error $msg
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
    Write-Host "AutoCert Certificate Management System - Configuration Test" -ForegroundColor Cyan
    Write-Host "Version: $script:ScriptVersion" -ForegroundColor Gray
    
    $configValid = Test-SystemConfiguration
    
    if ($configValid) {
        Write-Host "`nConfiguration test passed successfully." -ForegroundColor Green
        Exit 0
    } else {
        Write-Host "`nConfiguration test failed." -ForegroundColor Red
        Exit 1
    }
}

# Enhanced interactive mode functions
function Show-Menu {
    Clear-Host
    
    # Initialize ACME server if function is available
    if (Get-Command Initialize-ACMEServer -ErrorAction SilentlyContinue) {
        Initialize-ACMEServer
    }
    
    # Display enhanced header with system information
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host "    AUTOCERT LET'S ENCRYPT CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host "                            Version $script:ScriptVersion" -ForegroundColor Gray
    Write-Host "="*70 -ForegroundColor Cyan
    
    # Show current ACME server
    try {
        $currentServer = (Get-PAServer).Name
        Write-Host "ACME Server: $currentServer" -ForegroundColor Yellow
    } catch {
        Write-Host "ACME Server: Not configured" -ForegroundColor Red
    }
    
    # Show certificate summary with enhanced status
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config
            $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
            $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count
            
            Write-Host "Certificates: $($orders.Count) total" -ForegroundColor Green
            if ($needsRenewal -gt 0) {
                Write-Host "             $needsRenewal need renewal" -ForegroundColor Yellow
            }
            if ($expiringSoon -gt 0) {
                Write-Host "             $expiringSoon expire within 7 days" -ForegroundColor Red
            }
        } else {
            Write-Host "Certificates: None configured" -ForegroundColor Gray
        }
    } catch {
        Write-Host "Certificates: Status unavailable" -ForegroundColor Gray
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
            Write-Host "Auto-Renewal: $taskStatus" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
        } else {
            Write-Host "Auto-Renewal: Not configured" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Auto-Renewal: Status unavailable" -ForegroundColor Gray
    }
    
    Write-Host "`nAvailable Actions:" -ForegroundColor White
    Write-Host "1. Register a new certificate" -ForegroundColor Green
    Write-Host "2. Install existing certificate" -ForegroundColor Cyan
    Write-Host "3. Configure automatic renewal" -ForegroundColor Yellow
    Write-Host "4. View and Manage existing certificates" -ForegroundColor Magenta
    Write-Host "5. Options" -ForegroundColor Blue
    Write-Host "6. Manage Credentials" -ForegroundColor DarkCyan
    Write-Host "7. System health check" -ForegroundColor DarkGreen
    Write-Host "S. Help / About" -ForegroundColor Gray
    Write-Host "0. Exit" -ForegroundColor DarkRed
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
}

# Enhanced credential management menu
function Show-CredentialManagementMenu {
    Clear-Host
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    CREDENTIAL MANAGEMENT" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan

    # List stored credentials
    $credentials = Get-StoredCredential
    if ($credentials.Count -eq 0) {
        Write-Host "No credentials found. You can add new ones." -ForegroundColor Yellow
    } else {
        Write-Host "Stored Credentials:" -ForegroundColor Green
        foreach ($cred in $credentials) {
            Write-Host "  • $($cred.Target)" -ForegroundColor White
        }
    }

    Write-Host "`nAvailable Actions:" -ForegroundColor White
    Write-Host "1. Add new credential" -ForegroundColor Green
    Write-Host "2. Remove credential" -ForegroundColor Red
    Write-Host "3. Test credential" -ForegroundColor Cyan
    Write-Host "0. Return to Main Menu" -ForegroundColor DarkRed
    Write-Host "`n" + "="*60 -ForegroundColor Cyan

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
                Write-Host "Credential added successfully." -ForegroundColor Green
            } catch {
                Write-Error "Failed to add credential: $($_.Exception.Message)"
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
                    Write-Host "Credential removed successfully." -ForegroundColor Green
                } else {
                    Write-Warning "Credential not found."
                }
            } catch {
                Write-Error "Failed to remove credential: $($_.Exception.Message)"
            }
            
            Read-Host "Press Enter to continue"
        }
        '3' {
            # Test credential
            $target = Read-Host "Enter credential target to test"
            
            try {
                $cred = Get-StoredCredential -Target $target
                if ($cred) {
                    # Attempt to use the credential (e.g., test DNS resolution)
                    $username = $cred.UserName
                    $password = $cred.GetNetworkCredential().Password
                    
                    # For demonstration, just display the credential (do not do this in production)
                    Write-Host "Credential for ${target}:" -ForegroundColor Green
                    Write-Host "  Username: $username" -ForegroundColor White
                    Write-Host "  Password: $password" -ForegroundColor White
                } else {
                    Write-Warning "Credential not found."
                }
            } catch {
                Write-Error "Failed to test credential: $($_.Exception.Message)"
            }
            
            Read-Host "Press Enter to continue"
        }
        '0' { return }
        default {
            Write-Warning "Invalid option. Please try again."
            Read-Host "Press Enter to continue"
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
        Write-Host "`n" + "="*70 -ForegroundColor Cyan
        Write-Host "    MANAGING CERTIFICATE: $mainDomain" -ForegroundColor Cyan
        Write-Host "="*70 -ForegroundColor Cyan

        try {
            $certDetails = Get-PACertificate -MainDomain $mainDomain
            $daysUntilExpiry = ($certDetails.Certificate.NotAfter - (Get-Date)).Days
            Write-Host "Status: Valid" -ForegroundColor Green
            Write-Host "Expires: $($certDetails.Certificate.NotAfter) ($daysUntilExpiry days remaining)" -ForegroundColor $(if ($daysUntilExpiry -lt 30) { "Yellow" } else { "Green" })
            Write-Host "Thumbprint: $($certDetails.Thumbprint)" -ForegroundColor Gray
            Write-Host "SANs: $($certDetails.SANs -join ', ')" -ForegroundColor Gray
        } catch {
            Write-Host "Status: Could not retrieve certificate details." -ForegroundColor Red
        }

        Write-Host "`nAvailable Actions for ${mainDomain}:" -ForegroundColor White
        Write-Host "1. Force Renew" -ForegroundColor Yellow
        Write-Host "2. Re-install Certificate" -ForegroundColor Cyan
        Write-Host "3. Revoke Certificate" -ForegroundColor Red
        Write-Host "4. View Details" -ForegroundColor Magenta
        Write-Host "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice for '$mainDomain'"

        switch ($choice) {
            '1' {
                Write-Host "Forcing renewal for $mainDomain..." -ForegroundColor Yellow
                try {
                    $renewed = New-PACertificate -MainDomain $mainDomain -Force
                    if ($renewed) {
                        Write-Host "Certificate for $mainDomain renewed successfully." -ForegroundColor Green
                    } else {
                        Write-Warning "Renewal failed. Check logs for details."
                    }
                } catch {
                    Write-Error "An error occurred during renewal: $($_.Exception.Message)"
                }
                Read-Host "Press Enter to continue"
            }
            '2' {
                # Call the existing Install-Certificate function
                try {
                    $cert = Get-PACertificate -MainDomain $mainDomain
                    if ($cert) {
                        Install-Certificate -PACertificate $cert
                    } else {
                        Write-Warning "Certificate not found for $mainDomain"
                    }
                } catch {
                    Write-Error "Failed to install certificate: $($_.Exception.Message)"
                }
                Read-Host "Press Enter to continue"
            }
            '3' {
                # Call the existing Revoke-Certificate function
                Write-Host "Note: This will show all certificates available for revocation." -ForegroundColor Yellow
                Revoke-Certificate
                Read-Host "Press Enter to continue"
                return # Exit sub-menu after revoke
            }
            '4' {
                Get-PAOrder -MainDomain $mainDomain | Format-List
                Read-Host "Press Enter to continue"
            }
            '0' { return }
            default { Write-Warning "Invalid option. Please try again." }
        }
    }
}

# Enhanced help function
function Show-Help {
    Clear-Host
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host "    HELP / ABOUT - CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host "                            Version $script:ScriptVersion" -ForegroundColor Gray
    Write-Host "="*70 -ForegroundColor Cyan
    
    Write-Host "`nThis tool manages Let's Encrypt certificates using Posh-ACME." -ForegroundColor Gray
    Write-Host "Developed for enterprise environments with automation capabilities." -ForegroundColor Gray
    
    Write-Host "`nKey Features:" -ForegroundColor Yellow
    Write-Host "• Automatic DNS provider detection with 10+ supported providers" -ForegroundColor Green
    Write-Host "• Error handling with exponential backoff retry logic" -ForegroundColor Green
    Write-Host "• Certificate caching for improved performance and reliability" -ForegroundColor Green
    Write-Host "• Renewal scheduling with randomization" -ForegroundColor Green
    Write-Host "• Multiple certificate installation targets (IIS, stores, files)" -ForegroundColor Green
    Write-Host "• Logging and monitoring with event logs" -ForegroundColor Green
    Write-Host "• Email notifications for renewal events and failures" -ForegroundColor Green
    Write-Host "• System health checks and configuration validation" -ForegroundColor Green
    Write-Host "• Multi-format certificate export (PFX, PEM, full-chain)" -ForegroundColor Green
    
    Write-Host "`nMenu Options:" -ForegroundColor Yellow
    Write-Host " 1) Register: Obtain new certificates with automated DNS validation"
    Write-Host " 2) Install: Deploy certificates to various targets with verification"
    Write-Host " 3) Renewal: Set up automated renewal with flexible scheduling"
    Write-Host " 4) Manage: Comprehensive certificate management submenu including:"
    Write-Host "    • View all certificates with detailed status information"
    Write-Host "    • Individual certificate management (renew, reinstall, view details)"
    Write-Host "    • Bulk renewal operations and status checks"
    Write-Host "    • Certificate export in multiple formats"
    Write-Host "    • Safe certificate revocation with confirmation"
    Write-Host "    • Certificate deletion with data cleanup"
    Write-Host " 5) Advanced: ACME server settings, plugins, and configurations"
    Write-Host " 6) Credentials: Secure DNS provider credential management"
    Write-Host " 7) Health: System status, certificate validation, and diagnostics"
    Write-Host " S) Help: This comprehensive information screen"
    Write-Host " 0) Exit: Safely close the application with cleanup"
    
    Write-Host "`nSupported DNS Providers:" -ForegroundColor Yellow
    Write-Host "• Cloudflare, AWS Route53, Azure DNS, Google Cloud DNS"
    Write-Host "• DigitalOcean, DNS Made Easy, Namecheap, GoDaddy"
    Write-Host "• Linode, Vultr, Hetzner, OVH, and many more"
    Write-Host "• Manual DNS (compatible with any DNS provider)"
    
    Write-Host "`nInstallation Targets:" -ForegroundColor Yellow
    Write-Host "• Windows Certificate Store (LocalMachine/CurrentUser)"
    Write-Host "• IIS websites with automatic binding configuration"
    Write-Host "• PEM files for Linux/Apache/Nginx servers"
    Write-Host "• PFX files with custom password protection"
    Write-Host "• Multi-format export for maximum compatibility"
    
    Write-Host "`nBest Practices:" -ForegroundColor Yellow
    Write-Host "• Always run as Administrator for certificate store operations"
    Write-Host "• Test certificates in Let's Encrypt staging before production"
    Write-Host "• Set up automatic renewal at least 30 days before expiry"
    Write-Host "• Keep secure backups of important certificates"
    Write-Host "• Monitor renewal logs and configure email notifications"
    Write-Host "• Use system health checks to validate configuration"
    Write-Host "• Document your certificate deployment procedures"
    
    Write-Host "`nCommand Line Usage:" -ForegroundColor Yellow
    Write-Host "• .\Main.ps1                    # Interactive mode"
    Write-Host "• .\Main.ps1 -RenewAll          # Manual renewal check"
    Write-Host "• .\Main.ps1 -ConfigTest        # Validate configuration"
    Write-Host "• .\Main.ps1 -RenewAll -NonInteractive  # Scheduled task mode"
    
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "• Check log files in %LOCALAPPDATA%\\Posh-ACME\\"
    Write-Host "• Run system health check (option 8) for diagnostics"
    Write-Host "• Verify DNS provider credentials and permissions"
    Write-Host "• Ensure Windows Event Log source is registered"
    Write-Host "• Test internet connectivity to Let's Encrypt API"
    
    Write-Host "`nSupport Information:" -ForegroundColor Gray
    Write-Host "• Script Version: $script:ScriptVersion"
    Write-Host "• PowerShell Version: $($PSVersionTable.PSVersion)"
    Write-Host "• Loaded Modules: $($script:LoadedModules.Count)"
    Write-Host "• Session Started: $($script:StartTime)"
    
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Read-Host "Press Enter to return to the main menu"
}

# Enhanced system health check
function Test-SystemHealth {
    Clear-Host
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    SYSTEM HEALTH CHECK" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    $healthIssues = @()
    $healthWarnings = @()
    
    Write-Host "`nRunning comprehensive system health check..." -ForegroundColor Yellow
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking components..." -PercentComplete 10
    
    # Check PowerShell version
    Write-Host "`n1. PowerShell Environment:" -ForegroundColor Cyan
    $psVersion = $PSVersionTable.PSVersion
    Write-Host "   Version: $psVersion" -ForegroundColor Green
    Write-Host "   Edition: $($PSVersionTable.PSEdition)" -ForegroundColor Green
    Write-Host "   Platform: $($PSVersionTable.Platform)" -ForegroundColor Green
    
    if ($psVersion.Major -lt 5) {
        $healthIssues += "PowerShell version $psVersion is not supported. Minimum version 5.1 required."
    } elseif ($psVersion.Major -eq 5 -and $psVersion.Minor -eq 0) {
        $healthWarnings += "PowerShell 5.0 detected. Version 5.1 or later recommended for best compatibility."
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking modules..." -PercentComplete 20
    
    # Check Posh-ACME module
    Write-Host "`n2. Posh-ACME Module:" -ForegroundColor Cyan
    try {
        $poshAcmeModule = Get-Module -Name Posh-ACME -ListAvailable | Select-Object -First 1
        if ($poshAcmeModule) {
            Write-Host "   Installed: Version $($poshAcmeModule.Version)" -ForegroundColor Green
            Write-Host "   Path: $($poshAcmeModule.ModuleBase)" -ForegroundColor Gray
            
            # Test module import
            Import-Module Posh-ACME -Force
            Write-Host "   Status: Loaded successfully" -ForegroundColor Green
            
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
    Write-Host "`n3. Script Modules:" -ForegroundColor Cyan
    Write-Host "   Loaded Modules: $($script:LoadedModules.Count)" -ForegroundColor Green
    $script:LoadedModules | ForEach-Object { Write-Host "   • $_" -ForegroundColor Gray }
    
    if ($script:InitializationErrors.Count -gt 0) {
        Write-Host "   Initialization Errors: $($script:InitializationErrors.Count)" -ForegroundColor Yellow
        $script:InitializationErrors | ForEach-Object { $healthWarnings += "Module loading: $_" }
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking ACME connectivity..." -PercentComplete 40
    
    # Check ACME server connectivity
    Write-Host "`n4. ACME Server Connectivity:" -ForegroundColor Cyan
    try {
        $server = Get-PAServer
        if ($server) {
            Write-Host "   Server: $($server.Name)" -ForegroundColor Green
            Write-Host "   URL: $($server.location)" -ForegroundColor Green
            
            # Test connectivity with timeout
            $connectivityTest = Invoke-WithRetry -ScriptBlock {
                $response = Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                return $response
            } -MaxAttempts 3 -InitialDelaySeconds 2 -OperationName "ACME server connectivity test"
            
            Write-Host "   Connectivity: OK (Status: $($connectivityTest.StatusCode))" -ForegroundColor Green
            Write-Host "   Response Time: $((Measure-Command { Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 5 }).TotalMilliseconds.ToString('F0')) ms" -ForegroundColor Gray
        } else {
            $healthWarnings += "No ACME server configured"
        }
    } catch {
        $healthIssues += "ACME server connectivity failed: $($_.Exception.Message)"
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking certificates..." -PercentComplete 50
    
    # Check certificate status
    Write-Host "`n5. Certificate Status:" -ForegroundColor Cyan
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config
            
            Write-Host "   Total Certificates: $($orders.Count)" -ForegroundColor Green
            
            $expiringSoon = $renewalStatus | Where-Object { $_.NeedsRenewal }
            $criticallyExpiring = $renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }
            
            if ($criticallyExpiring) {
                Write-Host "   Critically Expiring: $($criticallyExpiring.Count)" -ForegroundColor Red
                foreach ($cert in $criticallyExpiring) {
                    Write-Host "     • $($cert.Domain) (expires in $($cert.DaysUntilExpiry) days)" -ForegroundColor Red
                    $healthIssues += "Certificate $($cert.Domain) expires in $($cert.DaysUntilExpiry) days"
                }
            }
            
            if ($expiringSoon -and $expiringSoon.Count -gt $criticallyExpiring.Count) {
                $soonCount = $expiringSoon.Count - $criticallyExpiring.Count
                Write-Host "   Expiring Soon: $soonCount" -ForegroundColor Yellow
                foreach ($cert in ($expiringSoon | Where-Object { $_.DaysUntilExpiry -gt 7 })) {
                    Write-Host "     • $($cert.Domain) (expires in $($cert.DaysUntilExpiry) days)" -ForegroundColor Yellow
                }
                $healthWarnings += "$soonCount certificate(s) need renewal within $($config.RenewalThresholdDays) days"
            }
            
            if (-not $expiringSoon) {
                Write-Host "   All certificates valid" -ForegroundColor Green
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
            Write-Host "   No certificates configured" -ForegroundColor Gray
        }
    } catch {
        $healthWarnings += "Certificate status check failed: $($_.Exception.Message)"
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking file system..." -PercentComplete 60
    
    # Check file system permissions and paths
    Write-Host "`n6. File System:" -ForegroundColor Cyan
    try {
        $appDataPath = "$env:LOCALAPPDATA\Posh-ACME"
        if (Test-Path $appDataPath) {
            Write-Host "   Data Directory: $appDataPath" -ForegroundColor Green
            
            # Check directory size
            $dirSize = (Get-ChildItem $appDataPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $dirSizeMB = [math]::Round($dirSize / 1MB, 2)
            Write-Host "   Directory Size: $dirSizeMB MB" -ForegroundColor Gray
            
            # Test write permissions
            $testFile = Join-Path $appDataPath "health_check_test.tmp"
            try {
                "health check test" | Out-File -FilePath $testFile
                Remove-Item $testFile -Force
                Write-Host "   Write Permissions: OK" -ForegroundColor Green
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
            Write-Host "   Certificate Store: $certCount certificates in LocalMachine\\My" -ForegroundColor Green
            
            # Test store write access
            try {
                $testStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                $testStore.Open("ReadWrite")
                $testStore.Close()
                Write-Host "   Store Write Access: OK" -ForegroundColor Green
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
    Write-Host "`n7. Automatic Renewal:" -ForegroundColor Cyan
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            Write-Host "   Scheduled Task: Configured" -ForegroundColor Green
            Write-Host "   State: $($task.State)" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
            Write-Host "   Last Run: $($task.LastRunTime)" -ForegroundColor Gray
            Write-Host "   Next Run: $($task.NextRunTime)" -ForegroundColor Gray
            Write-Host "   Last Result: $($task.LastTaskResult)" -ForegroundColor $(if ($task.LastTaskResult -eq 0) { "Green" } else { "Red" })
            
            if ($task.State -ne "Ready") {
                $healthWarnings += "Scheduled task is not in Ready state: $($task.State)"
            }
            
            if ($task.LastTaskResult -ne 0 -and $task.LastTaskResult -ne 267009) { # 267009 = never run
                $healthWarnings += "Scheduled task last execution failed (code: $($task.LastTaskResult))"
            }
        } else {
            Write-Host "   Scheduled Task: Not configured" -ForegroundColor Yellow
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
    Write-Host "`n8. Network and DNS:" -ForegroundColor Cyan
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
            Write-Host "   Internet Connectivity: OK ($connectableHosts/$($internetHosts.Count) DNS servers reachable)" -ForegroundColor Green
        } else {
            $healthIssues += "No internet connectivity detected"
        }
        
        # Test DNS resolution
        try {
            Resolve-DnsName -Name "letsencrypt.org" -Type A -ErrorAction Stop | Out-Null
            Write-Host "   DNS Resolution: OK" -ForegroundColor Green
        } catch {
            $healthIssues += "DNS resolution failed: $($_.Exception.Message)"
        }
        
        # Check proxy settings
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            Write-Host "   Proxy: Enabled ($($proxySettings.ProxyServer))" -ForegroundColor Yellow
            $healthWarnings += "Proxy is enabled, may affect ACME operations"
        } else {
            Write-Host "   Proxy: Direct connection" -ForegroundColor Green
        }
        
    } catch {
        $healthWarnings += "Network check failed: $($_.Exception.Message)"
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking event logging..." -PercentComplete 90
    
    # Check event logging
    Write-Host "`n9. Event Logging:" -ForegroundColor Cyan
    try {
        # Test event log source registration
        $eventSources = Get-WinEvent -ListProvider "Certificate Management" -ErrorAction SilentlyContinue
        if ($eventSources) {
            Write-Host "   Event Source: Registered" -ForegroundColor Green
        } else {
            Write-Host "   Event Source: Not registered" -ForegroundColor Yellow
            $healthWarnings += "Event log source 'Certificate Management' not registered"
        }
        
        # Test event log writing
        try {
            New-EventLog -LogName Application -Source "Certificate Management" -ErrorAction SilentlyContinue
            Write-EventLog -LogName Application -Source "Certificate Management" -EventId 9999 -Message "Health check test event" -ErrorAction Stop
            Write-Host "   Event Writing: OK" -ForegroundColor Green
        } catch {
            $healthWarnings += "Cannot write to event log: $($_.Exception.Message)"
        }
        
    } catch {
        $healthWarnings += "Event logging check failed: $($_.Exception.Message)"
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Finalizing health check..." -PercentComplete 95
    
    # Check system resources
    Write-Host "`n10. System Resources:" -ForegroundColor Cyan
    try {
        $memory = Get-CimInstance -ClassName Win32_ComputerSystem
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        Write-Host "   Total Memory: $totalMemoryGB GB" -ForegroundColor Green
        
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $memoryUsage = [math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 1)
        Write-Host "   Memory Usage: $memoryUsage%" -ForegroundColor $(if ($memoryUsage -lt 80) { "Green" } else { "Yellow" })
        
        if ($memoryUsage -gt 90) {
            $healthWarnings += "High memory usage detected: $memoryUsage%"
        }
        
        # Check available disk space
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
        $diskUsage = [math]::Round((($totalSpaceGB - $freeSpaceGB) / $totalSpaceGB) * 100, 1)
        
        Write-Host "   Disk Space: $freeSpaceGB GB free ($diskUsage% used)" -ForegroundColor $(if ($diskUsage -lt 80) { "Green" } else { "Yellow" })
        
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
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "COMPREHENSIVE HEALTH CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    if ($healthIssues.Count -eq 0 -and $healthWarnings.Count -eq 0) {
        Write-Host "✓ System health: EXCELLENT" -ForegroundColor Green
        Write-Host "  All components are functioning optimally." -ForegroundColor Green
        Write-Host "  No issues or warnings detected." -ForegroundColor Green
    } elseif ($healthIssues.Count -eq 0) {
        Write-Host "⚠ System health: GOOD (with warnings)" -ForegroundColor Yellow
        Write-Host "  System is functional but some optimization is recommended." -ForegroundColor Yellow
        Write-Host "`n  Warnings detected:" -ForegroundColor Yellow
        $healthWarnings | ForEach-Object { Write-Host "    • $_" -ForegroundColor Yellow }
    } else {
        Write-Host "✗ System health: NEEDS ATTENTION" -ForegroundColor Red
        Write-Host "  Critical issues require immediate attention." -ForegroundColor Red
        Write-Host "`n  Critical issues:" -ForegroundColor Red
        $healthIssues | ForEach-Object { Write-Host "    • $_" -ForegroundColor Red }
        
        if ($healthWarnings.Count -gt 0) {
            Write-Host "`n  Additional warnings:" -ForegroundColor Yellow
            $healthWarnings | ForEach-Object { Write-Host "    • $_" -ForegroundColor Yellow }
        }
    }
    
    # Health score calculation
    $issueScore = $healthIssues.Count * 3
    $warningScore = $healthWarnings.Count * 1
    $healthScore = [math]::Max(0, 100 - $issueScore - $warningScore)
    
    Write-Host "`nHealth Score: $healthScore/100" -ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
    Write-Host "Issues: $($healthIssues.Count) critical, $($healthWarnings.Count) warnings" -ForegroundColor White
    Write-Host "Check completed: $(Get-Date)" -ForegroundColor Gray
    Write-Host "Check duration: $((Get-Date) - $script:StartTime)" -ForegroundColor Gray
    
    # Recommendations based on health status
    if ($healthIssues.Count -gt 0 -or $healthWarnings.Count -gt 0) {
        Write-Host "`nRecommended Actions:" -ForegroundColor Cyan
        
        if ($healthIssues.Count -gt 0) {
            Write-Host "• Address critical issues immediately before proceeding" -ForegroundColor Red
            Write-Host "• Run configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor Red
        }
        
        if ($healthWarnings.Count -gt 0) {
            Write-Host "• Review warnings and optimize system configuration" -ForegroundColor Yellow
            Write-Host "• Consider setting up monitoring for detected issues" -ForegroundColor Yellow
        }
        
        Write-Host "• Check log files for additional details" -ForegroundColor White
        Write-Host "• Verify network connectivity and DNS resolution" -ForegroundColor White
        Write-Host "• Ensure sufficient system resources are available" -ForegroundColor White
    }
    
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    
    # Log health check results
    Write-Log "System health check completed - Score: $healthScore/100, Issues: $($healthIssues.Count), Warnings: $($healthWarnings.Count)" -Level 'Info'
    
    Read-Host "Press Enter to return to the main menu"
}

# Enhanced error handling wrapper for menu operations
function Invoke-MenuOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Operation,
        [Parameter(Mandatory = $true)]
        [string]$OperationName
    )
    
    try {
        Write-Host "`nStarting $OperationName..." -ForegroundColor Cyan
        Write-ProgressHelper -Activity "Certificate Management" -Status "Preparing $OperationName..." -PercentComplete 0
        
        $startTime = Get-Date
        & $Operation
        $duration = (Get-Date) - $startTime
        
        Write-Host "`n$OperationName completed successfully in $($duration.TotalSeconds.ToString('F1')) seconds." -ForegroundColor Green
        Write-Log "$OperationName completed successfully" -Level 'Success'
        
    } catch {
        $errorMsg = "$OperationName failed: $($_.Exception.Message)"
        Write-Error $errorMsg
        Write-Log $errorMsg -Level 'Error'
        
        # Enhanced error reporting
        Write-Host "`nError Details:" -ForegroundColor Red
        Write-Host "  Operation: $OperationName" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        
        # Provide context-specific troubleshooting
        Write-Host "`nTroubleshooting suggestions:" -ForegroundColor Yellow
        switch ($OperationName) {
            "certificate registration" {
                Write-Host "• Check DNS provider credentials and permissions" -ForegroundColor Yellow
                Write-Host "• Verify domain ownership and DNS propagation" -ForegroundColor Yellow
                Write-Host "• Test internet connectivity to ACME servers" -ForegroundColor Yellow
            }
            "certificate installation" {
                Write-Host "• Ensure script is running as Administrator" -ForegroundColor Yellow
                Write-Host "• Check certificate store permissions" -ForegroundColor Yellow
                Write-Host "• Verify certificate file integrity" -ForegroundColor Yellow
            }
            default {
                Write-Host "• Check the log files for detailed error information" -ForegroundColor Yellow
                Write-Host "• Run system health check to identify configuration issues" -ForegroundColor Yellow
                Write-Host "• Verify all required modules are loaded correctly" -ForegroundColor Yellow
            }
        }
        
    } finally {
        Write-Progress -Activity "Certificate Management" -Completed
    }
}

# Main script execution starts here
try {
    # Initialize the system
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
            '5' { Show-AdvancedOptions }
            '6' { Show-CredentialManagementMenu }
            '7' { Test-SystemHealth }
            'S' { Show-Help }
            '0' {
                Write-Host "Exiting..." -ForegroundColor Yellow
                Exit 0
            }
            default {
                Write-Warning "Invalid option. Please try again."
                Read-Host "Press Enter to continue"
            }
        }
    }
    
} catch {
    $criticalError = "Critical application error: $($_.Exception.Message)"
    Write-Error $criticalError
    
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $criticalError -Level 'Error'
    }
    
    Write-Host "`nThe application encountered a critical error and must exit." -ForegroundColor Red
    Write-Host "Error details have been logged for troubleshooting." -ForegroundColor Yellow
    
    # Enhanced error information
    Write-Host "`nError Information:" -ForegroundColor Red
    Write-Host "  Message: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Type: $($_.Exception.GetType().Name)" -ForegroundColor Red
    Write-Host "  Location: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "  Time: $(Get-Date)" -ForegroundColor Red
    
    Write-Host "`nTroubleshooting Resources:" -ForegroundColor Yellow
    Write-Host "• Log files: $env:LOCALAPPDATA\Posh-ACME\certificate_script.log" -ForegroundColor Yellow
    Write-Host "• Run configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor Yellow
    Write-Host "• Check system health: .\Main.ps1 and select option 8" -ForegroundColor Yellow
    Write-Host "• Verify all script files are present and accessible" -ForegroundColor Yellow
    
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

# Enhanced certificate management menu
function Show-CertificateManagementMenu {
    while ($true) {
        Clear-Host
        Write-Host "`n" + "="*70 -ForegroundColor Cyan
        Write-Host "    CERTIFICATE MANAGEMENT" -ForegroundColor Cyan
        Write-Host "="*70 -ForegroundColor Cyan

        # Show current certificate summary
        try {
            $orders = Get-PAOrder
            if ($orders) {
                $config = Get-RenewalConfig
                $renewalStatus = Get-CertificateRenewalStatus -Config $config
                $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
                $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count
                $total = $orders.Count
                
                Write-Host "Certificate Summary:" -ForegroundColor Green
                Write-Host "  Total certificates: $total" -ForegroundColor White
                if ($needsRenewal -gt 0) {
                    Write-Host "  Certificates needing renewal: $needsRenewal" -ForegroundColor Yellow
                }
                if ($expiringSoon -gt 0) {
                    Write-Host "  Expiring within 7 days: $expiringSoon" -ForegroundColor Red
                }
                Write-Host ""
            } else {
                Write-Host "No certificates found." -ForegroundColor Yellow
                Write-Host ""
            }
        } catch {
            Write-Host "Could not retrieve certificate summary." -ForegroundColor Red
            Write-Host ""
        }

        Write-Host "Available Actions:" -ForegroundColor White
        Write-Host "1. View all certificates (detailed list)" -ForegroundColor Green
        Write-Host "2. Manage individual certificate" -ForegroundColor Cyan
        Write-Host "3. Bulk renewal check" -ForegroundColor Yellow
        Write-Host "4. Export certificates" -ForegroundColor Blue
        Write-Host "5. Revoke a certificate" -ForegroundColor Red
        Write-Host "6. Delete a certificate" -ForegroundColor Red
        Write-Host "0. Return to Main Menu" -ForegroundColor DarkRed
        Write-Host "`n" + "="*70 -ForegroundColor Cyan

        $choice = Read-Host "Enter your choice"

        switch ($choice) {
            '1' {
                # View all certificates in detailed list format
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    ALL CERTIFICATES - DETAILED VIEW" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                Get-ExistingCertificates
                Read-Host "`nPress Enter to continue"
            }
            '2' {
                # Manage individual certificate - show selection menu
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    SELECT CERTIFICATE TO MANAGE" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Invoke-SingleCertificateManagement -CertificateOrder $selectedOrder
                } else {
                    Write-Host "No certificate selected." -ForegroundColor Yellow
                    Read-Host "Press Enter to continue"
                }
            }
            '3' {
                # Bulk renewal check
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    BULK RENEWAL CHECK" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                try {
                    $orders = Get-PAOrder
                    if ($orders) {
                        $config = Get-RenewalConfig
                        $renewalStatus = Get-CertificateRenewalStatus -Config $config
                        
                        Write-Host "Renewal Status Summary:" -ForegroundColor Green
                        foreach ($status in $renewalStatus) {
                            $color = if ($status.NeedsRenewal) { 
                                if ($status.DaysUntilExpiry -le 7) { "Red" } else { "Yellow" }
                            } else { "Green" }
                            
                            $statusText = if ($status.NeedsRenewal) { "NEEDS RENEWAL" } else { "OK" }
                            Write-Host "  $($status.Domain): $statusText (expires in $($status.DaysUntilExpiry) days)" -ForegroundColor $color
                        }
                        
                        $needsRenewal = $renewalStatus | Where-Object { $_.NeedsRenewal }
                        if ($needsRenewal) {
                            Write-Host "`nWould you like to renew all certificates that need renewal? (y/n)" -ForegroundColor Yellow
                            $renewChoice = Read-Host
                            if ($renewChoice -eq 'y' -or $renewChoice -eq 'Y') {
                                Write-Host "Starting bulk renewal process..." -ForegroundColor Cyan
                                Update-AllCertificates -Force
                            }
                        }
                    } else {
                        Write-Host "No certificates found." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Error "Bulk renewal check failed: $($_.Exception.Message)"
                }
                
                Read-Host "`nPress Enter to continue"
            }
            '4' {
                # Export certificates
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    EXPORT CERTIFICATES" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                try {
                    $orders = Get-PAOrder
                    if ($orders) {
                        Write-Host "Available certificates:" -ForegroundColor Green
                        for ($i = 0; $i -lt $orders.Count; $i++) {
                            Write-Host "  $($i + 1). $($orders[$i].MainDomain)" -ForegroundColor White
                        }
                        Write-Host "  A. All certificates" -ForegroundColor Yellow
                        Write-Host "  0. Cancel" -ForegroundColor Red
                        
                        $exportChoice = Read-Host "`nEnter your choice"
                        
                        if ($exportChoice -eq 'A' -or $exportChoice -eq 'a') {
                            # Export all certificates
                            $exportPath = Read-Host "Enter export directory path (leave blank for current directory)"
                            if ([string]::IsNullOrWhiteSpace($exportPath)) {
                                $exportPath = $PWD.Path
                            }
                            
                            Write-Host "Exporting all certificates to: $exportPath" -ForegroundColor Cyan
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
                                    
                                    Write-Host "  Exported: $($order.MainDomain)" -ForegroundColor Green
                                } catch {
                                    Write-Host "  Failed to export: $($order.MainDomain) - $($_.Exception.Message)" -ForegroundColor Red
                                }
                            }
                            Write-Host "Export completed." -ForegroundColor Green
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
                                
                                Write-Host "Certificate exported successfully to: $domainPath" -ForegroundColor Green
                            } catch {
                                Write-Error "Failed to export certificate: $($_.Exception.Message)"
                            }
                        } elseif ($exportChoice -ne '0') {
                            Write-Host "Invalid choice." -ForegroundColor Red
                        }
                    } else {
                        Write-Host "No certificates found to export." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Error "Export operation failed: $($_.Exception.Message)"
                }
                
                Read-Host "`nPress Enter to continue"
            }
            '5' {
                # Revoke a certificate
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    REVOKE CERTIFICATE" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                Write-Host "Warning: Certificate revocation is permanent and cannot be undone!" -ForegroundColor Red
                Write-Host "Revoked certificates will be immediately invalid for all uses." -ForegroundColor Yellow
                Write-Host ""
                
                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Write-Host "`nYou have selected: $($selectedOrder.MainDomain)" -ForegroundColor Yellow
                    Write-Host "Are you sure you want to revoke this certificate? (yes/no)" -ForegroundColor Red
                    $confirmation = Read-Host
                    
                    if ($confirmation -eq 'yes') {
                        try {
                            # Note: Revoke-Certificate doesn't accept MainDomain parameter
                            # It will show a selection menu for the user
                            Write-Host "Launching certificate revocation process..." -ForegroundColor Cyan
                            Revoke-Certificate
                            Write-Host "Certificate revocation process completed." -ForegroundColor Green
                        } catch {
                            Write-Error "Failed to revoke certificate: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Host "Revocation cancelled." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "No certificate selected." -ForegroundColor Yellow
                }
                
                Read-Host "`nPress Enter to continue"
            }
            '6' {
                # Delete a certificate
                Clear-Host
                Write-Host "`n" + "="*60 -ForegroundColor Cyan
                Write-Host "    DELETE CERTIFICATE" -ForegroundColor Cyan
                Write-Host "="*60 -ForegroundColor Cyan
                
                Write-Host "Warning: This will permanently delete the certificate and all associated data!" -ForegroundColor Red
                Write-Host "The certificate will be removed from local storage and cannot be recovered." -ForegroundColor Yellow
                Write-Host "Consider revoking the certificate first if it's still valid." -ForegroundColor Yellow
                Write-Host ""
                
                $selectedOrder = Get-ExistingCertificates -ShowMenu
                if ($selectedOrder) {
                    Write-Host "`nYou have selected: $($selectedOrder.MainDomain)" -ForegroundColor Yellow
                    Write-Host "Are you sure you want to delete this certificate? (yes/no)" -ForegroundColor Red
                    $confirmation = Read-Host
                      if ($confirmation -eq 'yes') {
                        try {
                            # Note: Remove-Certificate doesn't accept MainDomain parameter
                            # It will show a selection menu for the user
                            Write-Host "Launching certificate deletion process..." -ForegroundColor Cyan
                            Remove-Certificate
                            Write-Host "Certificate deletion process completed." -ForegroundColor Green
                        } catch {
                            Write-Error "Failed to delete certificate: $($_.Exception.Message)"
                        }
                    } else {
                        Write-Host "Deletion cancelled." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "No certificate selected." -ForegroundColor Yellow
                }
                
                Read-Host "`nPress Enter to continue"
            }
            '0' {
                return
            }
            default {
                Write-Warning "Invalid option. Please try again."
                Read-Host "Press Enter to continue"
            }
        }
    }
}