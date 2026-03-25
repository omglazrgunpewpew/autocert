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
  │   ├─ 1) Server-specific certificate
  │   ├─ 2) Wildcard certificate (*.domain)
  │   └─ 3) Multi-domain certificate (SAN)
  ├─ **NEW: Select Challenge Type** (Lines 113-146)
  │   ├─ 1) DNS-01 Challenge (default)
  │   ├─ 2) HTTP-01 Self-hosted listener
  │   └─ 3) HTTP-01 Existing web server
  ├─ IF DNS-01:
  │   ├─ Detect DNS Provider (Get-DNSProvider)
  │   ├─ Select DNS Plugin
  │   ├─ Configure DNS Plugin Parameters
  │   └─ Set $plugin and $pluginArgs
  ├─ IF HTTP-01 Self-Host:
  │   ├─ Set $plugin = 'WebSelfHost'
  │   ├─ Ask for Port (default 80)
  │   ├─ Ask for Timeout (default 120s)
  │   └─ Set $pluginArgs (WSHPort, WSHTimeout)
  ├─ IF HTTP-01 WebRoot:
  │   ├─ Set $plugin = 'WebRoot'
  │   ├─ Ask for Web Root Path
  │   ├─ Validate Path Exists
  │   ├─ Ask for Exact Path Option
  │   └─ Set $pluginArgs (WRPath, WRExactPath)
  ├─ Create/Verify ACME Account
  ├─ Request Certificate:
  │   ├─ Manual DNS Mode:
  │   │   └─ Invoke-WithCircuitBreaker → New-PACertificate
  │   └─ Automated Mode (DNS/HTTP):
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
- `Get-PAPlugin` - List available DNS/HTTP plugins

### HTTP-01 Challenge Plugins (New)
- **WebSelfHost Plugin** - Self-hosted HTTP listener
  - Parameters: WSHPort (default 80), WSHTimeout (default 120)
  - Starts temporary HTTP server on specified port
  - Responds to ACME challenge requests automatically
- **WebRoot Plugin** - Existing web server integration
  - Parameters: WRPath (web root path), WRExactPath (optional)
  - Writes challenge files to web server document root
  - Works with IIS, Apache, nginx, etc.

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

## HTTP-01 Challenge Flow (New in 2.0.0)

### Challenge Type Selection

After selecting certificate type, users now choose validation method:

```
1) DNS-01 Challenge (default - requires DNS provider API)
2) HTTP-01 Challenge - Self-hosted listener
3) HTTP-01 Challenge - Existing web server
```

### HTTP-01 Self-Hosted Listener Flow

**Plugin:** WebSelfHost
**File:** Functions/Register-Certificate.ps1 (Lines 240-289)

```
User selects HTTP-01 Self-Hosted
  ↓
Configure Port:
  ├─ Default: 80
  └─ Custom: 1-65535 (requires port forwarding)
  ↓
Configure Timeout:
  ├─ Default: 120 seconds
  └─ Custom: 0 = unlimited
  ↓
Set Plugin Parameters:
  ├─ $plugin = 'WebSelfHost'
  └─ $pluginArgs = @{WSHPort=80; WSHTimeout=120}
  ↓
Request Certificate:
  └─ New-PACertificate -Domain $domain -Plugin WebSelfHost -PluginArgs $pluginArgs
  ↓
Posh-ACME Starts HTTP Listener:
  ├─ Binds to http://+:80/.well-known/acme-challenge/
  ├─ Responds to ACME challenge requests
  ├─ Let's Encrypt validates domain ownership
  └─ Listener stops after validation
  ↓
Certificate Issued
```

**Requirements:**
- Port 80 must be available (not in use)
- Domain must resolve to server's public IP
- Firewall must allow inbound port 80
- Administrator privileges (to bind port 80)

### HTTP-01 Web Root Flow

**Plugin:** WebRoot
**File:** Functions/Register-Certificate.ps1 (Lines 291-352)

```
User selects HTTP-01 WebRoot
  ↓
Configure Web Root:
  ├─ Prompt for path (e.g., C:\inetpub\wwwroot)
  ├─ Validate path exists
  └─ Create if necessary
  ↓
Configure Path Mode:
  ├─ Standard: Create .well-known/acme-challenge/ subdirectory
  └─ Exact: Use specified path as-is
  ↓
Set Plugin Parameters:
  ├─ $plugin = 'WebRoot'
  └─ $pluginArgs = @{WRPath='C:\inetpub\wwwroot'; WRExactPath=$false}
  ↓
Request Certificate:
  └─ New-PACertificate -Domain $domain -Plugin WebRoot -PluginArgs $pluginArgs
  ↓
Posh-ACME Writes Challenge Files:
  ├─ Creates directory: $WRPath\.well-known\acme-challenge\
  ├─ Writes file with token name
  ├─ File content = key authorization
  └─ Web server serves file at http://domain/.well-known/acme-challenge/{token}
  ↓
Let's Encrypt Validates:
  ├─ Requests http://domain/.well-known/acme-challenge/{token}
  ├─ Verifies file content matches expected value
  └─ Marks domain as validated
  ↓
Posh-ACME Cleans Up:
  └─ Removes challenge file
  ↓
Certificate Issued
```

**Requirements:**
- Web server running (IIS, Apache, nginx)
- Web root directory writable
- `.well-known` path publicly accessible
- Domain configured in web server

### HTTP-01 vs DNS-01 Decision Matrix

| Scenario | Recommended Method |
|----------|-------------------|
| Wildcard certificate (`*.domain.com`) | DNS-01 only |
| Server behind firewall (no public IP) | DNS-01 |
| DNS provider without API | HTTP-01 |
| Existing web server (IIS/Apache/nginx) | HTTP-01 WebRoot |
| API server (no web server) | HTTP-01 Self-Host or DNS-01 |
| Port 80 not available | DNS-01 |
| Internal/private domain | DNS-01 Manual |
| Simple public web server | HTTP-01 WebRoot |
| Quick testing | HTTP-01 Self-Host |

### HTTP-01 Error Scenarios

1. **Port 80 in use:**
   - Error: "Address already in use"
   - Solution: Use WebRoot method or stop conflicting service

2. **Firewall blocking:**
   - Error: "Connection timeout"
   - Solution: Open port 80 in firewall

3. **Domain not resolving:**
   - Error: "DNS resolution failed"
   - Solution: Check A record, wait for propagation

4. **Web root not writable:**
   - Error: "Access denied"
   - Solution: Grant write permissions, run as Administrator

5. **Challenge file not accessible:**
   - Error: "404 Not Found"
   - Solution: Check web server configuration, verify `.well-known` path

## Related Documentation

- [HTTP-CHALLENGES.md](./HTTP-CHALLENGES.md) - **NEW** Complete HTTP-01 guide
- [RELIABILITY.md](./RELIABILITY.md) - Circuit breaker and resilience patterns
- [DNS-PROVIDERS.md](./DNS-PROVIDERS.md) - DNS provider setup guides
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues and solutions
- [USAGE.md](./USAGE.md) - General usage documentation

## Version History

- **2.0.0** (2025-10) - Added circuit breaker integration and HTTP-01 challenge support
- **1.9.0** (2025-07) - DNS provider auto-detection improvements
- **1.8.0** (2025-07) - Email notification system
- **1.7.0** (2025-07) - Initial menu-based system

---

**Last Updated:** 2025-10-23
**Validation Status:** ✅ Complete - Flow verified and documented including HTTP-01 support
