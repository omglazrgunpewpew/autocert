# Tests/RunTests.ps1
<#
    .SYNOPSIS
        Enhanced test runner script for AutoCert test suites.

    .DESCRIPTION
        Runs comprehensive test suites including unit tests, integration tests,
        and resilience tests for the AutoCert certificate management system.
#>

param(
    [Parameter()]
    [ValidateSet('Unit', 'Integration', 'Resilience', 'EmailNotification', 'DNSProvider', 'CertificateLifecycle', 'RenewalAutomation', 'All')]
    [string]$TestType = 'All',

    [Parameter()]
    [string]$OutputFormat = 'NUnitXml',

    [Parameter()]
    [string]$OutputFile = $null,

    [Parameter()]
    [switch]$GenerateReport = $false,

    [Parameter()]
    [switch]$ContinueOnFailure = $false
)

# Set testing environment variables to prevent module updates
$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Define test configurations
$testConfigs = @{
    'Unit'                 = @{
        Scripts     = @('Autocert.Tests.ps1', 'Unit\CompleteViewDeployment.Tests.ps1')
        Description = 'Basic unit tests for core functions'
        Tags        = @('Unit')
    }
    'Integration'          = @{
        Scripts     = @(
            'Autocert.Integration.Tests.ps1',
            'Integration\EmailNotification.Integration.Tests.ps1',
            'Integration\DNSProvider.Integration.Tests.ps1',
            'Integration\CertificateLifecycle.Integration.Tests.ps1',
            'Integration\RenewalAutomation.Integration.Tests.ps1'
        )
        Description = 'End-to-end integration tests including email notifications, DNS providers, certificate lifecycle, and renewal automation'
        Tags        = @('Integration', 'E2E')
    }
    'Resilience'           = @{
        Scripts     = @('Autocert.Resilience.Tests.ps1', 'Autocert.Complete.Tests.ps1')
        Description = 'Error recovery and resilience tests'
        Tags        = @('Resilience', 'ErrorHandling')
    }
    'EmailNotification'    = @{
        Scripts     = @('Integration\EmailNotification.Integration.Tests.ps1')
        Description = 'Email notification system integration tests'
        Tags        = @('Integration', 'EmailNotification', 'E2E')
    }
    'DNSProvider'          = @{
        Scripts     = @('Integration\DNSProvider.Integration.Tests.ps1')
        Description = 'DNS provider API connectivity integration tests'
        Tags        = @('Integration', 'DNSProvider', 'API', 'E2E')
    }
    'CertificateLifecycle' = @{
        Scripts     = @('Integration\CertificateLifecycle.Integration.Tests.ps1')
        Description = 'Complete certificate lifecycle integration tests'
        Tags        = @('Integration', 'CertificateLifecycle', 'E2E', 'Slow')
    }
    'RenewalAutomation'    = @{
        Scripts     = @('Integration\RenewalAutomation.Integration.Tests.ps1')
        Description = 'Renewal automation system integration tests'
        Tags        = @('Integration', 'RenewalAutomation', 'E2E', 'Automation')
    }
}

function Write-TestLog {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        'Info' { 'Cyan' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
    }

    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

function Test-Prerequisite {
    Write-TestLog "Checking test prerequisites..." -Level 'Info'

    # Check Pester module
    try {
        Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
        $pesterVersion = (Get-Module Pester).Version
        Write-TestLog "Pester version $pesterVersion loaded successfully" -Level 'Success'
    }
    catch {
        Write-TestLog "Failed to load Pester module: $($_.Exception.Message)" -Level 'Error'
        return $false
    }

    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5) {
        Write-TestLog "PowerShell $psVersion detected. Version 5.1 or higher recommended." -Level 'Warning'
    }
    else {
        Write-TestLog "PowerShell $psVersion detected" -Level 'Success'
    }

    # Check if running as Administrator for integration tests
    if ($TestType -in @('Integration', 'All')) {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        if (-not $isAdmin) {
            Write-TestLog "Integration tests require Administrator privileges for certificate store operations" -Level 'Warning'
        }
    }

    return $true
}

