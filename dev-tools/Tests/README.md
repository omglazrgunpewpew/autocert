# AutoCert Testing System

## Overview

The AutoCert testing system provides comprehensive test coverage for the certificate management functionality, including unit tests, integration tests, and resilience testing.

## Test Types

### 1. Unit Tests (`Autocert.Tests.ps1`)
Basic unit tests that verify core functions are properly loaded and defined.

**Coverage:**
- Function existence validation
- Basic parameter validation
- Module loading verification

**Execution Time:** ~30 seconds

### 2. Integration Tests (`Autocert.Integration.Tests.ps1`)
End-to-end tests that cover complete certificate lifecycle scenarios.

**Coverage:**
- Certificate registration workflows
- DNS validation processes
- Certificate renewal automation
- Installation and certificate store operations
- Error recovery mechanisms
- Circuit breaker functionality
- Configuration validation
- Health monitoring

**Requirements:**
- Network connectivity
- Administrator privileges (for certificate store operations)
- Valid DNS provider credentials (for full testing)

**Execution Time:** ~10-30 minutes (depending on network and DNS response times)

### 3. Resilience Tests (`Autocert.Resilience.Tests.ps1`, `Autocert.Complete.Tests.ps1`)
Tests focused on error handling, recovery mechanisms, and system resilience.

**Coverage:**
- Transient error handling
- Retry logic validation
- Circuit breaker patterns
- Failure recovery scenarios
- Performance under load
- Timeout handling

**Execution Time:** ~5-15 minutes

## Quick Start

### Basic Test Execution

```powershell
# Run all tests
.\RunTests.ps1

# Run specific test type
.\RunTests.ps1 -TestType Unit
.\RunTests.ps1 -TestType Integration
.\RunTests.ps1 -TestType Resilience

# Run with detailed reporting
.\RunTests.ps1 -GenerateReport -OutputFormat NUnitXml -OutputFile "TestResults.xml"
```

### Advanced Options

```powershell
# Continue testing even if some tests fail
.\RunTests.ps1 -ContinueOnFailure

# Generate HTML report
.\RunTests.ps1 -GenerateReport

# Run integration tests with custom domain
.\Autocert.Integration.Tests.ps1 -TestDomain "test.example.com" -DNSProvider "Manual"
```

## Test Configuration

### Environment Variables

Set these variables to control test behavior:

```powershell
# Enable testing mode (prevents module updates)
$env:AUTOCERT_TESTING_MODE = $true

# Skip Posh-ACME upgrade checks
$env:POSHACME_SKIP_UPGRADE_CHECK = $true

# Custom test log location
$env:AUTOCERT_TEST_LOG_PATH = "C:\Logs\AutoCert\Tests"
```

### Integration Test Parameters

The integration tests support several parameters for customization:

- `TestDomain`: Domain to use for testing (default: "test.example.com")
- `DNSProvider`: DNS provider to test with (default: "Manual")
- `UseStaging`: Use Let's Encrypt staging environment (default: true)
- `SkipCleanup`: Skip cleanup after tests (default: false)

### Prerequisites

#### For Unit Tests
- PowerShell 5.1 or later
- Pester 5.0 or later

#### For Integration Tests
- Administrator privileges
- Network connectivity
- Valid DNS provider credentials (for live testing)
- Access to Let's Encrypt staging environment

#### For Resilience Tests
- All integration test prerequisites
- Ability to simulate network failures
- Performance monitoring tools (optional)

## Test Execution Examples

### Developer Workflow

```powershell
# Quick unit test before commit
.\RunTests.ps1 -TestType Unit

# Full validation before release
.\RunTests.ps1 -TestType All -GenerateReport
```

### CI/CD Pipeline

```powershell
# Automated testing with XML output
.\RunTests.ps1 -TestType All -OutputFormat NUnitXml -OutputFile "TestResults.xml" -ContinueOnFailure

# Check exit code for pass/fail
if ($LASTEXITCODE -eq 0) {
    Write-Host "All tests passed" -ForegroundColor Green
} else {
    Write-Host "Some tests failed" -ForegroundColor Red
    exit 1
}
```

### Manual Testing

```powershell
# Test specific scenarios with custom parameters
.\Autocert.Integration.Tests.ps1 -TestDomain "manual-test.yourdomain.com" -DNSProvider "Cloudflare" -UseStaging:$false
```

## Output and Reporting

### Console Output

The test runner provides real-time console output with:
- Progress indicators
- Test execution status
- Detailed error messages
- Performance metrics
- Summary statistics

