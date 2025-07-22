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

function Show-Help
{
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
    Write-Information -MessageData "- Automatic DNS provider detection with 10+ supported providers" -InformationAction Continue
    Write-Information -MessageData "- Error handling with exponential backoff retry logic" -InformationAction Continue
    Write-Information -MessageData "- Certificate caching for improved performance and reliability" -InformationAction Continue
    Write-Information -MessageData "- Renewal scheduling with randomization" -InformationAction Continue
    Write-Information -MessageData "- Multiple certificate installation targets (IIS, stores, files)" -InformationAction Continue
    Write-Information -MessageData "- Logging and monitoring with event logs" -InformationAction Continue
    Write-Information -MessageData "- Email notifications for renewal events and failures" -InformationAction Continue
    Write-Information -MessageData "- System health checks and configuration validation" -InformationAction Continue
    Write-Host -Object "- Multi-format certificate export (PFX, PEM, full-chain)" -ForegroundColor Green

    Write-Warning -Message "`nMenu Options:"
    Write-Host -Object " 1) Register: Obtain new certificates with automated DNS validation"
    Write-Host -Object " 2) Install: Deploy certificates to various targets with verification"
    Write-Host -Object " 3) Renewal: Set up automated renewal with scheduling"
    Write-Host -Object " 4) Manage: Certificate management submenu including:"
    Write-Host -Object "    - View all certificates with status information"
    Write-Host -Object "    - Individual certificate management (renew, reinstall, view details)"
    Write-Host -Object "    - Bulk renewal operations and status checks"
    Write-Host -Object "    - Certificate export in multiple formats"
    Write-Host -Object "    - Safe certificate revocation with confirmation"
    Write-Host -Object "    - Certificate deletion with data cleanup"
    Write-Host -Object " 5) Options: System configuration and settings"
    Write-Host -Object " 6) Credentials: DNS provider credential management"
    Write-Host -Object " 7) Health: System diagnostics and troubleshooting"

    Write-Warning -Message "`nDNS Providers (Automatic Detection):"
    Write-Host -Object "Cloudflare, Azure DNS, AWS Route53, GoDaddy, Namecheap, Google DNS, and more"

    Write-Warning -Message "`nCertificate Installation Targets:"
    Write-Host -Object "- Windows Certificate Store (Local Machine/Current User)"
    Write-Host -Object "- IIS Server with automatic binding configuration"
    Write-Host -Object "- Apache Server with configuration file updates"
    Write-Host -Object "- File system (PFX, PEM, CRT formats)"
    Write-Host -Object "- Network shares and remote locations"

    Write-Warning -Message "`nAutomation & Scheduling:"
    Write-Host -Object "- Task Scheduler integration for automatic renewals"
    Write-Host -Object "- Configurable renewal windows (30-90 days before expiration)"
    Write-Host -Object "- Randomized execution times to distribute load"
    Write-Host -Object "- Email notifications for success/failure events"
    Write-Host -Object "- Logging integration with Windows Event Log"

    Write-Warning -Message "`nTroubleshooting:"
    Write-Host -Object "- Check Event Viewer > Applications and Services Logs > AutoCert"
    Write-Host -Object "- Review log files in: $env:LOCALAPPDATA\Posh-ACME\"
    Write-Host -Object "- Use 'Health Check' option for system diagnostics"
    Write-Host -Object "- Verify DNS provider credentials in credential management"
    Write-Host -Object "- Ensure proper firewall configuration for ACME challenges"

    Write-Warning -Message "`nSupport & Documentation:"
    Write-Host -Object "- Online documentation: https://github.com/omglazrgunpewpew/autocert"
    Write-Host -Object "- Troubleshooting guides available in docs folder"
    Write-Host -Object "- System requirements: PowerShell 5.1+, Administrator privileges"

    Write-Host -Object "`n" + "="*70 -ForegroundColor Cyan
    Write-Host -Object "Press any key to return to main menu..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Show-Help
