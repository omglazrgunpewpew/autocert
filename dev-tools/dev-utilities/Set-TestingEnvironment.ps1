<#
    .SYNOPSIS
        Sets up the testing environment for AutoCert development.

    .DESCRIPTION
        This script configures environment variables to prevent Posh-ACME module
        updates during testing and development. It should be run before any testing
        or when working with the AutoCert system in development mode.

    .PARAMETER Force
        Forces the environment setup even if variables are already set.

    .EXAMPLE
        .\Set-TestingEnvironment.ps1
        Sets up testing environment variables.

    .EXAMPLE
        .\Set-TestingEnvironment.ps1 -Force
        Forces setup of testing environment variables.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

# Check if already in testing mode
$alreadyInTestingMode = $env:AUTOCERT_TESTING_MODE -and $env:POSHACME_SKIP_UPGRADE_CHECK

if ($alreadyInTestingMode -and -not $Force)
{
    Write-Host "Testing environment is already configured." -ForegroundColor Green
    Write-Host "AUTOCERT_TESTING_MODE: $env:AUTOCERT_TESTING_MODE" -ForegroundColor Cyan
    Write-Host "POSHACME_SKIP_UPGRADE_CHECK: $env:POSHACME_SKIP_UPGRADE_CHECK" -ForegroundColor Cyan
    return
}

# Set testing environment variables
Write-Host "Configuring testing environment..." -ForegroundColor Yellow

$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Also set for current PowerShell session
[Environment]::SetEnvironmentVariable('AUTOCERT_TESTING_MODE', $true, 'Process')
[Environment]::SetEnvironmentVariable('POSHACME_SKIP_UPGRADE_CHECK', $true, 'Process')

Write-Host "Testing environment configured successfully!" -ForegroundColor Green
Write-Host "The following environment variables are now set:" -ForegroundColor Cyan
Write-Host "  AUTOCERT_TESTING_MODE = $env:AUTOCERT_TESTING_MODE" -ForegroundColor White
Write-Host "  POSHACME_SKIP_UPGRADE_CHECK = $env:POSHACME_SKIP_UPGRADE_CHECK" -ForegroundColor White
Write-Host ""
Write-Host "This will:" -ForegroundColor Yellow
Write-Host "  - Use the bundled Posh-ACME module from the repository" -ForegroundColor White
Write-Host "  - Prevent automatic module updates during testing" -ForegroundColor White
Write-Host "  - Skip module upgrade checks" -ForegroundColor White
Write-Host ""
Write-Host "To clear testing mode, restart your PowerShell session or run:" -ForegroundColor Cyan
Write-Host "  Remove-Item Env:AUTOCERT_TESTING_MODE" -ForegroundColor White
Write-Host "  Remove-Item Env:POSHACME_SKIP_UPGRADE_CHECK" -ForegroundColor White