### HTML Reports

When `-GenerateReport` is specified, an HTML report is generated with:
- Test suite summaries
- Pass/fail statistics
- Execution times
- Error details
- Success rate analysis

### XML Output

For CI/CD integration, tests can output results in NUnit XML format:
- Compatible with most CI/CD systems
- Includes detailed test metadata
- Supports test categorization
- Provides timing information

## Troubleshooting

### Common Issues

#### 1. Permission Errors
```
Error: Access denied to certificate store
```
**Solution:** Run tests as Administrator

#### 2. Network Timeouts
```
Error: DNS validation timeout
```
**Solutions:**
- Check network connectivity
- Verify DNS provider credentials
- Increase timeout values in test configuration

#### 3. Module Loading Issues
```
Error: Cannot find module 'Pester'
```
**Solution:** Install required modules:
```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Force -SkipPublisherCheck
```

#### 4. Let's Encrypt Rate Limiting
```
Error: Too many requests
```
**Solutions:**
- Use staging environment (`-UseStaging`)
- Implement test delays
- Use different test domains

### Debug Mode

Enable verbose logging for troubleshooting:

```powershell
# Enable verbose output
.\RunTests.ps1 -Verbose

# Enable debug logging in integration tests
$env:AUTOCERT_DEBUG_MODE = $true
.\RunTests.ps1 -TestType Integration
```

### Log Analysis

Test logs are stored in:
- Console output (real-time)
- Test-specific log files
- Windows Event Log (for integration tests)
- HTML reports (when enabled)

## Best Practices

### Test Development

1. **Isolation**: Each test should be independent and not rely on other tests
2. **Cleanup**: Always clean up test resources to avoid side effects
3. **Mocking**: Use mocks for external dependencies where possible
4. **Timeouts**: Set appropriate timeouts for network operations
5. **Error Handling**: Test both success and failure scenarios

### Test Execution

1. **Environment**: Use staging environments for integration tests
2. **Credentials**: Use test-specific credentials, not production
3. **Scheduling**: Don't run tests during production maintenance windows
4. **Monitoring**: Monitor test execution for performance issues
5. **Documentation**: Keep test results and logs for analysis

### CI/CD Integration

1. **Parallel Execution**: Run different test types in parallel when possible
2. **Artifact Storage**: Store test reports and logs as build artifacts
3. **Failure Handling**: Configure appropriate failure thresholds
4. **Notifications**: Set up alerts for test failures
5. **Trending**: Track test performance over time

## Performance Expectations

### Typical Execution Times

| Test Type | Duration | Network Calls | Disk I/O |
|-----------|----------|---------------|----------|
| Unit | 30 seconds | None | Minimal |
| Integration | 10-30 minutes | Many | Moderate |
| Resilience | 5-15 minutes | Simulated | Low |

### Resource Usage

- **Memory**: 50-200 MB during execution
- **CPU**: Low to moderate (depends on encryption operations)
- **Network**: Variable (integration tests require internet access)
- **Disk**: Minimal (temporary test files only)

## Extending the Test Suite

### Adding New Tests

1. Create test file in `Tests/` directory
2. Follow existing naming conventions
3. Use Pester framework
4. Include appropriate tags and metadata
5. Update test runner configuration

### Test Categories

Use these tags for test categorization:
- `Unit` - Basic unit tests
- `Integration` - End-to-end tests
- `E2E` - Full workflow tests
- `Resilience` - Error handling tests
- `Performance` - Performance tests
- `Security` - Security validation tests

### Example Test Structure

```powershell
Describe 'Feature Name Tests' -Tag @('Unit', 'FeatureName') {
    BeforeAll {
        # Setup code
    }
    
    Context 'Specific Scenario' {
        It 'Should perform expected behavior' {
            # Test implementation
        }
    }
    
    AfterAll {
        # Cleanup code
    }
}
```

## Support and Maintenance

### Regular Maintenance

- Review and update test data regularly
- Monitor test execution times for performance regression
- Update test environments to match production
- Validate test credentials and permissions
- Archive old test results and logs

### Version Compatibility

The test suite is designed to work with:
- PowerShell 5.1+
- Pester 5.0+
- Windows Server 2016+
- Let's Encrypt v2 API

### Getting Help

For issues with the test suite:
1. Check this documentation
2. Review test logs and error messages
3. Verify prerequisites are met
4. Test in isolation to identify specific issues
5. Consult AutoCert troubleshooting documentation
