# Tests/Integration/DNSProvider.Integration.Tests.ps1
<#
    .SYNOPSIS
        Comprehensive integration tests for DNS provider API connectivity and functionality.

    .DESCRIPTION
        End-to-end integration tests covering DNS provider detection, API connectivity,
        credential validation, and DNS challenge operations across multiple providers.

    .NOTES
        These tests require valid DNS provider credentials for full testing.
        Set environment variables for each provider to enable real API testing.
        AUTOCERT_TEST_DOMAIN should be set to a domain you control for testing.
#>

[CmdletBinding()]
param(
    [string]$TestDomain = $env:AUTOCERT_TEST_DOMAIN,
    [string]$CloudflareToken = $env:AUTOCERT_TEST_CLOUDFLARE_TOKEN,
    [string]$CombellApiKey = $env:AUTOCERT_TEST_COMBELL_API_KEY,
    [string]$CombellApiSecret = $env:AUTOCERT_TEST_COMBELL_API_SECRET,
    [string]$AWSAccessKey = $env:AUTOCERT_TEST_AWS_ACCESS_KEY,
    [string]$AWSSecretKey = $env:AUTOCERT_TEST_AWS_SECRET_KEY,
    [switch]$SkipRealAPITests = $env:AUTOCERT_SKIP_REAL_API_TESTS -eq 'true',
    [switch]$UseStaging = $true
)

