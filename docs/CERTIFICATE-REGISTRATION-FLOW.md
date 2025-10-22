# Certificate Registration Flow - Complete Path

This document describes the complete end-to-end flow for registering a certificate through the menu-based system.

## Entry Point

**File:** `Main.ps1`
**Line:** 2878-2910 (Main execution loop)

## Flow Diagram

```
User Starts Main.ps1
  ↓
Initialize-ScriptModules (Line 2880)
  ↓
Load Core Modules:
  - Core/Logging.ps1
  - Core/Helpers.ps1
  - Core/Initialize-PoshAcme.ps1
  - Core/ConfigurationManager.ps1
  - Core/CircuitBreaker.ps1
  - Core/DNSProviderDetection.ps1
  - Core/RenewalConfig.ps1
  ↓
Load Function Modules:
  - Functions/Register-Certificate.ps1 ✓ (with circuit breaker)
  - Functions/Install-Certificate.ps1
  - Functions/Get-ExistingCertificates.ps1
  ↓
Show Main Menu (Line 2887)
  ↓
User Selects Option 1 "Register Certificate"
  ↓
Call Register-Certificate() (Line 2891)
  ↓
Register-Certificate Function Executes:
  ├─ Load Circuit Breaker (Lines 14-17)
  ├─ Initialize ACME Server
  ├─ Get PublicSuffixList
  ├─ Get Script Settings
  ├─ Prompt for Domain Name
  ├─ Validate Domain (Test-ValidDomain)
  ├─ Extract Base Domain (Get-BaseDomain)
  ├─ Select Certificate Type
  ├─ Detect DNS Provider (Get-DNSProvider)
  ├─ Select DNS Plugin
  ├─ Create/Verify ACME Account
  ├─ Configure DNS Plugin Parameters
  ├─ Request Certificate:
  │   ├─ Manual Mode:
  │   │   └─ Invoke-WithCircuitBreaker → New-PACertificate
  │   └─ Automated Mode:
  │       └─ Invoke-WithCircuitBreaker → Invoke-WithRetry → New-PACertificate
  ├─ Verify Certificate Obtained
  └─ Prompt for Installation
```

## Critical Functions Required

All these functions are loaded by Main.ps1 during initialization:

### From Core/Helpers.ps1
- `Write-ProgressHelper` - Progress bar display
- `Get-ValidatedInput` - Menu input validation
- `Test-ValidEmail` - Email validation
- `Test-ValidDomain` - Domain validation
- `Get-ScriptSettings` - Load user settings
- `Get-BaseDomain` - Extract base domain from FQDN
- `Invoke-WithRetry` - Retry logic with exponential backoff

### From Core/Initialize-PoshAcme.ps1
- `Initialize-ACMEServer` - Set up ACME server connection

### From Core/DNSProviderDetection.ps1
- `Get-PublicSuffixList` - Load public suffix list for domain parsing
- `Get-DNSProvider` - Auto-detect DNS provider
- `Get-ProviderFromNSRecord` - Match NS records to providers
- `Get-ProviderFromSOA` - Match SOA records to providers

### From Core/CircuitBreaker.ps1
- `Invoke-WithCircuitBreaker` - Circuit breaker pattern for resilience
- `Get-CircuitBreakerStatus` - Check circuit breaker states
- `Reset-CircuitBreaker` - Manual circuit breaker reset

### From Core/ConfigurationManager.ps1
- `Save-ScriptSettings` - Persist user settings

### From Posh-ACME Module
- `Get-PAServer` - Get current ACME server
- `Set-PAServer` - Set ACME server
- `Get-PAAccount` - Get ACME account
- `New-PAAccount` - Create ACME account
- `New-PACertificate` - Request certificate (PROTECTED BY CIRCUIT BREAKER)
- `Get-PACertificate` - Retrieve certificate details
- `Get-PAPlugin` - List available DNS plugins

## Circuit Breaker Integration

The certificate registration flow has **full circuit breaker protection** on critical operations:

### Protected Operations

1. **Manual Certificate Requests** (Line 414-416 in Register-Certificate.ps1)
   ```powershell
   $cert = Invoke-WithCircuitBreaker -OperationName 'CertificateRenewal' -Operation {
       New-PACertificate -Domain $mainDomain -Plugin $plugin -DnsSleep 0 -Verbose
   }
   ```

2. **Automated Certificate Requests** (Lines 558-567 in Register-Certificate.ps1)
   ```powershell
   $cert = Invoke-WithCircuitBreaker -OperationName 'CertificateRenewal' -Operation {
       Invoke-WithRetry -ScriptBlock {
           New-PACertificate -Domain $mainDomain -Plugin $plugin -PluginArgs $pluginArgs -Force -Verbose
       } -MaxAttempts 3 -InitialDelaySeconds 30 -OperationName "Certificate acquisition"
   }
   ```

### Circuit Breaker Configuration

- **Operation Name:** `CertificateRenewal`
- **Failure Threshold:** 2 failures
- **Success Threshold:** 1 success (to recover)
- **Timeout:** 600 seconds (10 minutes)
- **States:** Closed → Open → HalfOpen → Closed

### Benefits

1. **Prevents Cascade Failures** - If Let's Encrypt is down, stops after 2 failures
2. **Automatic Recovery** - Tests with HalfOpen state before full recovery
3. **Combined Resilience** - Circuit breaker + retry logic for maximum reliability
4. **Failure Tracking** - Maintains hourly failure history for analysis

