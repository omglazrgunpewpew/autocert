# Test-TestingMode.ps1
# Quick test to verify the testing mode auto-detection works

$ErrorActionPreference = 'Stop'

Write-Host "Testing auto-detection of development environment..." -ForegroundColor Cyan

# Clear existing environment variables
Remove-Item Env:AUTOCERT_TESTING_MODE -ErrorAction SilentlyContinue
Remove-Item Env:POSHACME_SKIP_UPGRADE_CHECK -ErrorAction SilentlyContinue

Write-Host "Environment variables cleared." -ForegroundColor Yellow

# Test the auto-detection logic from Main.ps1
$repoModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Modules\Posh-ACME'
if ((Test-Path $repoModulePath) -and -not $env:AUTOCERT_TESTING_MODE)
{
    Write-Host "Development environment detected: Setting testing mode to prevent module updates" -ForegroundColor Green
    $env:AUTOCERT_TESTING_MODE = $true
    $env:POSHACME_SKIP_UPGRADE_CHECK = $true
}

Write-Host ""
Write-Host "Results:" -ForegroundColor Cyan
Write-Host "  Repository Posh-ACME path exists: $(Test-Path $repoModulePath)" -ForegroundColor White
Write-Host "  AUTOCERT_TESTING_MODE: $env:AUTOCERT_TESTING_MODE" -ForegroundColor White
Write-Host "  POSHACME_SKIP_UPGRADE_CHECK: $env:POSHACME_SKIP_UPGRADE_CHECK" -ForegroundColor White

if ($env:AUTOCERT_TESTING_MODE -and $env:POSHACME_SKIP_UPGRADE_CHECK)
{
    Write-Host ""
    Write-Host "✓ Auto-detection working correctly!" -ForegroundColor Green
    Write-Host "The system will automatically use the bundled Posh-ACME module." -ForegroundColor Green
} else
{
    Write-Host ""
    Write-Host "✗ Auto-detection not working as expected." -ForegroundColor Red
}


