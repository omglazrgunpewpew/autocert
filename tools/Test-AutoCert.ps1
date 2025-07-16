# Test-AutoCertRobustness.ps1
<#
    .SYNOPSIS
        Test runner for AutoCert robustness and resilience features.

    .DESCRIPTION
        This script runs tests for the AutoCert features.
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

# Ensure we're in correct directory
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $scriptRoot "Core\Logging.ps1"))) {
    throw "AutoCert files not found. Please run this script from the AutoCert root directory."
}

# Check if Pester is available
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Warning -Message "Pester module not found. Installing Pester..."
    try {
        Install-Module -Name Pester -Force -SkipPublisherCheck
        Write-Information -MessageData "Pester installed successfully." -InformationAction Continue
    } catch {
        throw "Failed to install Pester: $($_.Exception.Message)"
    }
}

# Import Pester
Import-Module Pester -Force

Write-Host -Object "AutoCert Robustness and Resilience Test Suite" -ForegroundColor Cyan
Write-Host -Object "=" * 50 -ForegroundColor Cyan

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
    Write-Warning -Message "Running tests for category: $TestCategory"
}

if ($SkipSlowTests) {
    Write-Warning -Message "Skipping slow tests..."
}

# Add JUnit output if requested
if ($OutputFormat -eq 'JUnit') {
    $pesterConfig.TestResult = @{
        Enabled = $true
        OutputPath = Join-Path $scriptRoot "TestResults.xml"
        OutputFormat = 'JUnitXml'
    }
}

# Run tests
try {
    Write-Information -MessageData "`nStarting test execution..." -InformationAction Continue
    $startTime = Get-Date

    $results = Invoke-Pester -Configuration ([PesterConfiguration]$pesterConfig)

    $endTime = Get-Date
    $duration = $endTime - $startTime

    # Display results summary
    Write-Host -Object "`n" + "=" * 50 -ForegroundColor Cyan
    Write-Host -Object "TEST RESULTS SUMMARY" -ForegroundColor Cyan
    Write-Host -Object "=" * 50 -ForegroundColor Cyan

    Write-Host -Object "Total Tests: $($results.TotalCount)" -ForegroundColor White
    Write-Information -MessageData "Passed: $($results.PassedCount)" -InformationAction Continue
    Write-Host -Object "Failed: $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { 'Red' } else { 'Gray' })
    Write-Warning -Message "Skipped: $($results.SkippedCount)"
    Write-Host -Object "Duration: $($duration.ToString('mm\:ss\.fff'))" -ForegroundColor Gray

    if ($results.FailedCount -gt 0) {
        Write-Error -Message "`nFAILED TESTS:"
        foreach ($test in $results.Failed) {
            Write-Host -Object "  - $($test.Name)" -ForegroundColor Red
            if ($OutputFormat -eq 'Detailed') {
                Write-Error -Message "    Error: $($test.ErrorRecord.Exception.Message)"
            }
        }

        Write-Warning -Message "`nRecommendations:"
        Write-Warning -Message "1. Check system prerequisites (Admin rights, PowerShell version, modules)"
        Write-Warning -Message "2. Verify all AutoCert modules are properly loaded"
        Write-Warning -Message "3. Review the detailed error messages above"
        Write-Warning -Message "4. Run individual test categories to isolate issues"
    } else {
        Write-Information -MessageData "`n🎉 All tests passed successfully!" -InformationAction Continue
        Write-Information -MessageData "AutoCert robustness and resilience features are working correctly." -InformationAction Continue
    }

    if ($OutputFormat -eq 'JUnit') {
        $xmlPath = Join-Path $scriptRoot "TestResults.xml"
        if (Test-Path $xmlPath) {
            Write-Host -Object "`nJUnit XML results saved to: $xmlPath" -ForegroundColor Gray
        }
    }

    # Return appropriate exit code
    if ($results.FailedCount -gt 0) {
        exit 1
    } else {
        exit 0
    }

} catch {
    Write-Error -Message "Test execution failed: $($_.Exception.Message)"
    Write-Warning -Message "`nTroubleshooting steps:"
    Write-Warning -Message "1. Ensure you're running as Administrator"
    Write-Warning -Message "2. Check that all PowerShell modules are available"
    Write-Warning -Message "3. Verify the AutoCert directory structure is intact"
    Write-Warning -Message "4. Try running a subset of tests first"
    exit 1
}