## Error Handling

The registration flow has multiple layers of error handling:

1. **Input Validation** - Domain, email, and plugin parameter validation
2. **Retry Logic** - `Invoke-WithRetry` with exponential backoff
3. **Circuit Breaker** - Prevents repeated failures to ACME servers
4. **Try/Catch Blocks** - Comprehensive error catching throughout
5. **Logging** - All operations logged via `Write-Log`

## Testing the Flow

### Prerequisites
1. Run as Administrator
2. Internet connectivity
3. Valid domain name you control
4. DNS provider credentials (if using automated DNS validation)

### Test Steps

1. Start Main.ps1:
   ```powershell
   .\Main.ps1
   ```

2. Select Option 1 (Register Certificate)

3. Enter domain name: `test.example.com`

4. Select certificate type:
   - Server-specific
   - Wildcard
   - Multi-domain (SAN)

5. DNS Provider Detection runs automatically

6. Select DNS plugin or use Manual

7. Enter DNS credentials (if automated)

8. Certificate request begins:
   - Circuit breaker protects the request
   - Retry logic handles transient failures
   - Progress displayed via Write-ProgressHelper

9. Certificate issued and saved

10. Optional: Install certificate immediately

### Monitoring Circuit Breaker

Check circuit breaker status during operation:
```powershell
# In another PowerShell window
. .\Core\CircuitBreaker.ps1
Get-CircuitBreakerStatus -OperationName 'CertificateRenewal'
```

Output:
```
State           : Closed
FailureCount    : 0
SuccessCount    : 1
LastFailureTime : 1/1/0001 12:00:00 AM
FailureHistory  : {}
```

### Health Check Integration

The system health check (Option 7 in main menu) includes circuit breaker monitoring:
```powershell
Test-SystemHealth
```

Section 9 displays:
```
9. Circuit Breaker Status:
   CertificateRenewal: Closed
   DNSValidation: Closed
   CertificateInstallation: Closed
   EmailNotification: Closed
```

## Common Issues and Solutions

### Issue: Circuit Breaker is Open

**Symptom:** Error message: "Circuit breaker is OPEN for CertificateRenewal"

**Cause:** Too many consecutive failures (2+ within timeout period)

**Solution:**
1. Check Let's Encrypt status: https://letsencrypt.status.io/
2. Verify DNS provider credentials
3. Wait for timeout period (10 minutes) OR
4. Manually reset: `Reset-CircuitBreaker -OperationName 'CertificateRenewal'`

### Issue: Function Not Found

**Symptom:** Error: "The term 'FunctionName' is not recognized"

**Cause:** Module loading failed

**Solution:**
1. Check `$script:InitializationErrors` for loading issues
2. Verify all files in Core/, Functions/ exist
3. Re-run Main.ps1

### Issue: DNS Provider Not Detected

**Symptom:** "DNS provider could not be automatically detected"

**Cause:** NS records don't match known patterns

**Solution:**
1. Select "Manual" or "Other DNS Plugin"
2. Manually select your DNS provider from the list
3. Enter credentials when prompted

## Files Modified for Circuit Breaker Integration

1. ✅ `Functions/Register-Certificate.ps1` - Added circuit breaker wrapper around New-PACertificate
2. ✅ `Core/RenewalOperations.ps1` - Added circuit breaker to renewal operations
3. ✅ `Core/SystemDiagnostics.ps1` - Added circuit breaker status monitoring
4. ✅ `Core/CircuitBreaker.ps1` - Base implementation (already existed)

## Validation Checklist

- [x] Main.ps1 loads Functions/Register-Certificate.ps1
- [x] Register-Certificate has circuit breaker integration
- [x] All helper functions available (Helpers.ps1, DNSProviderDetection.ps1, etc.)
- [x] Circuit breaker loaded before first use
- [x] Invoke-WithCircuitBreaker wraps New-PACertificate calls
- [x] Combined with Invoke-WithRetry for maximum resilience
- [x] Error handling preserves circuit breaker errors
- [x] Logging integrated throughout flow
- [x] System health check monitors circuit breaker status

## Performance Considerations

- **DNS Detection:** ~2-5 seconds
- **ACME Account Creation:** ~3-10 seconds
- **Certificate Request (DNS-01):** ~30-120 seconds
  - Depends on DNS propagation time
  - Manual mode requires user to create TXT records
- **Circuit Breaker Overhead:** < 10ms per operation
- **Retry Logic:** Adds 30-60 seconds per retry attempt

## Related Documentation

- [RELIABILITY.md](./RELIABILITY.md) - Circuit breaker and resilience patterns
- [DNS-PROVIDERS.md](./DNS-PROVIDERS.md) - DNS provider setup guides
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues and solutions
- [USAGE.md](./USAGE.md) - General usage documentation

## Version History

- **2.0.0** (2025-10) - Added circuit breaker integration to certificate registration
- **1.9.0** (2025-07) - DNS provider auto-detection improvements
- **1.8.0** (2025-07) - Email notification system
- **1.7.0** (2025-07) - Initial menu-based system

---

**Last Updated:** 2025-10-22
**Validation Status:** ✅ Complete - Flow verified and documented
