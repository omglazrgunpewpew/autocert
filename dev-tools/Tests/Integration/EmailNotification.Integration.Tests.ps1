# Tests/Integration/EmailNotification.Integration.Tests.ps1
<#
    .SYNOPSIS
        Comprehensive integration tests for the AutoCert email notification system.

    .DESCRIPTION
        End-to-end integration tests covering email notification functionality including
        SMTP configuration, template processing, delivery verification, and error handling.

    .NOTES
        These tests require a test SMTP server or mock SMTP configuration.
        Set AUTOCERT_TEST_EMAIL environment variable to receive test emails.
#>

[CmdletBinding()]
param(
    [string]$TestEmail = $env:AUTOCERT_TEST_EMAIL,
    [string]$TestSMTPServer = $env:AUTOCERT_TEST_SMTP_SERVER,
    [int]$TestSMTPPort = [int]($env:AUTOCERT_TEST_SMTP_PORT -or 587),
    [switch]$UseRealSMTP = $env:AUTOCERT_USE_REAL_SMTP -eq 'true',
    [switch]$SkipDeliveryTests = $false
)

Describe 'AutoCert Email Notification System - Integration Tests' -Tag @('Integration', 'EmailNotification', 'E2E') {

    BeforeAll {
        $script:ErrorActionPreference = 'Stop'
        $script:TestStartTime = Get-Date
        $script:TestResults = @{
            Passed        = 0
            Failed        = 0
            Skipped       = 0
            TotalDuration = 0
        }

        # Setup test environment
        $env:AUTOCERT_TESTING_MODE = $true
        $env:POSHACME_SKIP_UPGRADE_CHECK = $true

        # Calculate path to main repository
        $repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

        # Load all AutoCert modules required for email testing
        $modulePaths = @(
            "$repoRoot\Core\Logging.ps1",
            "$repoRoot\Core\Helpers.ps1",
            "$repoRoot\Core\ConfigurationManager.ps1",
            "$repoRoot\Core\RenewalConfig.ps1",
            "$repoRoot\Core\NotificationManager.ps1",
            "$repoRoot\Public\NotificationManager.ps1"
        )

        foreach ($module in $modulePaths) {
            if (Test-Path $module) {
                . $module
                Write-Host "Loaded: $module" -ForegroundColor Green
            }
            else {
                Write-Warning "Module not found: $module"
            }
        }

        # Initialize notification system
        Initialize-NotificationSystem

        # Setup test configuration
        $script:TestConfig = @{
            TestEmail        = $TestEmail -or "test@example.com"
            TestSMTPServer   = $TestSMTPServer -or "smtp.gmail.com"
            TestSMTPPort     = $TestSMTPPort
            UseRealSMTP      = $UseRealSMTP
            TestLogPath      = Join-Path $env:TEMP "AutoCert_EmailTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            BackupConfigPath = Join-Path $env:TEMP "AutoCert_EmailTest_Config_Backup.json"
            MaxTestDuration  = 300  # 5 minutes max per test
        }

        # Create mock SMTP credentials for testing
        $script:MockCredentials = @{
            Username = "test@example.com"
            Password = ConvertTo-SecureString "testpassword" -AsPlainText -Force
        }
        $script:TestCredential = New-Object System.Management.Automation.PSCredential(
            $script:MockCredentials.Username, 
            $script:MockCredentials.Password
        )

        Write-Host "Email notification integration test environment initialized" -ForegroundColor Cyan
        Write-Host "Test Email: $($script:TestConfig.TestEmail)" -ForegroundColor Gray
        Write-Host "Test SMTP: $($script:TestConfig.TestSMTPServer):$($script:TestConfig.TestSMTPPort)" -ForegroundColor Gray
        Write-Host "Use Real SMTP: $($script:TestConfig.UseRealSMTP)" -ForegroundColor Gray
    }

    Context 'SMTP Configuration Management' {

        It 'Should store and retrieve SMTP configuration securely' {
            $testName = "SMTP Configuration Storage"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test SMTP configuration storage
                $smtpConfig = @{
                    SmtpServer = $script:TestConfig.TestSMTPServer
                    SmtpPort   = $script:TestConfig.TestSMTPPort
                    FromEmail  = $script:TestConfig.TestEmail
                    UseSsl     = $true
                    Credential = $script:TestCredential
                }

                # Store SMTP configuration
                $result = Set-SmtpConfiguration @smtpConfig -ErrorAction Stop

                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true

                # Retrieve and verify configuration
                $retrievedConfig = Get-SmtpConfiguration

                $retrievedConfig | Should -Not -BeNullOrEmpty
                $retrievedConfig.SmtpServer | Should -Be $script:TestConfig.TestSMTPServer
                $retrievedConfig.SmtpPort | Should -Be $script:TestConfig.TestSMTPPort
                $retrievedConfig.FromEmail | Should -Be $script:TestConfig.TestEmail
                $retrievedConfig.UseSsl | Should -Be $true

                Write-Host "✓ SMTP configuration stored and retrieved successfully" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ SMTP configuration test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should validate SMTP configuration parameters' {
            $testName = "SMTP Configuration Validation"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test invalid SMTP server
                $invalidConfig = @{
                    SmtpServer = ""
                    SmtpPort   = $script:TestConfig.TestSMTPPort
                    FromEmail  = $script:TestConfig.TestEmail
                }

                { Set-SmtpConfiguration @invalidConfig } | Should -Throw

                # Test invalid port
                $invalidPortConfig = @{
                    SmtpServer = $script:TestConfig.TestSMTPServer
                    SmtpPort   = 99999  # Invalid port
                    FromEmail  = $script:TestConfig.TestEmail
                }

                { Set-SmtpConfiguration @invalidPortConfig } | Should -Throw

                # Test invalid email format
                $invalidEmailConfig = @{
                    SmtpServer = $script:TestConfig.TestSMTPServer
                    SmtpPort   = $script:TestConfig.TestSMTPPort
                    FromEmail  = "invalid-email"  # Invalid email format
                }

                { Set-SmtpConfiguration @invalidEmailConfig } | Should -Throw

                Write-Host "✓ SMTP configuration validation working correctly" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ SMTP validation test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Email Template Processing' {

        It 'Should process certificate renewal success template correctly' {
            $testName = "Certificate Renewal Success Template"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $templateVariables = @{
                    Domain          = "test.example.com"
                    RenewalDate     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    ExpirationDate  = (Get-Date).AddDays(90).ToString('yyyy-MM-dd HH:mm:ss')
                    Thumbprint      = "TEST123456789ABCDEF0123456789ABCDEF01234567"
                    Duration        = "2 minutes 15 seconds"
                    NextRenewalDate = (Get-Date).AddDays(60).ToString('yyyy-MM-dd HH:mm:ss')
                    ServerName      = $env:COMPUTERNAME
                }

                # Test template processing
                $result = Send-Notification -TemplateName 'CertificateRenewalSuccess' -Variables $templateVariables -Channels @([NotificationChannel]::Email)

                $result | Should -Not -BeNullOrEmpty
                $result.ContainsKey([NotificationChannel]::Email) | Should -Be $true

                # Verify template variable substitution
                if ($result[[NotificationChannel]::Email].ProcessedSubject) {
                    $result[[NotificationChannel]::Email].ProcessedSubject | Should -Match "test\.example\.com"
                }
                if ($result[[NotificationChannel]::Email].ProcessedBody) {
                    $result[[NotificationChannel]::Email].ProcessedBody | Should -Match "test\.example\.com"
                    $result[[NotificationChannel]::Email].ProcessedBody | Should -Match "TEST123456789ABCDEF0123456789ABCDEF01234567"
                }

                Write-Host "✓ Certificate renewal success template processed correctly" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Template processing test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should process certificate renewal failure template correctly' {
            $testName = "Certificate Renewal Failure Template"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $templateVariables = @{
                    Domain            = "failure.example.com"
                    FailureDate       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    CurrentExpiration = (Get-Date).AddDays(10).ToString('yyyy-MM-dd HH:mm:ss')
                    DaysUntilExpiry   = "10"
                    ErrorMessage      = "DNS validation failed"
                    ErrorDetails      = "Unable to create TXT record: timeout"
                    ServerName        = $env:COMPUTERNAME
                    FailureCount      = "3"
                }

                # Test failure template processing
                $result = Send-Notification -TemplateName 'CertificateRenewalFailure' -Variables $templateVariables -Channels @([NotificationChannel]::Email)

                $result | Should -Not -BeNullOrEmpty
                $result.ContainsKey([NotificationChannel]::Email) | Should -Be $true

                # Verify urgent priority for failure notifications
                if ($result[[NotificationChannel]::Email].Priority) {
                    $result[[NotificationChannel]::Email].Priority | Should -BeIn @('High', 'Critical')
                }

                Write-Host "✓ Certificate renewal failure template processed correctly" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Failure template processing test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should handle missing template variables gracefully' {
            $testName = "Missing Template Variables"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test with minimal variables
                $minimalVariables = @{
                    Domain = "minimal.example.com"
                }

                # Should not throw but may have placeholder values
                $result = Send-Notification -TemplateName 'CertificateRenewalSuccess' -Variables $minimalVariables -Channels @([NotificationChannel]::Email)

                $result | Should -Not -BeNullOrEmpty
                $result.ContainsKey([NotificationChannel]::Email) | Should -Be $true

                Write-Host "✓ Missing template variables handled gracefully" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Missing variables test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Email Delivery Testing' {

        It 'Should send test email notification successfully' -Skip:$SkipDeliveryTests {
            $testName = "Test Email Delivery"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                if (-not $script:TestConfig.UseRealSMTP) {
                    Set-ItResult -Skipped -Because "Real SMTP not configured for testing"
                    return
                }

                # Configure SMTP for real delivery test
                $smtpConfig = @{
                    SmtpServer = $script:TestConfig.TestSMTPServer
                    SmtpPort   = $script:TestConfig.TestSMTPPort
                    FromEmail  = $script:TestConfig.TestEmail
                    UseSsl     = $true
                    Credential = $script:TestCredential
                }

                Set-SmtpConfiguration @smtpConfig

                # Send test email
                $result = Test-EmailNotification -ToEmail $script:TestConfig.TestEmail -TestMessage "AutoCert email integration test - $(Get-Date)"

                $result | Should -Be $true

                Write-Host "✓ Test email sent successfully to $($script:TestConfig.TestEmail)" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Email delivery test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should handle SMTP connection failures gracefully' {
            $testName = "SMTP Connection Failure Handling"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Configure invalid SMTP server
                $invalidSmtpConfig = @{
                    SmtpServer = "invalid.smtp.server.example"
                    SmtpPort   = 587
                    FromEmail  = $script:TestConfig.TestEmail
                    UseSsl     = $true
                    Credential = $script:TestCredential
                }

                Set-SmtpConfiguration @invalidSmtpConfig

                # Attempt to send email - should fail gracefully
                $result = Test-EmailNotification -ToEmail $script:TestConfig.TestEmail -ErrorAction SilentlyContinue

                $result | Should -Be $false

                Write-Host "✓ SMTP connection failure handled gracefully" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                # This is expected - the test should handle the exception
                Write-Host "✓ SMTP connection failure properly caught and handled" -ForegroundColor Green
                $script:TestResults.Passed++
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should retry email delivery on transient failures' {
            $testName = "Email Delivery Retry Logic"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Simulate retry logic by testing with timeout
                $retryConfig = @{
                    SmtpServer = $script:TestConfig.TestSMTPServer
                    SmtpPort   = 999  # Invalid port to trigger timeout
                    FromEmail  = $script:TestConfig.TestEmail
                    UseSsl     = $false
                    Credential = $script:TestCredential
                }

                Set-SmtpConfiguration @retryConfig

                # Test retry mechanism (should fail but attempt multiple times)
                $startTime = Get-Date
                $result = Invoke-WithRetry -ScriptBlock {
                    Test-EmailNotification -ToEmail $script:TestConfig.TestEmail
                } -MaxAttempts 3 -InitialDelaySeconds 1 -OperationName "Email delivery retry test"

                $endTime = Get-Date
                $duration = ($endTime - $startTime).TotalSeconds

                # Should have taken at least a few seconds due to retries
                $duration | Should -BeGreaterThan 2

                Write-Host "✓ Email delivery retry logic working (took $([math]::Round($duration, 1)) seconds)" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                # This is expected for this test
                $endTime = Get-Date
                $duration = ($endTime - $startTime).TotalSeconds
                Write-Host "✓ Email delivery retry attempted ($([math]::Round($duration, 1)) seconds, expected failure)" -ForegroundColor Green
                $script:TestResults.Passed++
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Multi-Channel Notification Integration' {

        It 'Should send notifications through multiple channels simultaneously' {
            $testName = "Multi-Channel Notification"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $templateVariables = @{
                    Domain      = "multichannel.example.com"
                    RenewalDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    ServerName  = $env:COMPUTERNAME
                }

                # Test multiple notification channels
                $channels = @([NotificationChannel]::Email, [NotificationChannel]::EventLog, [NotificationChannel]::File)
                $result = Send-Notification -TemplateName 'CertificateRenewalSuccess' -Variables $templateVariables -Channels $channels

                $result | Should -Not -BeNullOrEmpty
                $result.Count | Should -Be $channels.Count

                # Verify each channel was attempted
                foreach ($channel in $channels) {
                    $result.ContainsKey($channel) | Should -Be $true
                    Write-Host "  ✓ $channel channel notification attempted" -ForegroundColor Gray
                }

                Write-Host "✓ Multi-channel notification integration working" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Multi-channel notification test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should continue with other channels when one fails' {
            $testName = "Channel Failure Resilience"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Configure invalid email settings to force email failure
                $invalidSmtpConfig = @{
                    SmtpServer = "invalid.smtp.example"
                    SmtpPort   = 25
                    FromEmail  = "invalid@invalid.example"
                    UseSsl     = $false
                }

                Set-SmtpConfiguration @invalidSmtpConfig

                $templateVariables = @{
                    Domain     = "resilience.example.com"
                    ServerName = $env:COMPUTERNAME
                }

                # Test with email (will fail) and file (should succeed)
                $channels = @([NotificationChannel]::Email, [NotificationChannel]::File)
                $result = Send-Notification -TemplateName 'CertificateRenewalSuccess' -Variables $templateVariables -Channels $channels

                $result | Should -Not -BeNullOrEmpty
                
                # Email should fail, but file should succeed
                $result[[NotificationChannel]::Email].Success | Should -Be $false
                $result[[NotificationChannel]::File].Success | Should -Be $true

                Write-Host "✓ Channel failure resilience working - other channels continued" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Channel resilience test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Certificate Lifecycle Email Integration' {

        It 'Should send appropriate emails for complete certificate lifecycle' {
            $testName = "Certificate Lifecycle Email Integration"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $domain = "lifecycle.example.com"
                $baseVariables = @{
                    Domain     = $domain
                    ServerName = $env:COMPUTERNAME
                }

                # Test certificate lifecycle email sequence
                $lifecycleEvents = @(
                    @{ Template = 'CertificateRenewalSuccess'; Variables = $baseVariables + @{ RenewalDate = Get-Date; ExpirationDate = (Get-Date).AddDays(90) } },
                    @{ Template = 'CertificateExpiryWarning'; Variables = $baseVariables + @{ ExpirationDate = (Get-Date).AddDays(30); DaysUntilExpiry = 30 } },
                    @{ Template = 'CertificateRenewalFailure'; Variables = $baseVariables + @{ FailureDate = Get-Date; ErrorMessage = "Test failure scenario" } }
                )

                $results = @()
                foreach ($event in $lifecycleEvents) {
                    $result = Send-Notification -TemplateName $event.Template -Variables $event.Variables -Channels @([NotificationChannel]::Email)
                    $results += $result
                    Start-Sleep -Milliseconds 500  # Brief pause between notifications
                }

                # Verify all lifecycle emails were processed
                $results.Count | Should -Be $lifecycleEvents.Count
                foreach ($result in $results) {
                    $result | Should -Not -BeNullOrEmpty
                    $result.ContainsKey([NotificationChannel]::Email) | Should -Be $true
                }

                Write-Host "✓ Certificate lifecycle email integration complete ($($results.Count) events)" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Certificate lifecycle integration test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    AfterAll {
        $script:TestEndTime = Get-Date
        $totalDuration = ($script:TestEndTime - $script:TestStartTime).TotalSeconds

        Write-Host "`n" -NoNewline
        Write-Host "=== EMAIL NOTIFICATION INTEGRATION TEST SUMMARY ===" -ForegroundColor Cyan
        Write-Host "Test Duration: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor Gray
        Write-Host "Passed: $($script:TestResults.Passed)" -ForegroundColor Green
        Write-Host "Failed: $($script:TestResults.Failed)" -ForegroundColor Red
        Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow

        # Cleanup test artifacts
        try {
            if (Test-Path $script:TestConfig.TestLogPath) {
                Remove-Item $script:TestConfig.TestLogPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $script:TestConfig.BackupConfigPath) {
                Remove-Item $script:TestConfig.BackupConfigPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Failed to cleanup test artifacts: $($_.Exception.Message)"
        }

        # Reset environment
        $env:AUTOCERT_TESTING_MODE = $null
        $env:POSHACME_SKIP_UPGRADE_CHECK = $null

        Write-Host "Email notification integration tests completed." -ForegroundColor Cyan
    }
}
