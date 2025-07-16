# Main Menu System
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 8, 2025

<#
.SYNOPSIS
    Main menu system for AutoCert
.DESCRIPTION
    Provides the primary interactive menu for the AutoCert certificate management system
.NOTES
    Central navigation point for the application
#>

function Show-Menu {
    [CmdletBinding()]
    param()

    Clear-Host

    # Initialize ACME server if function is available
    if (Get-Command Initialize-ACMEServer -ErrorAction SilentlyContinue) {
        Initialize-ACMEServer -ErrorAction SilentlyContinue | Out-Null
    }

    # Display header with system information
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host "    AUTOCERT LET'S ENCRYPT CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host "                            Version $script:ScriptVersion" -ForegroundColor Gray
    Write-Host "="*70 -ForegroundColor Cyan

    # Show current ACME server
    try {
        $currentServer = (Get-PAServer).Name
        Write-Host "ACME Server: $currentServer" -ForegroundColor Yellow
    } catch {
        Write-Host "ACME Server: Not configured" -ForegroundColor Yellow
    }

    # Show certificate summary with status
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config
            $needsRenewal = ($renewalStatus | Where-Object { $_.NeedsRenewal }).Count
            $expiringSoon = ($renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }).Count
            $total = $orders.Count

            Write-Host "Certificates: $total total" -ForegroundColor Green
            if ($needsRenewal -gt 0) {
                Write-Host "Renewals Needed: $needsRenewal" -ForegroundColor Yellow
            }
            if ($expiringSoon -gt 0) {
                Write-Host "Critically Expiring: $expiringSoon" -ForegroundColor Red
            }
        } else {
            Write-Host "Certificates: None configured" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Certificate Status: Unavailable" -ForegroundColor Gray
    }

    # Show system status
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            $taskStatus = if ($task.State -eq "Ready") { "Configured & Active" } else { "Configured but $($task.State)" }
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

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Show-Menu
