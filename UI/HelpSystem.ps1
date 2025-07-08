# Help System Module
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 8, 2025

<#
.SYNOPSIS
    Help documentation system for AutoCert
.DESCRIPTION
    Provides comprehensive help information about the AutoCert system,
    including features, menu options, and troubleshooting guidance
.NOTES
    Accessed from the main menu with 'S' option
#>

function Show-Help {
    [CmdletBinding()]
    param()
    
    Clear-Host
    Write-Host "`n" + "="*70 -ForegroundColor Cyan
    Write-Host "    HELP / ABOUT - CERTIFICATE MANAGEMENT SYSTEM" -ForegroundColor Cyan
    Write-Host "                            Version $script:ScriptVersion" -ForegroundColor Gray
    Write-Host "="*70 -ForegroundColor Cyan
    
    Write-Host "`nThis tool manages Let's Encrypt certificates using Posh-ACME." -ForegroundColor Gray
    Write-Host "Developed for production environments with automation capabilities." -ForegroundColor Gray
    
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
    Write-Host " 3) Renewal: Set up automated renewal with scheduling"
    Write-Host " 4) Manage: Certificate management submenu including:"
    Write-Host "    • View all certificates with status information"
    Write-Host "    • Individual certificate management (renew, reinstall, view details)"
    Write-Host "    • Bulk renewal operations and status checks"
    Write-Host "    • Certificate export in multiple formats"
    Write-Host "    • Safe certificate revocation with confirmation"
    Write-Host "    • Certificate deletion with data cleanup"
    Write-Host " 5) Options: ACME server settings, plugins, and configurations"
    Write-Host " 6) Credentials: DNS provider credential management"
    Write-Host " 7) Health: System status, certificate validation, and diagnostics"
    Write-Host " S) Help: This information screen"
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

# Export functions
Export-ModuleMember -Function Show-Help