Describe 'AutoCert DNS Provider API Connectivity - Integration Tests' -Tag @('Integration', 'DNSProvider', 'API', 'E2E') {

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

        # Load all AutoCert modules required for DNS testing
        $modulePaths = @(
            "$repoRoot\Core\Logging.ps1",
            "$repoRoot\Core\Helpers.ps1",
            "$repoRoot\Core\ConfigurationManager.ps1",
            "$repoRoot\Core\Initialize-PoshAcme.ps1",
            "$repoRoot\Core\DNSProvider\DNSProviderDetection.ps1",
            "$repoRoot\Core\DNSProvider\DNSProviderCore.ps1",
            "$repoRoot\Core\DNSProvider\DNSProviderAPITesting.ps1"
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

        # Initialize Posh-ACME for testing
        Initialize-PoshAcme

        # Setup test configuration
        $script:TestConfig = @{
            TestDomain       = $TestDomain -or "test.example.com"
            UseStaging       = $UseStaging
            SkipRealAPITests = $SkipRealAPITests
            TestLogPath      = Join-Path $env:TEMP "AutoCert_DNSTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            MaxTestDuration  = 300  # 5 minutes max per test
            APITimeout       = 30   # 30 seconds for API calls
        }

        # Setup test credentials
        $script:TestCredentials = @{
            Cloudflare = @{
                CFToken = $CloudflareToken
            }
            Combell    = @{
                CombellApiKey    = $CombellApiKey
                CombellApiSecret = $CombellApiSecret
            }
            AWS        = @{
                AWSAccessKeyId     = $AWSAccessKey
                AWSSecretAccessKey = $AWSSecretKey
            }
        }

        Write-Host "DNS provider integration test environment initialized" -ForegroundColor Cyan
        Write-Host "Test Domain: $($script:TestConfig.TestDomain)" -ForegroundColor Gray
        Write-Host "Real API Tests: $(-not $script:TestConfig.SkipRealAPITests)" -ForegroundColor Gray
        Write-Host "Use Staging: $($script:TestConfig.UseStaging)" -ForegroundColor Gray
    }

    Context 'DNS Provider Detection and Discovery' {

        It 'Should detect DNS provider from domain NS records' {
            $testName = "DNS Provider Detection"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test DNS provider detection
                $result = Get-DNSProvider -Domain $script:TestConfig.TestDomain

                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Not -BeNullOrEmpty
                $result.Plugin | Should -Not -BeNullOrEmpty
                $result.Confidence | Should -BeIn @('High', 'Medium', 'Low', 'None')
                $result.NSRecords | Should -Not -BeNullOrEmpty

                Write-Host "✓ DNS provider detected: $($result.Name) (Confidence: $($result.Confidence))" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ DNS provider detection failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should provide extended DNS provider information' {
            $testName = "Extended DNS Provider Info"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test extended DNS provider information
                $result = Get-DNSProviderExtended -Domain $script:TestConfig.TestDomain

                $result | Should -Not -BeNullOrEmpty
                $result.Name | Should -Not -BeNullOrEmpty
                $result.Description | Should -Not -BeNullOrEmpty
                $result.DetectionMethod | Should -Not -BeNullOrEmpty

                # Should include setup information
                if ($result.SetupUrl) {
                    $result.SetupUrl | Should -Match '^https?://'
                }

                Write-Host "✓ Extended DNS provider info retrieved for $($result.Name)" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Extended DNS provider info test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should cache DNS provider detection results' {
            $testName = "DNS Provider Caching"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # First call - should perform detection
                $firstResult = Get-DNSProvider -Domain $script:TestConfig.TestDomain
                $firstCallTime = (Measure-Command { 
                        $secondResult = Get-DNSProvider -Domain $script:TestConfig.TestDomain 
                    }).TotalMilliseconds

                # Second call should be faster due to caching
                $firstCallTime | Should -BeLessThan 1000  # Should be very fast from cache

                $firstResult.Name | Should -Be $secondResult.Name
                $firstResult.Plugin | Should -Be $secondResult.Plugin

                Write-Host "✓ DNS provider caching working (cached call: $([math]::Round($firstCallTime, 1))ms)" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ DNS provider caching test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should handle apex domain detection correctly' {
            $testName = "Apex Domain Detection"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test with subdomain to verify apex detection
                $subdomain = "www.$($script:TestConfig.TestDomain)"
                $result = Get-DNSProvider -Domain $subdomain

                $result | Should -Not -BeNullOrEmpty
                
                # If detected from apex, should have the flag set
                if ($result.DetectedFromApex) {
                    $result.OriginalDomain | Should -Be $subdomain
                    Write-Host "✓ Apex domain detection triggered for subdomain" -ForegroundColor Green
                }
                else {
                    Write-Host "✓ Direct detection successful for subdomain" -ForegroundColor Green
                }

                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Apex domain detection test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'DNS Provider API Connectivity Testing' {

        It 'Should test Cloudflare API connectivity' -Skip:($script:TestConfig.SkipRealAPITests -or -not $script:TestCredentials.Cloudflare.CFToken) {
            $testName = "Cloudflare API Connectivity"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test Cloudflare API connectivity
                $result = Test-CloudflareAPI -Credentials $script:TestCredentials.Cloudflare -TestDomain $script:TestConfig.TestDomain -TimeoutSeconds $script:TestConfig.APITimeout

                $result | Should -Not -BeNullOrEmpty
                $result.Provider | Should -Be 'Cloudflare'
                $result.Success | Should -Be $true
                $result.Status | Should -Be 'Connected'
                $result.Details | Should -Not -BeNullOrEmpty

                # Verify API details
                $result.Details.UserEmail | Should -Not -BeNullOrEmpty
                $result.Details.APIStatus | Should -Be 'Active'

                Write-Host "✓ Cloudflare API connectivity confirmed" -ForegroundColor Green
                Write-Host "  User: $($result.Details.UserEmail)" -ForegroundColor Gray
                Write-Host "  Zone Access: $($result.Details.ZoneAccess)" -ForegroundColor Gray
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Cloudflare API test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should test Combell API connectivity' -Skip:($script:TestConfig.SkipRealAPITests -or -not $script:TestCredentials.Combell.CombellApiKey) {
            $testName = "Combell API Connectivity"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test Combell API connectivity
                $result = Test-CombellAPI -Credentials $script:TestCredentials.Combell -TestDomain $script:TestConfig.TestDomain -TimeoutSeconds $script:TestConfig.APITimeout

                $result | Should -Not -BeNullOrEmpty
                $result.Provider | Should -Be 'Combell'
                $result.Success | Should -Be $true
                $result.Status | Should -Be 'Connected'
                $result.Details | Should -Not -BeNullOrEmpty

                # Verify API details
                $result.Details.APIStatus | Should -Be 'Active'
                $result.Details.DomainsFound | Should -BeGreaterOrEqual 0

                Write-Host "✓ Combell API connectivity confirmed" -ForegroundColor Green
                Write-Host "  Domains Found: $($result.Details.DomainsFound)" -ForegroundColor Gray
                Write-Host "  Domain Access: $($result.Details.DomainAccess)" -ForegroundColor Gray
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Combell API test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should handle invalid API credentials gracefully' {
            $testName = "Invalid API Credentials Handling"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test with invalid Cloudflare token
                $invalidCredentials = @{
                    CFToken = "invalid_token_12345"
                }

                $result = Test-CloudflareAPI -Credentials $invalidCredentials -TestDomain $script:TestConfig.TestDomain -TimeoutSeconds $script:TestConfig.APITimeout

                $result | Should -Not -BeNullOrEmpty
                $result.Provider | Should -Be 'Cloudflare'
                $result.Success | Should -Be $false
                $result.Status | Should -BeIn @('API Error', 'Connection Failed', 'Authentication Failed')

                Write-Host "✓ Invalid API credentials handled gracefully" -ForegroundColor Green
                Write-Host "  Status: $($result.Status)" -ForegroundColor Gray
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Invalid credentials test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should handle API timeout scenarios' {
            $testName = "API Timeout Handling"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test with very short timeout to trigger timeout scenario
                $shortTimeout = 1  # 1 second timeout

                $startTime = Get-Date
                $result = Test-DNSProviderAPI -ProviderName 'Cloudflare' -Credentials @{ CFToken = 'test' } -TestDomain $script:TestConfig.TestDomain -TimeoutSeconds $shortTimeout

                $endTime = Get-Date
                $actualDuration = ($endTime - $startTime).TotalSeconds

                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $false
                
                # Should have failed within reasonable time frame
                $actualDuration | Should -BeLessOrEqual ($shortTimeout + 5)  # Allow some overhead

                Write-Host "✓ API timeout handled correctly (duration: $([math]::Round($actualDuration, 1))s)" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ API timeout test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'DNS Provider Health Check System' {

        It 'Should run comprehensive DNS provider health check' {
            $testName = "Comprehensive DNS Health Check"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Prepare credential store for health check
                $credentialStore = @{}
                if ($script:TestCredentials.Cloudflare.CFToken) {
                    $credentialStore['Cloudflare'] = $script:TestCredentials.Cloudflare
                }
                if ($script:TestCredentials.Combell.CombellApiKey) {
                    $credentialStore['Combell'] = $script:TestCredentials.Combell
                }

                # Run health check
                $result = Invoke-DNSProviderHealthCheck -Providers @('Cloudflare', 'Combell') -TestDomain $script:TestConfig.TestDomain -CredentialStore $credentialStore -TimeoutSeconds $script:TestConfig.APITimeout

                $result | Should -Not -BeNullOrEmpty
                $result.Summary | Should -Not -BeNullOrEmpty
                $result.Results | Should -Not -BeNullOrEmpty

                # Verify summary information
                $result.Summary.TotalProviders | Should -BeGreaterThan 0
                $result.Summary.TestDomain | Should -Be $script:TestConfig.TestDomain
                $result.Summary.Timestamp | Should -Not -BeNullOrEmpty

                # Verify individual results
                foreach ($providerResult in $result.Results) {
                    $providerResult.Provider | Should -Not -BeNullOrEmpty
                    $providerResult.Success | Should -BeOfType [bool]
                    $providerResult.Status | Should -Not -BeNullOrEmpty
                    $providerResult.Timestamp | Should -Not -BeNullOrEmpty
                }

                Write-Host "✓ Comprehensive DNS health check completed" -ForegroundColor Green
                Write-Host "  Total Providers: $($result.Summary.TotalProviders)" -ForegroundColor Gray
                Write-Host "  Successful: $($result.Summary.SuccessfulConnections)" -ForegroundColor Gray
                Write-Host "  Failed: $($result.Summary.FailedConnections)" -ForegroundColor Gray
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ DNS health check test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should provide detailed error information for failed providers' {
            $testName = "Detailed Error Information"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test with invalid credentials to generate errors
                $invalidCredentialStore = @{
                    'Cloudflare' = @{ CFToken = 'invalid_token' }
                    'Combell'    = @{ CombellApiKey = 'invalid'; CombellApiSecret = 'invalid' }
                }

                $result = Invoke-DNSProviderHealthCheck -Providers @('Cloudflare', 'Combell') -TestDomain $script:TestConfig.TestDomain -CredentialStore $invalidCredentialStore -TimeoutSeconds $script:TestConfig.APITimeout

                $result | Should -Not -BeNullOrEmpty
                $result.Results | Should -Not -BeNullOrEmpty

                # All results should show failures with detailed error information
                foreach ($providerResult in $result.Results) {
                    $providerResult.Success | Should -Be $false
                    $providerResult.Message | Should -Not -BeNullOrEmpty
                    $providerResult.Details | Should -Not -BeNullOrEmpty
                }

                Write-Host "✓ Detailed error information provided for failed providers" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Detailed error information test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'DNS Provider Configuration Testing' {

        It 'Should validate DNS provider configuration parameters' {
            $testName = "DNS Provider Configuration Validation"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test configuration validation for known providers
                $providers = @('Cloudflare', 'Route53', 'Azure', 'Combell')

                foreach ($providerName in $providers) {
                    # Test with empty credentials
                    $result = Test-DNSProviderConfiguration -ProviderName $providerName -Credentials @{}
                    
                    $result | Should -Be $false  # Should fail validation with empty credentials
                    
                    Write-Host "  ✓ $providerName configuration validation working" -ForegroundColor Gray
                }

                Write-Host "✓ DNS provider configuration validation complete" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ DNS provider configuration test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should provide provider recommendations for domains' {
            $testName = "DNS Provider Recommendations"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Capture output from recommendation function
                $output = Get-DNSProviderRecommendation -Domain $script:TestConfig.TestDomain 2>&1

                # Should generate output (either detected provider or recommendations)
                $output | Should -Not -BeNullOrEmpty

                Write-Host "✓ DNS provider recommendations generated" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ DNS provider recommendations test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'DNS Propagation Testing' {

        It 'Should test DNS propagation checking functionality' {
            $testName = "DNS Propagation Testing"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test DNS propagation checking with known TXT record
                $testRecord = "_acme-challenge.$($script:TestConfig.TestDomain)"
                $testValue = "test-value-$(Get-Random)"

                # This will likely fail (since we're not actually creating the record)
                # but should test the propagation checking logic
                $result = Test-DNSPropagation -DnsName $testRecord -ExpectedValue $testValue -MaxAttempts 2 -DelaySeconds 1

                # Result should be boolean
                $result | Should -BeOfType [bool]
                
                # Most likely will be false since we're not creating real records
                Write-Host "✓ DNS propagation testing logic working (result: $result)" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ DNS propagation test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should test multiple DNS servers for propagation' {
            $testName = "Multiple DNS Server Propagation Testing"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test multiple DNS server propagation checking
                $testRecord = "_acme-challenge.$($script:TestConfig.TestDomain)"
                $testValue = "multi-server-test-$(Get-Random)"
                $dnsServers = @('8.8.8.8', '1.1.1.1', '208.67.222.222')

                # Capture output from multiple server test
                $output = Test-DNSPropagationMultiple -DnsName $testRecord -ExpectedValue $testValue -DnsServers $dnsServers 2>&1

                # Should generate output for each server tested
                $output | Should -Not -BeNullOrEmpty

                Write-Host "✓ Multiple DNS server propagation testing working" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ Multiple DNS server propagation test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'DNS Provider Plugin Integration' {

        It 'Should enumerate available DNS plugins from Posh-ACME' {
            $testName = "DNS Plugin Enumeration"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test DNS plugin enumeration
                $plugins = Get-AvailableDNSPlugin

                $plugins | Should -Not -BeNullOrEmpty
                $plugins.Count | Should -BeGreaterThan 5  # Should have multiple DNS plugins

                # Verify plugin information structure
                foreach ($plugin in $plugins) {
                    $plugin.Name | Should -Not -BeNullOrEmpty
                    $plugin.ChallengeType | Should -Be 'dns-01'
                    $plugin.Description | Should -Not -BeNullOrEmpty
                }

                Write-Host "✓ DNS plugin enumeration complete ($($plugins.Count) plugins found)" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ DNS plugin enumeration test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            }
            finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should provide plugin setup information' {
            $testName = "DNS Plugin Setup Information"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Test plugin setup information retrieval
                $commonPlugins = @('Cloudflare', 'Route53', 'Azure', 'GoogleDomains')

                foreach ($pluginName in $commonPlugins) {
                    $setupUrl = Get-PluginSetupUrl -PluginName $pluginName
                    $description = Get-PluginDescription -PluginName $pluginName

                    # Setup URL should be valid if provided
                    if ($setupUrl) {
                        $setupUrl | Should -Match '^https?://'
                    }

                    # Description should not be empty
                    $description | Should -Not -BeNullOrEmpty

                    Write-Host "  ✓ $pluginName setup info available" -ForegroundColor Gray
                }

                Write-Host "✓ DNS plugin setup information complete" -ForegroundColor Green
                $script:TestResults.Passed++

            }
            catch {
                Write-Host "✗ DNS plugin setup information test failed: $($_.Exception.Message)" -ForegroundColor Red
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
        Write-Host "=== DNS PROVIDER INTEGRATION TEST SUMMARY ===" -ForegroundColor Cyan
        Write-Host "Test Duration: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor Gray
        Write-Host "Passed: $($script:TestResults.Passed)" -ForegroundColor Green
        Write-Host "Failed: $($script:TestResults.Failed)" -ForegroundColor Red
        Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow

        # Cleanup test artifacts
        try {
            if (Test-Path $script:TestConfig.TestLogPath) {
                Remove-Item $script:TestConfig.TestLogPath -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Failed to cleanup test artifacts: $($_.Exception.Message)"
        }

        # Reset environment
        $env:AUTOCERT_TESTING_MODE = $null
        $env:POSHACME_SKIP_UPGRADE_CHECK = $null

        Write-Host "DNS provider integration tests completed." -ForegroundColor Cyan
    }
}