function Invoke-TestSuite {
    param(
        [string]$SuiteName,
        [hashtable]$Config
    )

    Write-TestLog "Starting $SuiteName test suite: $($Config.Description)" -Level 'Info'

    $suiteResults = @{
        Name         = $SuiteName
        PassedCount  = 0
        FailedCount  = 0
        SkippedCount = 0
        TotalCount   = 0
        Duration     = 0
        Results      = @()
    }

    foreach ($script in $Config.Scripts) {
        $scriptPath = Join-Path $PSScriptRoot $script

        if (-not (Test-Path $scriptPath)) {
            Write-TestLog "Test script not found: $scriptPath" -Level 'Warning'
            continue
        }

        Write-TestLog "Running test script: $script" -Level 'Info'

        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            # Configure Pester for this test run
            $pesterConfig = New-PesterConfiguration
            $pesterConfig.Run.Path = $scriptPath
            $pesterConfig.Run.PassThru = $true
            $pesterConfig.Output.Verbosity = 'Detailed'

            if ($Config.Tags) {
                $pesterConfig.Filter.Tag = $Config.Tags
            }

            if ($OutputFormat -and $OutputFile) {
                $outputPath = $OutputFile -replace '\.xml$', "-$SuiteName.xml"
                $pesterConfig.TestResult.Enabled = $true
                $pesterConfig.TestResult.OutputFormat = $OutputFormat
                $pesterConfig.TestResult.OutputPath = $outputPath
            }

            # Run the tests
            $result = Invoke-Pester -Configuration $pesterConfig

            $stopwatch.Stop()

            # Aggregate results
            $suiteResults.PassedCount += $result.PassedCount
            $suiteResults.FailedCount += $result.FailedCount
            $suiteResults.SkippedCount += $result.SkippedCount
            $suiteResults.TotalCount += $result.TotalCount
            $suiteResults.Duration += $stopwatch.ElapsedMilliseconds
            $suiteResults.Results += $result

            Write-TestLog "Completed $script - Passed: $($result.PassedCount), Failed: $($result.FailedCount), Duration: $($stopwatch.ElapsedMilliseconds)ms" -Level 'Info'

        }
        catch {
            Write-TestLog "Error running test script $script`: $($_.Exception.Message)" -Level 'Error'
            $suiteResults.FailedCount++

            if (-not $ContinueOnFailure) {
                throw
            }
        }
    }

    return [pscustomobject]$suiteResults
}

function New-TestReport {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [array]$Results,
        [timespan]$TotalDuration
    )

    $reportPath = Join-Path $PSScriptRoot "TestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    if ($PSCmdlet.ShouldProcess($reportPath, "Create test report")) {

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AutoCert Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .suite { margin: 20px 0; }
        .passed { color: green; }
        .failed { color: red; }
        .skipped { color: orange; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>AutoCert Test Report</h1>
        <p>Generated: $(Get-Date)</p>
        <p>Total Duration: $($TotalDuration.TotalMinutes.ToString('F2')) minutes</p>
    </div>
"@

        foreach ($result in $Results) {
            $successRate = if ($result.TotalCount -gt 0) {
                ($result.PassedCount / $result.TotalCount * 100).ToString('F1')
            }
            else { 'N/A' }

            $html += @"
    <div class="suite">
        <h2>$($result.Name) Test Suite</h2>
        <table>
            <tr><th>Metric</th><th>Value</th></tr>
            <tr><td>Total Tests</td><td>$($result.TotalCount)</td></tr>
            <tr><td class="passed">Passed</td><td>$($result.PassedCount)</td></tr>
            <tr><td class="failed">Failed</td><td>$($result.FailedCount)</td></tr>
            <tr><td class="skipped">Skipped</td><td>$($result.SkippedCount)</td></tr>
            <tr><td>Success Rate</td><td>$successRate%</td></tr>
            <tr><td>Duration</td><td>$($result.Duration) ms</td></tr>
        </table>
    </div>
"@
        }

        $html += @"
</body>
</html>
"@

        $html | Out-File -FilePath $reportPath -Encoding UTF8
        Write-TestLog "Test report generated: $reportPath" -Level 'Success'

        return $reportPath
    }
    else {
        Write-TestLog "Test report creation was cancelled" -Level 'Warning'
        return $null
    }
}

# Main execution
Write-TestLog "Starting AutoCert test suite runner..." -Level 'Success'
Write-TestLog "Test Type: $TestType" -Level 'Info'
Write-TestLog "Testing mode enabled - using repository's Posh-ACME module" -Level 'Info'

$overallStartTime = Get-Date
$allResults = @()
$exitCode = 0

