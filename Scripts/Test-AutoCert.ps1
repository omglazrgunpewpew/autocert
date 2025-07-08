# Test-AutoCertRobustness.ps1
<#
    .SYNOPSIS
        Test runner for AutoCert robustness and resilience features.
    
    .DESCRIPTION
        This script runs comprehensive tests for the enhanced AutoCert features.
        It validates configuration management, circuit breakers, health monitoring,
        backup systems, and notification functionality.
    
    .PARAMETER TestCategory
        Specific test category to run. If not specified, all tests will run.
    
    .PARAMETER SkipSlowTests
        Skip tests that take a long time to execute.
    
    .PARAMETER OutputFormat
        Format for test output (Normal, Detailed, JUnit).
    
    .EXAMPLE
        .\Test-AutoCertRobustness.ps1
        Run all tests with normal output
    
    .EXAMPLE
        .\Test-AutoCertRobustness.ps1 -TestCategory "Configuration Management" -OutputFormat Detailed
        Run only configuration management tests with detailed output
#>

[CmdletBinding()]
param(
    [ValidateSet('Configuration Management', 'Circuit Breaker Pattern', 'Health Monitoring', 
                 'Backup Management', 'Notification System', 'Error Handling and Retry Logic',
                 'Security and Compliance', 'Performance and Monitoring', 'Integration and End-to-End')]
    [string]$TestCategory,
    
    [switch]$SkipSlowTests,
    
    [ValidateSet('Normal', 'Detailed', 'JUnit')]
    [string]$OutputFormat = 'Normal'
)

# Ensure we're in the correct directory
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $scriptRoot "Core\Logging.ps1"))) {
    throw "AutoCert files not found. Please run this script from the AutoCert root directory."
}

# Check if Pester is available
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Warning "Pester module not found. Installing Pester..."
    try {
        Install-Module -Name Pester -Force -SkipPublisherCheck
        Write-Host "Pester installed successfully." -ForegroundColor Green
    } catch {
        throw "Failed to install Pester: $($_.Exception.Message)"
    }
}

# Import Pester
Import-Module Pester -Force

Write-Host "AutoCert Robustness and Resilience Test Suite" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan

# Configure Pester
$pesterConfig = @{
    Run = @{
        Path = Join-Path $scriptRoot "Tests\Autocert.Resilience.Tests.ps1"
        Exit = $false
    }
    Output = @{
        Verbosity = switch ($OutputFormat) {
            'Detailed' { 'Detailed' }
            'JUnit' { 'Normal' }
            default { 'Normal' }
        }
    }
}

# Add test filtering if specific category requested
if ($TestCategory) {
    $pesterConfig.Filter = @{
        Tag = $TestCategory -replace ' ', ''
    }
    Write-Host "Running tests for category: $TestCategory" -ForegroundColor Yellow
}

if ($SkipSlowTests) {
    Write-Host "Skipping slow tests..." -ForegroundColor Yellow
}

# Add JUnit output if requested
if ($OutputFormat -eq 'JUnit') {
    $pesterConfig.TestResult = @{
        Enabled = $true
        OutputPath = Join-Path $scriptRoot "TestResults.xml"
        OutputFormat = 'JUnitXml'
    }
}

# Run the tests
try {
    Write-Host "`nStarting test execution..." -ForegroundColor Green
    $startTime = Get-Date
    
    $results = Invoke-Pester -Configuration ([PesterConfiguration]$pesterConfig)
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    # Display results summary
    Write-Host "`n" + "=" * 50 -ForegroundColor Cyan
    Write-Host "TEST RESULTS SUMMARY" -ForegroundColor Cyan
    Write-Host "=" * 50 -ForegroundColor Cyan
    
    Write-Host "Total Tests: $($results.TotalCount)" -ForegroundColor White
    Write-Host "Passed: $($results.PassedCount)" -ForegroundColor Green
    Write-Host "Failed: $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { 'Red' } else { 'Gray' })
    Write-Host "Skipped: $($results.SkippedCount)" -ForegroundColor Yellow
    Write-Host "Duration: $($duration.ToString('mm\:ss\.fff'))" -ForegroundColor Gray
    
    if ($results.FailedCount -gt 0) {
        Write-Host "`nFAILED TESTS:" -ForegroundColor Red
        foreach ($test in $results.Failed) {
            Write-Host "  - $($test.Name)" -ForegroundColor Red
            if ($OutputFormat -eq 'Detailed') {
                Write-Host "    Error: $($test.ErrorRecord.Exception.Message)" -ForegroundColor Red
            }
        }
        
        Write-Host "`nRecommendations:" -ForegroundColor Yellow
        Write-Host "1. Check system prerequisites (Admin rights, PowerShell version, modules)" -ForegroundColor Yellow
        Write-Host "2. Verify all AutoCert modules are properly loaded" -ForegroundColor Yellow
        Write-Host "3. Review the detailed error messages above" -ForegroundColor Yellow
        Write-Host "4. Run individual test categories to isolate issues" -ForegroundColor Yellow
    } else {
        Write-Host "`n🎉 All tests passed successfully!" -ForegroundColor Green
        Write-Host "AutoCert robustness and resilience features are working correctly." -ForegroundColor Green
    }
    
    if ($OutputFormat -eq 'JUnit') {
        $xmlPath = Join-Path $scriptRoot "TestResults.xml"
        if (Test-Path $xmlPath) {
            Write-Host "`nJUnit XML results saved to: $xmlPath" -ForegroundColor Gray
        }
    }
    
    # Return appropriate exit code
    if ($results.FailedCount -gt 0) {
        exit 1
    } else {
        exit 0
    }
    
} catch {
    Write-Error "Test execution failed: $($_.Exception.Message)"
    Write-Host "`nTroubleshooting steps:" -ForegroundColor Yellow
    Write-Host "1. Ensure you're running as Administrator" -ForegroundColor Yellow
    Write-Host "2. Check that all PowerShell modules are available" -ForegroundColor Yellow
    Write-Host "3. Verify the AutoCert directory structure is intact" -ForegroundColor Yellow
    Write-Host "4. Try running a subset of tests first" -ForegroundColor Yellow
    exit 1
}
