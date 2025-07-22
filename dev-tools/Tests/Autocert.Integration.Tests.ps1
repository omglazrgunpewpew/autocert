# Tests/Autocert.Integration.Tests.ps1
<#
    .SYNOPSIS
        Comprehensive integration tests for AutoCert certificate renewal workflows.

    .DESCRIPTION
        End-to-end integration tests that cover complete certificate lifecycle scenarios
        including registration, renewal, installation, and cleanup processes.

    .NOTES
        These tests require a test environment with proper DNS provider credentials
        and should not be run against production systems.
#>

[CmdletBinding()]
param(
    [string]$TestDomain = "test.example.com",
    [string]$DNSProvider = "Manual",
    [switch]$UseStaging = $true,
    [switch]$SkipCleanup = $false
)

Describe 'AutoCert Integration Tests - Certificate Lifecycle' -Tag @('Integration', 'E2E') {

    BeforeAll {
        # Initialize test environment
        $script:ErrorActionPreference = 'Stop'
        $script:TestStartTime = Get-Date
        $script:TestResults = @{
            Passed        = 0
            Failed        = 0
            Skipped       = 0
            TotalDuration = 0
        }

        # Setup test logging
        $script:TestLogPath = Join-Path $env:TEMP "AutoCert_IntegrationTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        Write-Host "Integration test log: $script:TestLogPath" -ForegroundColor Cyan

        # Set testing environment variables
        $env:AUTOCERT_TESTING_MODE = $true
        $env:POSHACME_SKIP_UPGRADE_CHECK = $true

        # Calculate path to main repository (go up two levels from Tests directory)
        $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

        # Load all AutoCert modules
        $modulePaths = @(
            "$repoRoot\Core\Logging.ps1",
            "$repoRoot\Core\Initialize-PoshAcme.ps1",
            "$repoRoot\Core\Helpers.ps1",
            "$repoRoot\Core\CircuitBreaker.ps1",
            "$repoRoot\Core\ConfigurationManager.ps1",
            "$repoRoot\Core\RenewalConfig.ps1",
            "$repoRoot\Utilities\ErrorHandling.ps1"
        )

        foreach ($module in $modulePaths)
        {
            if (Test-Path $module)
            {
                . $module
                Write-Host "Loaded: $module" -ForegroundColor Green
            } else
            {
                Write-Warning "Module not found: $module"
            }
        }

        # Load all function files from Public directory
        Get-ChildItem "$repoRoot\Public" -Filter '*.ps1' | ForEach-Object {
            . $_.FullName
            Write-Host "Loaded function: $($_.BaseName)" -ForegroundColor Green
        }

        # Initialize test configuration
        $script:TestConfig = @{
            Domain          = $TestDomain
            DNSProvider     = $DNSProvider
            UseStaging      = $UseStaging
            TestCertPath    = Join-Path $env:TEMP "AutoCert_TestCerts"
            BackupPath      = Join-Path $env:TEMP "AutoCert_TestBackup"
            MaxTestDuration = 1800  # 30 minutes max per test
        }

        # Ensure test directories exist
        foreach ($path in @($script:TestConfig.TestCertPath, $script:TestConfig.BackupPath))
        {
            if (-not (Test-Path $path))
            {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }

        # Initialize Posh-ACME for testing
        if ($UseStaging)
        {
            Set-PAServer -DirectoryUrl 'https://acme-staging-v02.api.letsencrypt.org/directory'
        }

        Write-Log "Integration test environment initialized" -Level 'Info'
    }

    Context 'Certificate Registration Workflow' {

        It 'Should successfully register a new certificate with DNS validation' {
            $testName = "Certificate Registration"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                Write-Log "Starting test: $testName" -Level 'Info'

                # Test certificate registration
                $result = Invoke-WithRetry -ScriptBlock {
                    Register-Certificate -Domain $script:TestConfig.Domain -DNSProvider $script:TestConfig.DNSProvider -Force
                } -MaxAttempts 3 -OperationName "Certificate Registration Test"

                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true

                # Verify certificate was created
                $cert = Get-PAOrder -MainDomain $script:TestConfig.Domain
                $cert | Should -Not -BeNullOrEmpty
                $cert.status | Should -Be 'valid'

                Write-Log "Test passed: $testName" -Level 'Success'
                $script:TestResults.Passed++

            } catch
            {
                Write-Log "Test failed: $testName - $($_.Exception.Message)" -Level 'Error'
                $script:TestResults.Failed++
                throw
            } finally
            {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
                Write-Log "Test duration: $($stopwatch.ElapsedMilliseconds)ms" -Level 'Info'
            }
        }

        It 'Should handle DNS provider failures gracefully' {
            $testName = "DNS Provider Failure Handling"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                Write-Log "Starting test: $testName" -Level 'Info'

                # Test with invalid DNS provider to trigger failure handling
                $result = try
                {
                    Register-Certificate -Domain "invalid-test-domain-$(Get-Random).com" -DNSProvider "InvalidProvider" -Force
                } catch
                {
                    $_.Exception.Message
                }

                # Should either handle gracefully or provide meaningful error
                $result | Should -Match "(DNS|provider|credential|invalid)"

                Write-Log "Test passed: $testName" -Level 'Success'
                $script:TestResults.Passed++

            } catch
            {
                Write-Log "Test failed: $testName - $($_.Exception.Message)" -Level 'Error'
                $script:TestResults.Failed++
                throw
            } finally
            {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Certificate Renewal Workflow' {

        It 'Should detect certificates needing renewal' {
            $testName = "Renewal Detection"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                Write-Log "Starting test: $testName" -Level 'Info'

                # Get renewal status
                $config = Get-RenewalConfig
                $renewalStatus = Get-CertificateRenewalStatus -Config $config

                $renewalStatus | Should -Not -BeNullOrEmpty
                $renewalStatus | Should -BeOfType [System.Array]

                # Each renewal status should have required properties
                foreach ($status in $renewalStatus)
                {
                    $status.Domain | Should -Not -BeNullOrEmpty
                    $status.ExpiryDate | Should -BeOfType [DateTime]
                    $status.DaysUntilExpiry | Should -BeOfType [int]
                    $status.NeedsRenewal | Should -BeOfType [bool]
                }

                Write-Log "Test passed: $testName" -Level 'Success'
                $script:TestResults.Passed++

            } catch
            {
                Write-Log "Test failed: $testName - $($_.Exception.Message)" -Level 'Error'
                $script:TestResults.Failed++
                throw
            } finally
            {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should perform automated renewal with retry logic' {
            $testName = "Automated Renewal with Retry"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                Write-Log "Starting test: $testName" -Level 'Info'

                # Test automated renewal process
                $renewalResult = Invoke-AutomatedRenewal -Force

                $renewalResult | Should -Not -BeNullOrEmpty
                $renewalResult.Success | Should -BeOfType [bool]
                $renewalResult.RenewedCount | Should -BeOfType [int]
                $renewalResult.FailedCount | Should -BeOfType [int]
                $renewalResult.SkippedCount | Should -BeOfType [int]

                # Result should have meaningful message
                $renewalResult.Message | Should -Not -BeNullOrEmpty

                Write-Log "Test passed: $testName" -Level 'Success'
                $script:TestResults.Passed++

            } catch
            {
                Write-Log "Test failed: $testName - $($_.Exception.Message)" -Level 'Error'
                $script:TestResults.Failed++
                throw
            } finally
            {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Certificate Installation Workflow' {

        It 'Should install certificates to local certificate store' {
            $testName = "Certificate Installation"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                Write-Log "Starting test: $testName" -Level 'Info'

                # Get an existing certificate to test installation
                $orders = Get-PAOrder
                if ($orders -and $orders.Count -gt 0)
                {
                    $testOrder = $orders[0]

                    # Test certificate installation
                    $installResult = Install-Certificate -Domain $testOrder.MainDomain -Force

                    $installResult | Should -Not -BeNullOrEmpty
                    $installResult.Success | Should -Be $true

                    # Verify certificate was installed
                    $installedCert = Get-ChildItem -Path "Cert:\LocalMachine\My" |
                        Where-Object { $_.Subject -like "*$($testOrder.MainDomain)*" }

                    $installedCert | Should -Not -BeNullOrEmpty
                } else
                {
                    Write-Warning "No certificates available for installation test"
                    $script:TestResults.Skipped++
                    return
                }

                Write-Log "Test passed: $testName" -Level 'Success'
                $script:TestResults.Passed++

            } catch
            {
                Write-Log "Test failed: $testName - $($_.Exception.Message)" -Level 'Error'
                $script:TestResults.Failed++
                throw
            } finally
            {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Error Recovery and Circuit Breaker Tests' {

        It 'Should trigger circuit breaker after repeated failures' {
            $testName = "Circuit Breaker Activation"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                Write-Log "Starting test: $testName" -Level 'Info'

                # Get a circuit breaker instance
                $circuitBreaker = $script:CircuitBreakers['DNSValidation']
                $initialState = $circuitBreaker.State

                # Force multiple failures to trigger circuit breaker
                $failureCount = 0
                for ($i = 1; $i -le 4; $i++)
                {
                    try
                    {
                        $circuitBreaker.Execute({
                                throw "Simulated DNS validation failure $i"
                            }, "TestOperation")
                    } catch
                    {
                        $failureCount++
                        Write-Verbose "Failure $i triggered: $($_.Exception.Message)"
                    }
                }

                # Circuit breaker should be open after threshold failures
                $circuitBreaker.State | Should -Be 'Open'
                $failureCount | Should -BeGreaterThan 2

                Write-Log "Test passed: $testName" -Level 'Success'
                $script:TestResults.Passed++

            } catch
            {
                Write-Log "Test failed: $testName - $($_.Exception.Message)" -Level 'Error'
                $script:TestResults.Failed++
                throw
            } finally
            {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should recover from transient failures using retry logic' {
            $testName = "Transient Failure Recovery"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                Write-Log "Starting test: $testName" -Level 'Info'

                $attemptCount = 0
                $result = Invoke-WithRetry -ScriptBlock {
                    $script:attemptCount++
                    if ($script:attemptCount -lt 3)
                    {
                        throw "Simulated transient failure (attempt $script:attemptCount)"
                    }
                    return "Success after $script:attemptCount attempts"
                } -MaxAttempts 5 -InitialDelaySeconds 1 -OperationName "Transient Failure Test"

                $result | Should -Be "Success after 3 attempts"
                $attemptCount | Should -Be 3

                Write-Log "Test passed: $testName" -Level 'Success'
                $script:TestResults.Passed++

            } catch
            {
                Write-Log "Test failed: $testName - $($_.Exception.Message)" -Level 'Error'
                $script:TestResults.Failed++
                throw
            } finally
            {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Configuration and Health Monitoring' {

        It 'Should validate system configuration' {
            $testName = "Configuration Validation"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try
            {
                Write-Log "Starting test: $testName" -Level 'Info'

                # Test configuration loading
                $config = Get-RenewalConfig
                $config | Should -Not -BeNullOrEmpty

                # Validate required configuration properties
                $requiredProps = @('RenewalThresholdDays', 'RetryAttempts', 'RetryDelay', 'UseRandomization')
                foreach ($prop in $requiredProps)
                {
                    $config.$prop | Should -Not -BeNullOrEmpty
                }

                # Test health check
                if (Get-Command Invoke-HealthCheck -ErrorAction SilentlyContinue)
                {
                    $healthResult = Invoke-HealthCheck
                    $healthResult | Should -Not -BeNullOrEmpty
                }

                Write-Log "Test passed: $testName" -Level 'Success'
                $script:TestResults.Passed++

            } catch
            {
                Write-Log "Test failed: $testName - $($_.Exception.Message)" -Level 'Error'
                $script:TestResults.Failed++
                throw
            } finally
            {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    AfterAll {
        # Cleanup test environment
        if (-not $SkipCleanup)
        {
            Write-Host "Cleaning up test environment..." -ForegroundColor Yellow

            # Remove test certificates
            try
            {
                $testOrders = Get-PAOrder | Where-Object { $_.MainDomain -like "*test*" -or $_.MainDomain -eq $script:TestConfig.Domain }
                foreach ($order in $testOrders)
                {
                    Remove-PAOrder -MainDomain $order.MainDomain -Force -ErrorAction SilentlyContinue
                }
            } catch
            {
                Write-Warning "Cleanup warning: $($_.Exception.Message)"
            }

            # Remove test directories
            foreach ($path in @($script:TestConfig.TestCertPath, $script:TestConfig.BackupPath))
            {
                if (Test-Path $path)
                {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        # Generate test report
        $totalDuration = (Get-Date) - $script:TestStartTime
        $avgDuration = if ($script:TestResults.Passed + $script:TestResults.Failed -gt 0)
        {
            $script:TestResults.TotalDuration / ($script:TestResults.Passed + $script:TestResults.Failed)
        } else { 0 }

        $report = @"

=== AutoCert Integration Test Report ===
Test Start Time: $($script:TestStartTime)
Total Duration: $($totalDuration.TotalMinutes.ToString('F2')) minutes
Average Test Duration: $($avgDuration.ToString('F0'))ms

Results:
- Passed: $($script:TestResults.Passed)
- Failed: $($script:TestResults.Failed)
- Skipped: $($script:TestResults.Skipped)
- Success Rate: $(if (($script:TestResults.Passed + $script:TestResults.Failed) -gt 0) { (($script:TestResults.Passed / ($script:TestResults.Passed + $script:TestResults.Failed)) * 100).ToString('F1') } else { 'N/A' })%

Log File: $script:TestLogPath
"@

        Write-Host $report -ForegroundColor Cyan
        Write-Log $report -Level 'Info'

        if ($script:TestResults.Failed -gt 0)
        {
            Write-Warning "Some integration tests failed. Check the log file for details."
            exit 1
        } else
        {
            Write-Host "All integration tests passed successfully!" -ForegroundColor Green
        }
    }
}
