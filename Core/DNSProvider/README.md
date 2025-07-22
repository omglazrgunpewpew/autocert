# DNS Provider Detection Module

This directory contains the modular DNS provider detection system for AutoCert.

## Structure

- **DNSProviderDetection.psm1** - Module manifest and coordinator
- **PublicSuffixList.ps1** - Mozilla Public Suffix List management
- **DNSProviderPatterns.ps1** - Provider detection patterns and configuration
- **DNSProviderCache.ps1** - Caching functionality for detection results
- **DomainAnalysis.ps1** - Domain parsing and apex domain determination
- **DNSProviderCore.ps1** - Core DNS provider detection logic
- **DNSProviderUI.ps1** - User interface and recommendation functions
- **DNSProviderAPITesting.ps1** - API connectivity testing for various providers

## Usage

The main entry point is `Core/DNSProvider/DNSProviderDetection.ps1` which imports this modular system.

```powershell
Import-Module "./Core/DNSProvider/DNSProviderDetection.ps1"
$provider = Get-DNSProvider -Domain "example.com"
```

## Functions

### Core Detection

- `Get-DNSProvider` - Main DNS provider detection function
- `Get-ProviderFromNSRecord` - Detect provider from NS records
- `Get-ProviderFromSOA` - Detect provider from SOA records
- `Get-DNSProviderExtended` - Extended detection with subdomain handling

### Domain Analysis

- `Get-ApexDomain` - Determine apex domain using public suffix list
- `Get-PublicSuffixList` - Download and cache Mozilla PSL

### Configuration & Patterns

- `Get-DNSProviderPattern` - Get provider detection patterns
- `Get-CachedDNSProvider` - Retrieve cached detection results
- `Set-CachedDNSProvider` - Cache detection results

### User Interface

- `Get-DNSProviderRecommendation` - Provider recommendations
- `Test-DNSProviderConfiguration` - Validate provider setup
- `Test-DNSPropagation` - Check DNS propagation
- `Get-AvailableDNSPlugin` - List available Posh-ACME plugins

### API Testing

- `Test-DNSProviderAPI` - Test provider API connectivity
- `Test-CloudflareAPI` - Cloudflare-specific API testing
- `Test-CombellAPI` - Combell-specific API testing
- `Invoke-DNSProviderHealthCheck` - Comprehensive health check

## Benefits of Modular Design

1. **Maintainability** - Each module has a single responsibility
2. **Testability** - Components can be tested independently
3. **Reusability** - Modules can be used separately if needed
4. **Clarity** - Clear separation of concerns
5. **Performance** - Only needed components are loaded

## Dependencies

- **Posh-ACME** - Required for plugin information and DNS operations
- **PowerShell 5.1+** - Core PowerShell functionality
- **Internet Access** - For public suffix list updates and API testing
