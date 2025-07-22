# AutoCert Integration Tests

This directory contains comprehensive integration tests for the AutoCert certificate management system. These tests validate end-to-end functionality across all major system components.

## Test Categories

### 1. Email Notification Integration Tests

**File**: `EmailNotification.Integration.Tests.ps1`

Tests the complete email notification system including:

- SMTP configuration management and validation
- Email template processing and variable substitution
- Email delivery testing with real SMTP servers
- Multi-channel notification integration
- Certificate lifecycle email integration
- Error handling and retry mechanisms

**Environment Variables**:

- `AUTOCERT_TEST_EMAIL` - Email address for test notifications
- `AUTOCERT_TEST_SMTP_SERVER` - SMTP server for testing
- `AUTOCERT_TEST_SMTP_PORT` - SMTP port (default: 587)
- `AUTOCERT_USE_REAL_SMTP` - Set to 'true' to enable real SMTP testing

### 2. DNS Provider Integration Tests

**File**: `DNSProvider.Integration.Tests.ps1`

Tests DNS provider functionality including:

- DNS provider detection from domain NS records
- API connectivity testing for multiple providers
- Credential validation and error handling
- DNS propagation checking and monitoring
- Provider health check system
- Plugin integration with Posh-ACME

**Environment Variables**:

- `AUTOCERT_TEST_DOMAIN` - Domain for testing (must be controlled by you)
- `AUTOCERT_TEST_CLOUDFLARE_TOKEN` - Cloudflare API token
- `AUTOCERT_TEST_COMBELL_API_KEY` - Combell API key
- `AUTOCERT_TEST_COMBELL_API_SECRET` - Combell API secret
- `AUTOCERT_TEST_AWS_ACCESS_KEY` - AWS access key
- `AUTOCERT_TEST_AWS_SECRET_KEY` - AWS secret key
- `AUTOCERT_SKIP_REAL_API_TESTS` - Set to 'true' to skip real API tests

### 3. Certificate Lifecycle Integration Tests

**File**: `CertificateLifecycle.Integration.Tests.ps1`

Tests complete certificate lifecycle including:

- Certificate registration and validation
- Certificate installation to Windows certificate store
- Certificate export to multiple formats (PFX, PEM)
- Certificate information retrieval and monitoring
- Certificate renewal workflow
- Certificate backup and recovery
- Certificate removal and cleanup

**Environment Variables**:

- `AUTOCERT_TEST_DOMAIN` - Domain for certificate testing
- `AUTOCERT_TEST_DNS_PROVIDER` - DNS provider for ACME challenges
- `AUTOCERT_USE_STAGING` - Set to 'false' to use production Let's Encrypt
- `AUTOCERT_SKIP_INSTALLATION` - Set to 'true' to skip certificate installation
- `AUTOCERT_SKIP_CLEANUP` - Set to 'true' to skip certificate cleanup

### 4. Renewal Automation Integration Tests

**File**: `RenewalAutomation.Integration.Tests.ps1`

Tests automated renewal system including:

- Renewal configuration management
- Scheduled task creation and management
- Renewal decision logic and prioritization
- Health monitoring and alerting
- Notification systems for renewal events
- Error handling and recovery mechanisms
- System stability during failures

**Environment Variables**:

- `AUTOCERT_TEST_DOMAIN` - Domain for renewal testing
- `AUTOCERT_USE_STAGING` - Set to 'false' to use production Let's Encrypt
- `AUTOCERT_SKIP_SCHEDULED_TASKS` - Set to 'true' to skip scheduled task tests
- `AUTOCERT_ENABLE_REAL_NOTIFICATIONS` - Set to 'true' to enable real notifications

## Running Integration Tests

### Individual Test Categories

```powershell
# Run email notification tests
.\RunTests.ps1 -TestType EmailNotification

# Run DNS provider tests
.\RunTests.ps1 -TestType DNSProvider

# Run certificate lifecycle tests
.\RunTests.ps1 -TestType CertificateLifecycle

# Run renewal automation tests
.\RunTests.ps1 -TestType RenewalAutomation
```

### All Integration Tests

```powershell
# Run all integration tests
.\RunTests.ps1 -TestType Integration

# Run all tests with detailed output
.\RunTests.ps1 -TestType All -GenerateReport
```

### With Environment Configuration

