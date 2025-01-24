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
. "$PSScriptRoot\Functions\RenewAllCertificates.ps1"

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
    Write-Host "8) Exit"
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
    $choice = Get-ValidatedInput -Prompt "`nEnter your choice (1-8)" -ValidOptions 1,2,3,4,5,6,7,8

    switch ($choice) {
        1 { Register-Certificate }
        2 { Install-Certificate }
        3 { Set-AutomaticRenewal }
        4 { Get-ExistingCertificates }
        5 { Revoke-Certificate }
        6 { Remove-Certificate }
        7 { Show-AdvancedOptions }
        8 {
            Write-Host "`nExiting..."
            Write-Log "User exited the script."
            exit
        }
        default {
            Write-Host "`nInvalid selection. Please choose 1-8." -ForegroundColor Yellow
        }
    }
}
