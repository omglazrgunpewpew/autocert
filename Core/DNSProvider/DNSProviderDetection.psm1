# Core/DNSProvider/DNSProviderDetection.psm1
<#
    .SYNOPSIS
        DNS Provider Detection Module
    .DESCRIPTION
        Modular DNS provider detection system with separate components for:
        - Public suffix list management
        - Provider pattern definitions
        - Core detection logic
        - Caching functionality
        - Domain analysis
        - User interface functions
        - API testing capabilities
    .NOTES
        Version: 1.0.0
        Author: AutoCert Team
        Created: 2025-01-17
        Updated: 2025-01-17
#>

# Get the directory containing this module
$ModuleRoot = $PSScriptRoot

# Import all component modules
$ComponentModules = @(
    'PublicSuffixList.ps1'
    'DNSProviderPatterns.ps1'
    'DNSProviderCache.ps1'
    'DomainAnalysis.ps1'
    'DNSProviderCore.ps1'
    'DNSProviderUI.ps1'
    'DNSProviderAPITesting.ps1'
)

foreach ($Module in $ComponentModules)
{
    $ModulePath = Join-Path $ModuleRoot $Module
    if (Test-Path $ModulePath)
    {
        Write-Verbose "Loading DNS Provider module component: $Module"
        . $ModulePath
    } else
    {
        Write-Warning "DNS Provider module component not found: $ModulePath"
    }
}

# Export all public functions from the components
$PublicFunctions = @(
    # From PublicSuffixList.ps1
    'Get-PublicSuffixList'

    # From DNSProviderPatterns.ps1
    'Get-DNSProviderPattern'

    # From DNSProviderCache.ps1
    'Get-CachedDNSProvider'
    'Set-CachedDNSProvider'

    # From DomainAnalysis.ps1
    'Get-ApexDomain'
    'Get-DNSProviderExtended'

    # From DNSProviderCore.ps1
    'Get-DNSProvider'
    'Get-ProviderFromNSRecord'
    'Get-ProviderFromSOA'

    # From DNSProviderUI.ps1
    'Test-DNSProviderConfiguration'
    'Get-DNSProviderRecommendation'
    'Get-AvailableDNSPlugin'
    'Get-PluginDescription'
    'Get-PluginSetupUrl'
    'Test-DNSPropagation'
    'Test-DNSPropagationMultiple'
    'Get-DNSProviderSuggestion'
    'Get-HostingProviderSuggestion'

    # From DNSProviderAPITesting.ps1
    'Test-DNSProviderAPI'
    'Test-CloudflareAPI'
    'Test-CombellAPI'
    'Test-Route53API'
    'Test-GenericDNSProvider'
    'Invoke-DNSProviderHealthCheck'
)

Export-ModuleMember -Function $PublicFunctions

Write-Verbose "DNS Provider Detection module loaded with $($PublicFunctions.Count) functions across $($ComponentModules.Count) components"
