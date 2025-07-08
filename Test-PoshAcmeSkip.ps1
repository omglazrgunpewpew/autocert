#!/usr/bin/env pwsh
# Test script to validate Posh-ACME upgrade skip functionality

Write-Host "=== Testing Posh-ACME Upgrade Skip ===" -ForegroundColor Cyan

# Set environment variable to skip upgrade check
$env:POSHACME_SKIP_UPGRADE_CHECK = $true
Write-Host "Set POSHACME_SKIP_UPGRADE_CHECK = $env:POSHACME_SKIP_UPGRADE_CHECK" -ForegroundColor Yellow

# Test sourcing the Initialize-PoshAcme script
Write-Host "`nTesting Initialize-PoshAcme.ps1..." -ForegroundColor Yellow
try {
    . ./Core/Initialize-PoshAcme.ps1
    Write-Host "✅ Initialize-PoshAcme.ps1 loaded successfully" -ForegroundColor Green
} catch {
    Write-Host "❌ Error loading Initialize-PoshAcme.ps1: $($_.Exception.Message)" -ForegroundColor Red
}

# Run a quick test
Write-Host "`nRunning quick Pester test..." -ForegroundColor Yellow
$testResult = Invoke-Pester -Path './Tests/Autocert.Tests.ps1' -PassThru
Write-Host "Test Result: $($testResult.Result)" -ForegroundColor $(if ($testResult.Result -eq 'Passed') { 'Green' } else { 'Red' })
Write-Host "Duration: $($testResult.Duration)" -ForegroundColor Cyan

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