```powershell
# Set up environment variables
$env:AUTOCERT_TEST_DOMAIN = "test.yourdomain.com"
$env:AUTOCERT_TEST_EMAIL = "admin@yourdomain.com"
$env:AUTOCERT_TEST_CLOUDFLARE_TOKEN = "your_cloudflare_token"
$env:AUTOCERT_USE_STAGING = "true"

# Run tests
.\RunTests.ps1 -TestType Integration
```

## Test Environment Setup

### Prerequisites

1. **PowerShell 5.1 or later**
2. **Pester 5.0 or later**
3. **Administrative privileges** (for some certificate store operations)
4. **Valid DNS provider credentials** (for real API testing)
5. **Test domain you control** (for end-to-end testing)

### Safety Considerations

- Tests use Let's Encrypt **staging environment** by default
- Tests create temporary files in `$env:TEMP`
- Tests may create/remove Windows certificate store entries
- Tests may create/remove scheduled tasks (with test prefix)
- Real API tests require valid credentials and may consume API quotas

### Staging vs Production

**Staging (Default)**:

- Uses Let's Encrypt staging environment
- Certificates are not trusted by browsers
- Higher rate limits for testing
- Safe for repeated testing

**Production**:

- Uses Let's Encrypt production environment
- Creates real, trusted certificates
- Subject to rate limits (50 certificates per domain per week)
- Should only be used for final validation

## Test Configuration

### Required for Full Testing

```powershell
# Domain you control (required for certificate tests)
$env:AUTOCERT_TEST_DOMAIN = "test.yourdomain.com"

# Email configuration (for notification tests)
$env:AUTOCERT_TEST_EMAIL = "admin@yourdomain.com"
$env:AUTOCERT_TEST_SMTP_SERVER = "smtp.gmail.com"
$env:AUTOCERT_USE_REAL_SMTP = "true"

# DNS provider credentials (for API tests)
$env:AUTOCERT_TEST_CLOUDFLARE_TOKEN = "your_token_here"
$env:AUTOCERT_TEST_COMBELL_API_KEY = "your_api_key"
$env:AUTOCERT_TEST_COMBELL_API_SECRET = "your_api_secret"

# Test behavior
$env:AUTOCERT_USE_STAGING = "true"
$env:AUTOCERT_SKIP_REAL_API_TESTS = "false"
$env:AUTOCERT_ENABLE_REAL_NOTIFICATIONS = "true"
```

### Minimal Configuration (Safe Testing)

```powershell
# Skip potentially risky operations
$env:AUTOCERT_SKIP_REAL_API_TESTS = "true"
$env:AUTOCERT_SKIP_INSTALLATION = "true"
$env:AUTOCERT_SKIP_SCHEDULED_TASKS = "true"
$env:AUTOCERT_SKIP_CLEANUP = "true"
$env:AUTOCERT_USE_REAL_SMTP = "false"
```

## Test Output and Reporting

### Standard Output

Tests provide detailed console output including:

- Test progress and status
- Individual test results
- Performance metrics
- Error details and troubleshooting information

### Test Reports

Use `-GenerateReport` to create detailed HTML reports:

```powershell
.\RunTests.ps1 -TestType Integration -GenerateReport -OutputFile "IntegrationTestReport.html"
```

### Logging

All tests create detailed logs in:

- `$env:TEMP\AutoCert_*Test_*.log`

## Troubleshooting

### Common Issues

1. **Permission Errors**: Run as administrator for certificate store operations
2. **Network Timeouts**: Check firewall and DNS settings
3. **API Rate Limits**: Use staging environment and spread out tests
4. **DNS Propagation**: Allow time for DNS changes to propagate
5. **Certificate Store**: Ensure certificate store is accessible

### Debug Mode

Enable verbose output for troubleshooting:

```powershell
.\RunTests.ps1 -TestType EmailNotification -Verbose
```

### Cleanup

If tests are interrupted, you may need to manually clean up:

- Temporary files in `$env:TEMP\AutoCert_*`
- Test certificates in Windows certificate store
- Test scheduled tasks (prefix: `AutoCert-Test-`)
- ACME orders in staging environment

## Contributing

When adding new integration tests:

1. Follow the existing test structure and naming conventions
2. Include proper environment variable support
3. Provide both safe and full testing modes
4. Add comprehensive error handling
5. Include cleanup in `AfterAll` blocks
6. Update this README with new test information

## Security Notes

- Never commit real API credentials to version control
- Use environment variables for sensitive configuration
- Test with staging environments when possible
- Limit API calls to avoid quota exhaustion
- Clean up test artifacts to avoid information disclosure

For more information, see the main [AutoCert documentation](../../../README.md).