try {
    # Check prerequisites (function was previously named Test-Prerequisite)
    if (Get-Command Test-Prerequisites -ErrorAction SilentlyContinue) {
        if (-not (Test-Prerequisites)) {
            Write-TestLog "Prerequisites check failed" -Level 'Error'
            exit 1
        }
    }
    elseif (Get-Command Test-Prerequisite -ErrorAction SilentlyContinue) {
        if (-not (Test-Prerequisite)) {
            Write-TestLog "Prerequisite check failed" -Level 'Error'
            exit 1
        }
    }
    else {
        Write-TestLog "Prerequisite function not found. Attempting inline prerequisite validation..." -Level 'Warning'
        # Minimal inline prerequisite validation fallback
        try {
            Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
        }
        catch {
            Write-TestLog "Pester not available. Attempting to install for current user..." -Level 'Warning'
            try {
                # Ensure TLS 1.2 for PowerShellGet
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck -ErrorAction Stop
                Import-Module Pester -ErrorAction Stop
                Write-TestLog "Pester installed successfully." -Level 'Success'
            }
            catch {
                Write-TestLog "Failed to install/import Pester: $($_.Exception.Message)" -Level 'Error'
                exit 1
            }
        }
    }

    # Determine which test suites to run
    $suitesToRun = if ($TestType -eq 'All') {
        @('Unit', 'Integration', 'Resilience')
    }
    else {
        @($TestType)
    }

    # Run test suites
    foreach ($suite in $suitesToRun) {
        if ($testConfigs.ContainsKey($suite)) {
            try {
                $result = Invoke-TestSuite -SuiteName $suite -Config $testConfigs[$suite]
                $allResults += $result

                if ($result.FailedCount -gt 0) {
                    $exitCode = 1
                    if (-not $ContinueOnFailure) {
                        Write-TestLog "Test failures detected in $suite suite. Use -ContinueOnFailure to run remaining suites." -Level 'Error'
                        break
                    }
                }
            }
            catch {
                Write-TestLog "Failed to run $suite test suite: $($_.Exception.Message)" -Level 'Error'
                $exitCode = 1
                if (-not $ContinueOnFailure) {
                    break
                }
            }
        }
    }

    # Generate summary
    $totalDuration = (Get-Date) - $overallStartTime
    $totalPassed = ($allResults | Measure-Object -Property PassedCount -Sum).Sum
    $totalFailed = ($allResults | Measure-Object -Property FailedCount -Sum).Sum
    $totalSkipped = ($allResults | Measure-Object -Property SkippedCount -Sum).Sum
    $totalTests = ($allResults | Measure-Object -Property TotalCount -Sum).Sum

    Write-TestLog "`n=== Test Execution Summary ===" -Level 'Info'
    Write-TestLog "Total Duration: $($totalDuration.TotalMinutes.ToString('F2')) minutes" -Level 'Info'
    Write-TestLog "Total Tests: $totalTests" -Level 'Info'
    Write-TestLog "Passed: $totalPassed" -Level 'Success'
    if ($totalFailed -gt 0) {
        Write-TestLog "Failed: $totalFailed" -Level 'Error'
    }
    else {
        Write-TestLog "Failed: $totalFailed" -Level 'Success'
    }
    if ($totalSkipped -gt 0) {
        Write-TestLog "Skipped: $totalSkipped" -Level 'Warning'
    }

    $successRate = if ($totalTests -gt 0) {
        ($totalPassed / $totalTests * 100).ToString('F1')
    }
    else { 'N/A' }
    Write-TestLog "Success Rate: $successRate%" -Level 'Info'

    # Generate detailed report if requested
    if ($GenerateReport) {
        $reportPath = New-TestReport -Results $allResults -TotalDuration $totalDuration
        Write-TestLog "Detailed HTML report available at: $reportPath" -Level 'Info'
    }

    # Final status
    if ($exitCode -eq 0) {
        Write-TestLog "All tests completed successfully!" -Level 'Success'
    }
    else {
        Write-TestLog "Some tests failed. Check the output above for details." -Level 'Error'
    }

}
catch {
    Write-TestLog "Test execution failed: $($_.Exception.Message)" -Level 'Error'
    Write-TestLog "Stack trace: $($_.ScriptStackTrace)" -Level 'Error'
    $exitCode = 1

}
finally {
    # Clean up environment variables
    Remove-Item env:AUTOCERT_TESTING_MODE -ErrorAction SilentlyContinue
    Remove-Item env:POSHACME_SKIP_UPGRADE_CHECK -ErrorAction SilentlyContinue

    Write-TestLog "Test runner cleanup completed" -Level 'Info'
}

exit $exitCode


