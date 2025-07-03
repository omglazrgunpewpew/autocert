<#
    .SYNOPSIS
        Main script that orchestrates the menu and calls functions from other scripts.

    .NOTES
        Must be run as Administrator.
#>

# Ensure the script runs with administrative privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Host "You need to run this script as an administrator." -ForegroundColor Yellow
    Exit
}

# Load core scripts
. "$PSScriptRoot\Core\Initialize-PoshAcme.ps1"
. "$PSScriptRoot\Core\Logging.ps1"
. "$PSScriptRoot\Core\Helpers.ps1"

# Load function scripts
. "$PSScriptRoot\Functions\Register-Certificate.ps1"
. "$PSScriptRoot\Functions\Install-Certificate.ps1"
. "$PSScriptRoot\Functions\Revoke-Certificate.ps1"
. "$PSScriptRoot\Functions\Remove-Certificate.ps1"
. "$PSScriptRoot\Functions\Get-ExistingCertificates.ps1"
. "$PSScriptRoot\Functions\Set-AutomaticRenewal.ps1"
. "$PSScriptRoot\Functions\Show-AdvancedOptions.ps1"
. "$PSScriptRoot\Functions\Update-AllCertificates.ps1"

# Main Menu
function Show-Menu {
    Clear-Host
    Initialize-ACMEServer
    Write-Host "=== Let's Encrypt Certificate Management ===`n"
    Write-Host "1) Register a new certificate"
    Write-Host "2) Install certificate"
    Write-Host "3) Configure automatic renewal"
    Write-Host "4) View existing certificates"
    Write-Host "5) Revoke a certificate"
    Write-Host "6) Delete a certificate"
    Write-Host "7) Advanced options"
    Write-Host "8) Help / About"
    Write-Host "9) Exit"
}

# Show help/about information
function Show-Help {
    Clear-Host
    Write-Host "=== Help / About ===`n" -ForegroundColor Cyan
    Write-Host "This tool manages Let's Encrypt certificates using Posh-ACME." -ForegroundColor Gray
    Write-Host "Menu Options:" -ForegroundColor Yellow
    Write-Host " 1) Register a new certificate: Start the process to obtain a new certificate."
    Write-Host " 2) Install certificate: Install a previously obtained certificate."
    Write-Host " 3) Configure automatic renewal: Set up or modify automatic renewal settings."
    Write-Host " 4) View existing certificates: List all certificates managed by this tool."
    Write-Host " 5) Revoke a certificate: Revoke a certificate that is no longer needed."
    Write-Host " 6) Delete a certificate: Remove a certificate from the system."
    Write-Host " 7) Advanced options: Access advanced features and settings."
    Write-Host " 8) Help / About: Show this help information."
    Write-Host " 9) Exit: Quit the tool."
    Write-Host "\nFor best results, run as Administrator."
    Write-Host "\nFor more information, see the README.md file."
    Write-Host "\nPress any key to return to the menu..."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

# Main script logic
param(
    [switch]$RenewAll
)

if ($RenewAll) {
    # If run with -RenewAll, jump straight to renewing all orders
    Update-Certificates
    exit
}

while ($true) {
    Show-Menu
    # Enhanced input validation and progress feedback
    $choice = $null
    while ($null -eq $choice) {
        $inputRaw = Read-Host "`nEnter your choice (1-9)"
        if ($inputRaw -match '^[1-9]$') {
            $choice = [int]$inputRaw
        } else {
            Write-Host "Invalid selection. Please enter a number between 1 and 9." -ForegroundColor Yellow
        }
    }

    switch ($choice) {
        1 {
            Write-Host "\nStarting certificate registration..." -ForegroundColor Cyan
            Register-Certificate
            Write-Host "\nOperation complete. Press any key to return to the menu..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        2 {
            Write-Host "\nStarting certificate installation..." -ForegroundColor Cyan
            Install-Certificate
            Write-Host "\nOperation complete. Press any key to return to the menu..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        3 {
            Write-Host "\nConfiguring automatic renewal..." -ForegroundColor Cyan
            Set-AutomaticRenewal
            Write-Host "\nOperation complete. Press any key to return to the menu..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        4 {
            Write-Host "\nRetrieving existing certificates..." -ForegroundColor Cyan
            Get-ExistingCertificates
            Write-Host "\nOperation complete. Press any key to return to the menu..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        5 {
            Write-Host "\nRevoking certificate..." -ForegroundColor Cyan
            Revoke-Certificate
            Write-Host "\nOperation complete. Press any key to return to the menu..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        6 {
            Write-Host "\nDeleting certificate..." -ForegroundColor Cyan
            Remove-Certificate
            Write-Host "\nOperation complete. Press any key to return to the menu..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        7 {
            Write-Host "\nOpening advanced options..." -ForegroundColor Cyan
            Show-AdvancedOptions
            Write-Host "\nOperation complete. Press any key to return to the menu..."
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        8 {
            Show-Help
        }
        9 {
            Write-Host "`nExiting..."
            Write-Log "User exited the script."
            exit
        }
        default {
            Write-Host "`nInvalid selection. Please choose 1-9." -ForegroundColor Yellow
        }
    }
}
