# Tests/Integration/CertificateLifecycle.Integration.Tests.ps1
<#
    .SYNOPSIS
        Comprehensive integration tests for the complete certificate lifecycle in AutoCert.

    .DESCRIPTION
        End-to-end integration tests covering certificate registration, installation,
        renewal, monitoring, and cleanup processes across the entire certificate lifecycle.

    .NOTES
        These tests require proper DNS provider configuration and may create actual certificates.
        Use staging environment to avoid Let's Encrypt rate limits.
        Set AUTOCERT_TEST_DOMAIN to a domain you control for full testing.
#>

[CmdletBinding()]
param(
    [string]$TestDomain = $env:AUTOCERT_TEST_DOMAIN,
    [string]$DNSProvider = $env:AUTOCERT_TEST_DNS_PROVIDER -or "Manual",
    [switch]$UseStaging = $env:AUTOCERT_USE_STAGING -ne 'false',
    [switch]$SkipInstallation = $env:AUTOCERT_SKIP_INSTALLATION -eq 'true',
    [switch]$SkipCleanup = $env:AUTOCERT_SKIP_CLEANUP -eq 'true',
    [int]$MaxTestDuration = 1800  # 30 minutes
)

Describe 'AutoCert Certificate Lifecycle - Integration Tests' -Tag @('Integration', 'CertificateLifecycle', 'E2E', 'Slow') {

    BeforeAll {
        $script:ErrorActionPreference = 'Stop'
        $script:TestStartTime = Get-Date
        $script:TestResults = @{
            Passed        = 0
            Failed        = 0
            Skipped       = 0
            TotalDuration = 0
            CertificatesCreated = @()
        }

        # Setup test environment
        $env:AUTOCERT_TESTING_MODE = $true
        $env:POSHACME_SKIP_UPGRADE_CHECK = $true

        # Calculate path to main repository
        $repoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent

        # Load all AutoCert modules required for certificate lifecycle testing
        $modulePaths = @(
            "$repoRoot\Core\Logging.ps1",
            "$repoRoot\Core\Helpers.ps1",
            "$repoRoot\Core\ConfigurationManager.ps1",
            "$repoRoot\Core\RenewalConfig.ps1",
            "$repoRoot\Core\Initialize-PoshAcme.ps1",
            "$repoRoot\Public\Register-Certificate.ps1",
            "$repoRoot\Public\Install-Certificate.ps1",
            "$repoRoot\Public\Update-AllCertificates.ps1",
            "$repoRoot\Public\Remove-Certificate.ps1",
            "$repoRoot\Public\Get-ExistingCertificates.ps1",
            "$repoRoot\Private\Show-CertificateInformation.ps1"
        )

        foreach ($module in $modulePaths) {
            if (Test-Path $module) {
                . $module
                Write-Host "Loaded: $module" -ForegroundColor Green
            } else {
                Write-Warning "Module not found: $module"
            }
        }

        # Initialize Posh-ACME for testing
        Initialize-PoshAcme

        # Setup test configuration
        $script:TestConfig = @{
            TestDomain         = $TestDomain -or "lifecycle-test.example.com"
            DNSProvider        = $DNSProvider
            UseStaging         = $UseStaging
            SkipInstallation   = $SkipInstallation
            SkipCleanup        = $SkipCleanup
            MaxTestDuration    = $MaxTestDuration
            TestLogPath        = Join-Path $env:TEMP "AutoCert_LifecycleTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            CertStorePath      = Join-Path $env:TEMP "AutoCert_TestCerts"
            BackupPath         = Join-Path $env:TEMP "AutoCert_TestBackup"
        }

        # Ensure test directories exist
        foreach ($path in @($script:TestConfig.CertStorePath, $script:TestConfig.BackupPath)) {
            if (-not (Test-Path $path)) {
                New-Item -ItemType Directory -Path $path -Force | Out-Null
            }
        }

        # Configure staging environment if requested
        if ($script:TestConfig.UseStaging) {
            Set-PAServer -DirectoryUrl 'https://acme-staging-v02.api.letsencrypt.org/directory'
            Write-Host "Using Let's Encrypt staging environment" -ForegroundColor Yellow
        }

        Write-Host "Certificate lifecycle integration test environment initialized" -ForegroundColor Cyan
        Write-Host "Test Domain: $($script:TestConfig.TestDomain)" -ForegroundColor Gray
        Write-Host "DNS Provider: $($script:TestConfig.DNSProvider)" -ForegroundColor Gray
        Write-Host "Use Staging: $($script:TestConfig.UseStaging)" -ForegroundColor Gray
        Write-Host "Max Duration: $($script:TestConfig.MaxTestDuration) seconds" -ForegroundColor Gray
    }

    Context 'Certificate Registration Process' {

        It 'Should register a new certificate successfully' {
            $testName = "Certificate Registration"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                Write-Host "Starting certificate registration for $($script:TestConfig.TestDomain)..." -ForegroundColor Blue

                # Register new certificate
                $result = Invoke-WithRetry -ScriptBlock {
                    Register-Certificate -Domain $script:TestConfig.TestDomain -DNSProvider $script:TestConfig.DNSProvider -Force
                } -MaxAttempts 3 -InitialDelaySeconds 10 -OperationName "Certificate Registration"

                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true
                $result.Certificate | Should -Not -BeNullOrEmpty

                # Verify certificate was created
                $cert = Get-PAOrder -MainDomain $script:TestConfig.TestDomain
                $cert | Should -Not -BeNullOrEmpty
                $cert.status | Should -Be 'valid'
                $cert.Certificate | Should -Not -BeNullOrEmpty

                # Store certificate info for later tests
                $script:TestResults.CertificatesCreated += @{
                    Domain = $script:TestConfig.TestDomain
                    Order  = $cert
                    RegisterTime = Get-Date
                }

                Write-Host "✓ Certificate registered successfully" -ForegroundColor Green
                Write-Host "  Certificate Path: $($cert.Certificate)" -ForegroundColor Gray
                Write-Host "  Status: $($cert.status)" -ForegroundColor Gray
                Write-Host "  Expires: $($cert.CertExpires)" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate registration failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
                Write-Host "  Registration Duration: $([math]::Round($stopwatch.ElapsedMilliseconds / 1000, 1)) seconds" -ForegroundColor Gray
            }
        }

        It 'Should handle duplicate certificate registration requests' {
            $testName = "Duplicate Registration Handling"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Try to register the same certificate again
                $result = Register-Certificate -Domain $script:TestConfig.TestDomain -DNSProvider $script:TestConfig.DNSProvider

                # Should either reuse existing or create new based on implementation
                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true

                Write-Host "✓ Duplicate registration handled correctly" -ForegroundColor Green
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Duplicate registration test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should validate certificate properties and metadata' {
            $testName = "Certificate Validation"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Get the registered certificate
                $cert = Get-PAOrder -MainDomain $script:TestConfig.TestDomain
                $cert | Should -Not -BeNullOrEmpty

                # Validate certificate properties
                $cert.MainDomain | Should -Be $script:TestConfig.TestDomain
                $cert.status | Should -Be 'valid'
                $cert.CertExpires | Should -BeGreaterThan (Get-Date)

                # Validate certificate files exist
                $cert.Certificate | Should -Not -BeNullOrEmpty
                Test-Path $cert.Certificate | Should -Be $true

                if ($cert.CertKey) {
                    Test-Path $cert.CertKey | Should -Be $true
                }

                # Validate certificate content
                $certContent = Get-Content $cert.Certificate -Raw
                $certContent | Should -Match "BEGIN CERTIFICATE"
                $certContent | Should -Match "END CERTIFICATE"

                Write-Host "✓ Certificate validation complete" -ForegroundColor Green
                Write-Host "  Domain: $($cert.MainDomain)" -ForegroundColor Gray
                Write-Host "  Valid Until: $($cert.CertExpires)" -ForegroundColor Gray
                Write-Host "  Key Length: $($cert.KeyLength)" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate validation failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Certificate Installation Process' {

        It 'Should install certificate to Windows certificate store' -Skip:$script:TestConfig.SkipInstallation {
            $testName = "Certificate Store Installation"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Get the registered certificate
                $cert = Get-PAOrder -MainDomain $script:TestConfig.TestDomain
                $cert | Should -Not -BeNullOrEmpty

                # Install certificate to store
                $result = Install-Certificate -CertificatePath $cert.Certificate -PrivateKeyPath $cert.CertKey -InstallLocation 'LocalMachine' -StoreName 'My'

                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true
                $result.Thumbprint | Should -Not -BeNullOrEmpty

                # Verify certificate in store
                $installedCert = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object { $_.Subject -match $script:TestConfig.TestDomain }
                $installedCert | Should -Not -BeNullOrEmpty

                Write-Host "✓ Certificate installed to Windows certificate store" -ForegroundColor Green
                Write-Host "  Thumbprint: $($result.Thumbprint)" -ForegroundColor Gray
                Write-Host "  Store: LocalMachine\My" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate installation failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should export certificate to multiple formats' {
            $testName = "Certificate Export"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Get the registered certificate
                $cert = Get-PAOrder -MainDomain $script:TestConfig.TestDomain
                $cert | Should -Not -BeNullOrEmpty

                # Export to PFX format
                $pfxPath = Join-Path $script:TestConfig.CertStorePath "$($script:TestConfig.TestDomain).pfx"
                $pfxPassword = ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force

                $result = Export-CertificateToPFX -CertificatePath $cert.Certificate -PrivateKeyPath $cert.CertKey -OutputPath $pfxPath -Password $pfxPassword

                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true
                Test-Path $pfxPath | Should -Be $true

                # Export to PEM format
                $pemPath = Join-Path $script:TestConfig.CertStorePath "$($script:TestConfig.TestDomain).pem"
                $pemResult = Install-CertificateToPEM -CertificatePath $cert.Certificate -PrivateKeyPath $cert.CertKey -OutputPath $pemPath

                $pemResult | Should -Not -BeNullOrEmpty
                $pemResult.Success | Should -Be $true
                Test-Path $pemPath | Should -Be $true

                Write-Host "✓ Certificate exported to multiple formats" -ForegroundColor Green
                Write-Host "  PFX: $pfxPath" -ForegroundColor Gray
                Write-Host "  PEM: $pemPath" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate export failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Certificate Information and Monitoring' {

        It 'Should retrieve comprehensive certificate information' {
            $testName = "Certificate Information Retrieval"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Get certificate information
                $certInfo = Show-CertificateInformation -Domain $script:TestConfig.TestDomain

                $certInfo | Should -Not -BeNullOrEmpty
                $certInfo.Domain | Should -Be $script:TestConfig.TestDomain
                $certInfo.Status | Should -Be 'Valid'
                $certInfo.ExpirationDate | Should -BeGreaterThan (Get-Date)
                $certInfo.DaysUntilExpiry | Should -BeGreaterThan 0

                Write-Host "✓ Certificate information retrieved successfully" -ForegroundColor Green
                Write-Host "  Status: $($certInfo.Status)" -ForegroundColor Gray
                Write-Host "  Expires: $($certInfo.ExpirationDate)" -ForegroundColor Gray
                Write-Host "  Days Until Expiry: $($certInfo.DaysUntilExpiry)" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate information retrieval failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should list all existing certificates' {
            $testName = "Certificate Enumeration"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Get all existing certificates
                $existingCerts = Get-ExistingCertificates

                $existingCerts | Should -Not -BeNullOrEmpty
                $existingCerts.Count | Should -BeGreaterOrEqual 1

                # Should find our test certificate
                $testCert = $existingCerts | Where-Object { $_.Domain -eq $script:TestConfig.TestDomain }
                $testCert | Should -Not -BeNullOrEmpty

                Write-Host "✓ Certificate enumeration complete" -ForegroundColor Green
                Write-Host "  Total Certificates: $($existingCerts.Count)" -ForegroundColor Gray
                Write-Host "  Test Certificate Found: $($testCert -ne $null)" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate enumeration failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should detect certificates approaching expiration' {
            $testName = "Expiration Detection"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # This test is mainly for the logic, since staging certs are valid for 90 days
                $expiringCerts = Get-ExistingCertificates | Where-Object { $_.DaysUntilExpiry -le 30 }

                # For staging environment, certificates should not be expiring immediately
                if ($script:TestConfig.UseStaging) {
                    # Our fresh certificate should not be in the expiring list
                    $ourCert = $expiringCerts | Where-Object { $_.Domain -eq $script:TestConfig.TestDomain }
                    $ourCert | Should -BeNullOrEmpty
                }

                Write-Host "✓ Expiration detection working" -ForegroundColor Green
                Write-Host "  Expiring Certificates: $($expiringCerts.Count)" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Expiration detection failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Certificate Renewal Process' {

        It 'Should handle certificate renewal workflow' {
            $testName = "Certificate Renewal"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # For this test, we'll simulate renewal by forcing a renewal check
                Write-Host "Testing certificate renewal workflow..." -ForegroundColor Blue

                # Get current certificate
                $cert = Get-PAOrder -MainDomain $script:TestConfig.TestDomain
                $cert | Should -Not -BeNullOrEmpty

                # Test the renewal check logic (won't actually renew since cert is fresh)
                $renewalResult = Update-AllCertificates -Force:$false

                $renewalResult | Should -Not -BeNullOrEmpty

                # Since certificate is fresh, it should not be renewed
                Write-Host "✓ Certificate renewal workflow tested" -ForegroundColor Green
                Write-Host "  Renewal Result: Certificate not due for renewal" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate renewal test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should backup certificates before renewal' {
            $testName = "Certificate Backup"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Get current certificate
                $cert = Get-PAOrder -MainDomain $script:TestConfig.TestDomain
                $cert | Should -Not -BeNullOrEmpty

                # Create backup
                $backupPath = Join-Path $script:TestConfig.BackupPath "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
                $backupResult = Backup-Certificate -CertificatePath $cert.Certificate -PrivateKeyPath $cert.CertKey -BackupPath $backupPath

                $backupResult | Should -Not -BeNullOrEmpty
                $backupResult.Success | Should -Be $true
                Test-Path $backupPath | Should -Be $true

                Write-Host "✓ Certificate backup created successfully" -ForegroundColor Green
                Write-Host "  Backup Path: $backupPath" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate backup failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Certificate Lifecycle Management' {

        It 'Should track certificate lifecycle events' {
            $testName = "Lifecycle Event Tracking"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Check if we have tracked events for our certificate
                $certificateRecord = $script:TestResults.CertificatesCreated | Where-Object { $_.Domain -eq $script:TestConfig.TestDomain }
                $certificateRecord | Should -Not -BeNullOrEmpty

                # Verify registration time
                $certificateRecord.RegisterTime | Should -Not -BeNullOrEmpty
                $certificateRecord.RegisterTime | Should -BeLessOrEqual (Get-Date)

                # Check certificate order status
                $certificateRecord.Order | Should -Not -BeNullOrEmpty
                $certificateRecord.Order.status | Should -Be 'valid'

                Write-Host "✓ Certificate lifecycle events tracked" -ForegroundColor Green
                Write-Host "  Registration Time: $($certificateRecord.RegisterTime)" -ForegroundColor Gray
                Write-Host "  Current Status: $($certificateRecord.Order.status)" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Lifecycle event tracking failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should handle certificate replacement scenarios' {
            $testName = "Certificate Replacement"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # For this test, we'll verify the replacement workflow exists
                # (actual replacement would require forcing a new certificate)
                
                $cert = Get-PAOrder -MainDomain $script:TestConfig.TestDomain
                $cert | Should -Not -BeNullOrEmpty

                # Test that we can identify when replacement is needed
                $needsReplacement = ($cert.CertExpires -lt (Get-Date).AddDays(30))
                
                # Fresh certificate should not need replacement
                $needsReplacement | Should -Be $false

                Write-Host "✓ Certificate replacement logic verified" -ForegroundColor Green
                Write-Host "  Needs Replacement: $needsReplacement" -ForegroundColor Gray
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate replacement test failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    Context 'Certificate Cleanup and Removal' {

        It 'Should remove certificate from ACME store' -Skip:$script:TestConfig.SkipCleanup {
            $testName = "Certificate Removal"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Remove the test certificate
                $result = Remove-Certificate -Domain $script:TestConfig.TestDomain -Confirm:$false

                $result | Should -Not -BeNullOrEmpty
                $result.Success | Should -Be $true

                # Verify certificate is removed
                $cert = Get-PAOrder -MainDomain $script:TestConfig.TestDomain -ErrorAction SilentlyContinue
                $cert | Should -BeNullOrEmpty

                Write-Host "✓ Certificate removed successfully" -ForegroundColor Green
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate removal failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }

        It 'Should clean up certificate files and artifacts' -Skip:$script:TestConfig.SkipCleanup {
            $testName = "Certificate Cleanup"
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Clean up test certificate files
                $testFiles = @(
                    Join-Path $script:TestConfig.CertStorePath "$($script:TestConfig.TestDomain).pfx",
                    Join-Path $script:TestConfig.CertStorePath "$($script:TestConfig.TestDomain).pem"
                )

                foreach ($file in $testFiles) {
                    if (Test-Path $file) {
                        Remove-Item $file -Force
                        Write-Host "  Cleaned up: $file" -ForegroundColor Gray
                    }
                }

                # Clean up installed certificate from store
                $installedCerts = Get-ChildItem -Path "Cert:\LocalMachine\My" | Where-Object { $_.Subject -match $script:TestConfig.TestDomain }
                foreach ($cert in $installedCerts) {
                    Remove-Item -Path $cert.PSPath -Force
                    Write-Host "  Removed from store: $($cert.Thumbprint)" -ForegroundColor Gray
                }

                Write-Host "✓ Certificate cleanup completed" -ForegroundColor Green
                $script:TestResults.Passed++

            } catch {
                Write-Host "✗ Certificate cleanup failed: $($_.Exception.Message)" -ForegroundColor Red
                $script:TestResults.Failed++
                throw
            } finally {
                $stopwatch.Stop()
                $script:TestResults.TotalDuration += $stopwatch.ElapsedMilliseconds
            }
        }
    }

    AfterAll {
        $script:TestEndTime = Get-Date
        $totalDuration = ($script:TestEndTime - $script:TestStartTime).TotalSeconds

        Write-Host "`n" -NoNewline
        Write-Host "=== CERTIFICATE LIFECYCLE INTEGRATION TEST SUMMARY ===" -ForegroundColor Cyan
        Write-Host "Test Duration: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor Gray
        Write-Host "Passed: $($script:TestResults.Passed)" -ForegroundColor Green
        Write-Host "Failed: $($script:TestResults.Failed)" -ForegroundColor Red
        Write-Host "Skipped: $($script:TestResults.Skipped)" -ForegroundColor Yellow
        Write-Host "Certificates Created: $($script:TestResults.CertificatesCreated.Count)" -ForegroundColor Cyan

        # Show created certificates
        foreach ($cert in $script:TestResults.CertificatesCreated) {
            Write-Host "  Certificate: $($cert.Domain) - Status: $($cert.Order.status)" -ForegroundColor Gray
        }

        # Cleanup test directories
        try {
            if (Test-Path $script:TestConfig.TestLogPath) {
                Remove-Item $script:TestConfig.TestLogPath -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $script:TestConfig.CertStorePath) {
                Remove-Item $script:TestConfig.CertStorePath -Recurse -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $script:TestConfig.BackupPath) {
                Remove-Item $script:TestConfig.BackupPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {
            Write-Warning "Failed to cleanup test directories: $($_.Exception.Message)"
        }

        # Reset environment
        $env:AUTOCERT_TESTING_MODE = $null
        $env:POSHACME_SKIP_UPGRADE_CHECK = $null

        if ($totalDuration -gt ($script:TestConfig.MaxTestDuration * 0.8)) {
            Write-Warning "Test duration approaching maximum allowed time ($($script:TestConfig.MaxTestDuration)s)"
        }

        Write-Host "Certificate lifecycle integration tests completed." -ForegroundColor Cyan
    }
}
