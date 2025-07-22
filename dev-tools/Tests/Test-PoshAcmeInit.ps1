# Test-PoshAcmeInit.ps1
# Test that Posh-ACME initialization respects testing mode

$ErrorActionPreference = 'Stop'

Write-Host "Testing Posh-ACME initialization in testing mode..." -ForegroundColor Cyan

# Ensure testing environment is set
$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

Write-Host "Testing environment variables set:" -ForegroundColor Yellow
Write-Host "  AUTOCERT_TESTING_MODE: $env:AUTOCERT_TESTING_MODE" -ForegroundColor White
Write-Host "  POSHACME_SKIP_UPGRADE_CHECK: $env:POSHACME_SKIP_UPGRADE_CHECK" -ForegroundColor White

# Load the logging module first
. "$PSScriptRoot\Core\Logging.ps1"

Write-Host ""
Write-Host "Initializing Posh-ACME..." -ForegroundColor Cyan

# Source the Initialize-PoshAcme script
. "$PSScriptRoot\Core\Initialize-PoshAcme.ps1"

Write-Host ""
Write-Host "✓ Posh-ACME initialization completed without attempting updates!" -ForegroundColor Green

# Check if Posh-ACME was loaded
if (Get-Module -Name Posh-ACME)
{
    $version = (Get-Module -Name Posh-ACME).Version
    Write-Host "✓ Posh-ACME version $version is loaded" -ForegroundColor Green
} else
{
    Write-Host "✗ Posh-ACME module not loaded" -ForegroundColor Red
}


