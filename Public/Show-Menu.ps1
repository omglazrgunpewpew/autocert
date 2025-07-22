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

function Show-Menu
{
    <#
    .SYNOPSIS
        Displays the main menu for AutoCert
    .DESCRIPTION
        Shows the primary interactive menu for the AutoCert certificate management system
        with current system status and available actions
    .OUTPUTS
        None. This function displays the menu interface.
    .EXAMPLE
        Show-Menu
        Displays the main AutoCert menu
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Clear-Host

    # Initialize ACME server if function is available
    if (Get-Command Initialize-ACMEServer -ErrorAction SilentlyContinue)
    {
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
    try
    {
        $currentServer = (Get-PAServer).Name
        Write-Host -Object "ACME Server: $currentServer" -ForegroundColor Yellow
    } catch
    {
        Write-Host -Object "ACME Server: Not connected" -ForegroundColor Red
    }

    # Show renewal count
    try
    {
        $renewalCount = @(Get-ScriptSettings).Renewals.Count
        if ($renewalCount -gt 0)
        {
            Write-Host -Object "Active Renewals: $renewalCount certificates" -ForegroundColor Green
        } else
        {
            Write-Host -Object "Active Renewals: None configured" -ForegroundColor Yellow
        }
    } catch
    {
        Write-Host -Object "Active Renewals: Unable to determine" -ForegroundColor Red
    }

    Write-Host -Object ""

    # Display menu options
    $menuOptions = @"
  1. Register new certificate
  2. Install certificate
  3. Configure automatic renewal
  4. Certificate management
  5. Options
  6. Credential management
  7. System health check

  S. Show help
  0. Exit

"@

    Write-Host -Object $menuOptions -ForegroundColor White
    Write-Host -Object "Select an option: " -ForegroundColor Cyan -NoNewline
}

# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Show-Menu
