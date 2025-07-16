# Help System Module
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 8, 2025

<#
.SYNOPSIS
    Help documentation system for AutoCert
.DESCRIPTION
    Provides help information about the AutoCert system,
    including features, menu options, and troubleshooting guidance
.NOTES
    Accessed from the main menu with 'S' option
#>

function Show-Help {
    [CmdletBinding()]
    param()

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
    Write-Information -MessageData "• Certificate caching for improved performance and reliability" -InformationAction Continue
    Write-Information -MessageData "• Renewal scheduling with randomization" -InformationAction Continue
    Write-Information -MessageData "• Multiple certificate installation targets (IIS, stores, files)" -InformationAction Continue
    Write-Information -MessageData "• Logging and monitoring with event logs" -InformationAction Continue
    Write-Information -MessageData "• Email notifications for renewal events and failures" -InformationAction Continue
    Write-Information -MessageData "• System health checks and configuration validation" -InformationAction Continue
    Write-Host -Object "• Multi-format certificate export (PFX, PEM, full-chain)" -ForegroundColor Green

    Write-Warning -Message "`nMenu Options:"
    Write-Host -Object " 1) Register: Obtain new certificates with automated DNS validation"
    Write-Host -Object " 2) Install: Deploy certificates to various targets with verification"
    Write-Host -Object " 3) Renewal: Set up automated renewal with scheduling"
    Write-Host -Object " 4) Manage: Certificate management submenu including:"
    Write-Host -Object "    • View all certificates with status information"
    Write-Host -Object "    • Individual certificate management (renew, reinstall, view details)"
    Write-Host -Object "    • Bulk renewal operations and status checks"
    Write-Host -Object "    • Certificate export in multiple formats"
    Write-Host -Object "    • Safe certificate revocation with confirmation"
    Write-Host -Object "    • Certificate deletion with data cleanup"
    Write-Host -Object " 5) Options: ACME server settings, plugins, and configurations"
    Write-Host -Object " 6) Credentials: DNS provider credential management"
    Write-Host -Object " 7) Health: System status, certificate validation, and diagnostics"
    Write-Host -Object " S) Help: This information screen"
    Write-Host -Object " 0) Exit: Safely close the application with cleanup"

    Write-Warning -Message "`nSupported DNS Providers:"
    Write-Host -Object "• Cloudflare, AWS Route53, Azure DNS, Google Cloud DNS"
    Write-Host -Object "• DigitalOcean, DNS Made Easy, Namecheap, GoDaddy"
    Write-Host -Object "• Linode, Vultr, Hetzner, OVH, and many more"
    Write-Host -Object "• Manual DNS (compatible with any DNS provider)"

    Write-Warning -Message "`nInstallation Targets:"
    Write-Host -Object "• Windows Certificate Store (LocalMachine/CurrentUser)"
    Write-Host -Object "• IIS websites with automatic binding configuration"
    Write-Host -Object "• PEM files for Linux/Apache/Nginx servers"
    Write-Host -Object "• PFX files with custom password protection"
    Write-Host -Object "• Multi-format export for maximum compatibility"

    Write-Warning -Message "`nBest Practices:"
    Write-Host -Object "• Always run as Administrator for certificate store operations"
    Write-Host -Object "• Test certificates in Let's Encrypt staging before production"
    Write-Host -Object "• Set up automatic renewal at least 30 days before expiry"
    Write-Host -Object "• Keep secure backups of important certificates"
    Write-Host -Object "• Monitor renewal logs and configure email notifications"
    Write-Host -Object "• Use system health checks to validate configuration"
    Write-Host -Object "• Document your certificate deployment procedures"

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

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Show-Help



