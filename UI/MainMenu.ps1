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
    $headerLine = "`n" + ("=" * 70)
    Write-Host -Object $headerLine -ForegroundColor Cyan
    Write-Host -Object "    AUTOCERT LET'S ENCRYPT CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host -Object "                            Version $script:ScriptVersion" -ForegroundColor Gray
    $separatorLine = "=" * 70
    Write-Host -Object $separatorLine -ForegroundColor Cyan

    # Show current ACME server
    try {
        $currentServer = (Get-PAServer).Name
        Write-Warning -Message "ACME Server: $currentServer"
    }
    catch {
        Write-Warning -Message "ACME Server: Not configured"
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

            Write-Information -MessageData "Certificates: $total total" -InformationAction Continue
            if ($needsRenewal -gt 0) {
                Write-Warning -Message "Renewals Needed: $needsRenewal"
            }
            if ($expiringSoon -gt 0) {
                Write-Error -Message "Critically Expiring: $expiringSoon"
            }
        }
        else {
            Write-Warning -Message "Certificates: None configured"
        }
    }
    catch {
        Write-Host -Object "Certificate Status: Unavailable" -ForegroundColor Gray
    }

    # Show system status
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            $taskStatus = if ($task.State -eq "Ready") { "Configured & Active" } else { "Configured but $($task.State)" }
            Write-Host -Object "Auto-Renewal: $taskStatus" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
        }
        else {
            Write-Host -Object "Auto-Renewal: Not configured" -ForegroundColor Yellow
        }
    }
    catch {
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
    $footerLine = "`n" + ("=" * 70)
    Write-Host -Object $footerLine -ForegroundColor Cyan
}

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Show-Menu



