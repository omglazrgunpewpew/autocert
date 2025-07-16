# Core/DNSProviderDetection.ps1
<#
    .SYNOPSIS
        DNS provider detection and public suffix list management for AutoCert.
    .DESCRIPTION
        This module provides comprehensive DNS provider detection capabilities by analyzing
        NS records, SOA records, and other DNS-related information. It supports automatic
        detection of popular DNS providers and provides fallback suggestions for unknown providers.
    .NOTES
        Version: 1.0.0
        Author: AutoCert Team
        Created: 2025-01-01
        Updated: 2025-01-01
#>
#region Public Suffix List Functions
<#
    .SYNOPSIS
        Downloads and caches the public suffix list for domain analysis.
    .DESCRIPTION
        Retrieves the latest public suffix list from Mozilla's PSL and caches it locally.
        The cache is refreshed weekly to ensure accuracy.
    .PARAMETER Url
        The URL to download the public suffix list from.
    .OUTPUTS
        [string[]] Array of public suffixes.
#>
function Get-PublicSuffixList {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param (
        [string]$Url = "https://publicsuffix.org/list/public_suffix_list.dat"
    )
    $cacheDir = "$env:LOCALAPPDATA\PoshACME"
    $cachePath = "$cacheDir\public_suffix_list.dat"
    $cacheMaxAge = 7 # days
    # Ensure cache directory exists
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    # Check if cache needs refresh
    $needsRefresh = $true
    if (Test-Path $cachePath -PathType Leaf) {
        $cacheAge = (Get-Date) - (Get-Item $cachePath).LastWriteTime
        $needsRefresh = $cacheAge.TotalDays -gt $cacheMaxAge
    }
    if ($needsRefresh) {
        Write-ProgressHelper -Activity "Updating Public Suffix List" -Status "Downloading latest list..."
        try {
            Invoke-WebRequest -Uri $Url -OutFile $cachePath -UseBasicParsing
            Write-Log "Public suffix list updated successfully"
        } catch {
            Write-Error -Message "Failed to download public suffix list: $($_)"
            Write-Log "Failed to download public suffix list: $($_)" -Level 'Error'
            # Return empty array if download fails and no cache exists
            if (-not (Test-Path $cachePath)) {
                return @()
            }
        }
    }
    # Load and parse the suffix list
    try {
        $suffixes = Get-Content -Path $cachePath | Where-Object {
            $_ -and -not $_.StartsWith("//") -and $_.Trim()
        }
        return $suffixes
    } catch {
        Write-Error -Message "Failed to load public suffix list: $($_)"
        Write-Log "Failed to load public suffix list: $($_)" -Level 'Error'
        return @()
    }
}
#endregion
#region DNS Provider Detection
<#
    .SYNOPSIS
        Detects the DNS provider for a given domain.
    .DESCRIPTION
        Analyzes NS records, SOA records, and other DNS information to automatically
        detect the DNS provider for a domain. Uses multiple detection methods with
        fallback support.
    .PARAMETER Domain
        The domain to analyze for DNS provider detection.
    .OUTPUTS
        [hashtable] DNS provider information including name, plugin, confidence level, and setup details.
#>
function Get-DNSProvider {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analyzing $Domain..." -PercentComplete 10
    # Check cache first
    $cachedResult = Get-CachedDNSProvider -Domain $Domain
    if ($cachedResult) {
        Write-Log "Using cached DNS provider for $Domain`: $($cachedResult.Name)"
        return $cachedResult
    }
    try {
        # Get NS records with retry logic
        $nsRecords = Invoke-WithRetry -ScriptBlock {
            (Resolve-DnsName -Name $Domain -Type NS -ErrorAction Stop).NameHost
        } -MaxAttempts 3 -InitialDelaySeconds 2 -OperationName "DNS NS record lookup for $Domain"
        Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analyzing NS records..." -PercentComplete 30
        # Primary detection via NS records
        $detectedProvider = Get-ProviderFromNSRecord -NSRecords $nsRecords
        # Fallback detection methods for low confidence results
        if (-not $detectedProvider -or $detectedProvider.Confidence -eq "Low") {
            Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Trying fallback methods..." -PercentComplete 60
            # Try SOA record detection
            $soaProvider = Get-ProviderFromSOA -Domain $Domain
            if ($soaProvider -and $soaProvider.Confidence -ne "None") {
                $detectedProvider = $soaProvider
            }
        }
        Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analysis complete" -PercentComplete 100
        # Return results
        $finalProvider = if ($detectedProvider -and $detectedProvider.Name -ne "Unknown") {
            Write-Log "DNS provider detected: $($detectedProvider.Name) (Confidence: $($detectedProvider.Confidence))"
            $detectedProvider
        } else {
            Write-Log "DNS provider could not be automatically detected for $Domain" -Level 'Warning'
            @{
                Name = "Unknown"
                Plugin = "Manual"
                Confidence = "None"
                NSRecords = $nsRecords
                Description = "Manual DNS - Requires manual TXT record creation"
                SetupUrl = $null
                DetectionMethod = "NS Records"
            }
        }
        # Cache and return result
        Set-CachedDNSProvider -Domain $Domain -Provider $finalProvider
        return $finalProvider
    } catch {
        Write-Warning -Message "Failed to retrieve DNS information for $Domain`: $($_)"
        Write-Log "Failed to retrieve DNS information for $Domain`: $($_)" -Level 'Warning'
        return @{
            Name = "Unknown"
            Plugin = "Manual"
            Confidence = "None"
            NSRecords = @()
            Error = $_.Exception.Message
            Description = "DNS lookup failed - Manual DNS required"
            SetupUrl = $null
            DetectionMethod = "Error"
        }
    } finally {
        Write-Progress -Activity "DNS Provider Detection" -Completed
    }
}
<#
    .SYNOPSIS
        Detects DNS provider from NS records using pattern matching.
    .DESCRIPTION
        Analyzes NS records against known provider patterns to identify the DNS provider.
        Returns the most confident match with provider details.
    .PARAMETER NSRecords
        Array of NS record hostnames to analyze.
    .PARAMETER Domain
        The domain being analyzed (for logging purposes).
    .OUTPUTS
        [hashtable] Provider information or null if no match found.
#>
function Get-ProviderFromNSRecord {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$NSRecords
    )
    # DNS provider patterns organized by confidence level
    $providerPatterns = Get-DNSProviderPattern
    $mediumConfidenceMatch = $null
    # Check each NS record against provider patterns
    foreach ($ns in $NSRecords) {
        Write-Debug "Checking NS record: $ns"
        foreach ($providerName in $providerPatterns.Keys) {
            $provider = $providerPatterns[$providerName]
            foreach ($pattern in $provider.Patterns) {
                if ($ns -like $pattern) {
                    $result = @{
                        Name = $providerName
                        Plugin = $provider.Plugin
                        Confidence = $provider.Confidence
                        NSRecords = $NSRecords
                        Description = $provider.Description
                        SetupUrl = $provider.SetupUrl
                        DetectionMethod = "NS Records"
                        MatchedPattern = $pattern
                        MatchedRecord = $ns
                    }
                    # Return immediately for high confidence matches
                    if ($provider.Confidence -eq "High") {
                        return $result
                    }
                    # Store medium confidence matches for potential return
                    if ($provider.Confidence -eq "Medium") {
                        $mediumConfidenceMatch = $result
                    }
                }
            }
        }
    }
    # Return medium confidence match if no high confidence match found
    return $mediumConfidenceMatch
}
<#
    .SYNOPSIS
        Returns the DNS provider patterns used for detection.
    .DESCRIPTION
        Provides a centralized configuration of DNS provider patterns, organized by
        confidence level and including setup information.
    .OUTPUTS
        [hashtable] Dictionary of provider patterns and metadata.
#>
function Get-DNSProviderPattern {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        # Tier 1 - High confidence patterns (Cloud providers)
        'Cloudflare' = @{
            Patterns = @('*.cloudflare.com')
            Plugin = 'Cloudflare'
            Confidence = 'High'
            Description = 'Cloudflare DNS - Requires API Token'
            SetupUrl = 'https://dash.cloudflare.com/profile/api-tokens'
        }
        'AWS Route53' = @{
            Patterns = @('*.awsdns-*.*.amazonaws.com', '*.awsdns-*.amazonaws.com')
            Plugin = 'Route53'
            Confidence = 'High'
            Description = 'Amazon Route53 - Requires AWS credentials or profile'
            SetupUrl = 'https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html'
        }
        'Azure DNS' = @{
            Patterns = @('*.azure-dns*.info', '*.azure-dns*.org', '*.azure-dns*.com', '*.azure-dns*.net')
            Plugin = 'Azure'
            Confidence = 'High'
            Description = 'Microsoft Azure DNS - Requires Azure authentication'
            SetupUrl = 'https://docs.microsoft.com/en-us/azure/dns/'
        }
        'Google Cloud DNS' = @{
            Patterns = @('*.googledomains.com', '*.google.com', '*.googledns.com')
            Plugin = 'GoogleDomains'
            Confidence = 'High'
            Description = 'Google Cloud DNS - Requires service account or OAuth'
            SetupUrl = 'https://cloud.google.com/dns/docs'
        }
        'DigitalOcean' = @{
            Patterns = @('*.digitalocean.com')
            Plugin = 'DigitalOcean'
            Confidence = 'High'
            Description = 'DigitalOcean DNS - Requires API token'
            SetupUrl = 'https://cloud.digitalocean.com/account/api/tokens'
        }
        'Linode' = @{
            Patterns = @('*.linode.com')
            Plugin = 'Linode'
            Confidence = 'High'
            Description = 'Linode DNS - Requires API token'
            SetupUrl = 'https://cloud.linode.com/profile/tokens'
        }
        'Vultr' = @{
            Patterns = @('*.vultr.com')
            Plugin = 'Vultr'
            Confidence = 'High'
            Description = 'Vultr DNS - Requires API key'
            SetupUrl = 'https://my.vultr.com/settings/#settingsapi'
        }
        'Hetzner' = @{
            Patterns = @('*.hetzner.com', '*.hetzner.de')
            Plugin = 'Hetzner'
            Confidence = 'High'
            Description = 'Hetzner DNS - Requires API token'
            SetupUrl = 'https://dns.hetzner.com/settings/api-token'
        }
        'DNS Made Easy' = @{
            Patterns = @('*.dnsmadeeasy.com')
            Plugin = 'DNSMadeEasy'
            Confidence = 'High'
            Description = 'DNS Made Easy - Requires API credentials'
            SetupUrl = 'https://cp.dnsmadeeasy.com/account/info'
        }
        'NS1' = @{
            Patterns = @('*.nsone.net', '*.ns1.com')
            Plugin = 'NS1'
            Confidence = 'High'
            Description = 'NS1 DNS - Requires API key'
            SetupUrl = 'https://my.nsone.net/#/account/settings'
        }
        'DNSimple' = @{
            Patterns = @('*.dnsimple.com')
            Plugin = 'DNSimple'
            Confidence = 'High'
            Description = 'DNSimple - Requires API token'
            SetupUrl = 'https://dnsimple.com/user'
        }
        'Gandi' = @{
            Patterns = @('*.gandi.net')
            Plugin = 'Gandi'
            Confidence = 'High'
            Description = 'Gandi DNS - Requires API key'
            SetupUrl = 'https://account.gandi.net/account/api'
        }
        'Porkbun' = @{
            Patterns = @('*.porkbun.com')
            Plugin = 'Porkbun'
            Confidence = 'High'
            Description = 'Porkbun DNS - Requires API key'
            SetupUrl = 'https://porkbun.com/account/api'
        }
        'Dynu' = @{
            Patterns = @('*.dynu.com')
            Plugin = 'Dynu'
            Confidence = 'High'
            Description = 'Dynu DNS - Requires API credentials'
            SetupUrl = 'https://www.dynu.com/ControlPanel/APICredentials'
        }
        'Hurricane Electric' = @{
            Patterns = @('*.he.net')
            Plugin = 'HurricaneElectric'
            Confidence = 'High'
            Description = 'Hurricane Electric DNS - Requires API key'
            SetupUrl = 'https://dns.he.net/'
        }
        # Tier 2 - Medium confidence patterns (Registrar DNS)
        'GoDaddy' = @{
            Patterns = @('*.domaincontrol.com')
            Plugin = 'GoDaddy'
            Confidence = 'Medium'
            Description = 'GoDaddy DNS - Requires API key and secret'
            SetupUrl = 'https://developer.godaddy.com/keys'
        }
        'Namecheap' = @{
            Patterns = @('*.registrar-servers.com')
            Plugin = 'Namecheap'
            Confidence = 'Medium'
            Description = 'Namecheap DNS - Requires API key and username'
            SetupUrl = 'https://ap.www.namecheap.com/settings/tools/apiaccess/'
        }
        'OVH' = @{
            Patterns = @('*.ovh.net', '*.ovh.com')
            Plugin = 'OVH'
            Confidence = 'Medium'
            Description = 'OVH DNS - Requires API credentials'
            SetupUrl = 'https://eu.api.ovh.com/createToken/'
        }
        'Hover' = @{
            Patterns = @('*.hover.com')
            Plugin = 'Hover'
            Confidence = 'Medium'
            Description = 'Hover DNS - Requires API credentials'
            SetupUrl = 'https://www.hover.com/api'
        }
        'Network Solutions' = @{
            Patterns = @('*.worldnic.com', '*.networksolutions.com')
            Plugin = 'NetworkSolutions'
            Confidence = 'Medium'
            Description = 'Network Solutions DNS - May require manual configuration'
            SetupUrl = 'https://www.networksolutions.com/'
        }
        'Domain.com' = @{
            Patterns = @('*.domain.com')
            Plugin = 'DomainCom'
            Confidence = 'Medium'
            Description = 'Domain.com DNS - May require manual configuration'
            SetupUrl = 'https://www.domain.com/'
        }
        'Bluehost' = @{
            Patterns = @('*.bluehost.com')
            Plugin = 'Bluehost'
            Confidence = 'Medium'
            Description = 'Bluehost DNS - May require manual configuration'
            SetupUrl = 'https://www.bluehost.com/'
        }
        'HostGator' = @{
            Patterns = @('*.hostgator.com')
            Plugin = 'HostGator'
            Confidence = 'Medium'
            Description = 'HostGator DNS - May require manual configuration'
            SetupUrl = 'https://www.hostgator.com/'
        }
    }
}
# Function for SOA record-based detection
function Get-ProviderFromSOA {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    try {
        $soaRecord = Resolve-DnsName -Name $Domain -Type SOA -ErrorAction Stop
        $primaryNS = $soaRecord.PrimaryServer
        Write-Debug "SOA primary server: $primaryNS"
        # Use the same pattern matching logic as NS records
        return Get-ProviderFromNSRecord -NSRecords @($primaryNS)
    } catch {
        Write-Debug "SOA detection failed for $Domain`: $($_)"
        return $null
    }
}
#endregion
#region DNS Provider Caching
<#
    .SYNOPSIS
        Retrieves cached DNS provider information for a domain.
    .PARAMETER Domain
        The domain to check for cached provider information.
    .OUTPUTS
        [hashtable] Cached provider information or null if not found/expired.
#>
function Get-CachedDNSProvider {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    $cacheDir = "$env:TEMP\AutoCert\DNSCache"
    $cacheFile = "$cacheDir\$($Domain.ToLower()).json"
    if (Test-Path $cacheFile) {
        try {
            $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $cacheAge = (Get-Date) - [datetime]$cached.Timestamp
            # Cache valid for 24 hours
            if ($cacheAge.TotalHours -lt 24) {
                return $cached.Provider
            }
        } catch {
            Write-Debug "Failed to read DNS cache for $Domain`: $($_)"
        }
    }
    return $null
}
<#
    .SYNOPSIS
        Caches DNS provider information for a domain.
    .PARAMETER Domain
        The domain to cache provider information for.
    .PARAMETER Provider
        The provider information to cache.
#>
function Set-CachedDNSProvider {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter(Mandatory = $true)]
        [hashtable]$Provider
    )
    $cacheDir = "$env:TEMP\AutoCert\DNSCache"
    $cacheFile = "$cacheDir\$($Domain.ToLower()).json"
    if ($PSCmdlet.ShouldProcess("$Domain", "Cache DNS provider information")) {
        try {
            if (-not (Test-Path $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }
            $cacheData = @{
                Domain = $Domain
                Provider = $Provider
                Timestamp = (Get-Date).ToString('o')
            }
            $cacheData | ConvertTo-Json -Depth 10 | Set-Content $cacheFile -Encoding UTF8
            Write-Debug "Cached DNS provider for $Domain"
        } catch {
            Write-Debug "Failed to cache DNS provider for $Domain`: $($_)"
        }
    }
}
#endregion
#region Domain Analysis
<#
    .SYNOPSIS
        Determines the apex domain from a given domain name.
    .DESCRIPTION
        Uses the public suffix list to accurately determine the apex domain
        for both regular domains and complex TLDs.
    .PARAMETER Domain
        The domain to analyze.
    .OUTPUTS
        [string] The apex domain.
#>
function Get-ApexDomain {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    try {
        # Load public suffix list
        $suffixes = Get-PublicSuffixList
        # Find the longest matching suffix
        $longestSuffix = ""
        foreach ($suffix in $suffixes) {
            if ($Domain.EndsWith(".$suffix", [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($suffix.Length -gt $longestSuffix.Length) {
                    $longestSuffix = $suffix
                }
            }
        }
        if ($longestSuffix) {
            $remainingDomain = $Domain.Substring(0, $Domain.Length - $longestSuffix.Length - 1)
            $parts = $remainingDomain.Split('.')
            if ($parts.Length -gt 0) {
                return "$($parts[-1]).$longestSuffix"
            }
        }
        # Fallback to simple logic
        $parts = $Domain.Split('.')
        if ($parts.Length -ge 2) {
            return "$($parts[-2]).$($parts[-1])"
        }
        return $Domain
    } catch {
        Write-Debug "Failed to determine apex domain for $Domain`: $($_)"
        return $Domain
    }
}
<#
    .SYNOPSIS
        Extended DNS provider detection with subdomain handling.
    .DESCRIPTION
        Attempts DNS provider detection on the given domain, and if unsuccessful,
        tries detection on the apex domain.
    .PARAMETER Domain
        The domain to analyze.
    .OUTPUTS
        [hashtable] DNS provider information.
#>
function Get-DNSProviderExtended {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    # Try detection on the provided domain first
    $provider = Get-DNSProvider -Domain $Domain
    # If detection failed or confidence is low, try apex domain
    if (-not $provider -or $provider.Confidence -eq "None" -or $provider.Confidence -eq "Low") {
        $apexDomain = Get-ApexDomain -Domain $Domain
        if ($apexDomain -ne $Domain) {
            Write-Debug "Trying apex domain detection: $apexDomain"
            $apexProvider = Get-DNSProvider -Domain $apexDomain
            if ($apexProvider -and $apexProvider.Confidence -ne "None") {
                $apexProvider.OriginalDomain = $Domain
                $apexProvider.DetectedFromApex = $true
                return $apexProvider
            }
        }
    }
    return $provider
}
#endregion
#region User Interface Functions
# Function to validate DNS provider configuration
function Test-DNSProviderConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$providerName,
        [Parameter()]
        [hashtable]$credentials
    )
    Write-Host -Object "`n=== Testing DNS Provider Configuration ===" -ForegroundColor Cyan
    Write-Warning -Message "Provider: $providerName"
    try {
        # Test if the provider plugin is available
        $plugin = Get-PAPlugin | Where-Object { $_.Name -eq $providerName }
        if (-not $plugin) {
            Write-Host -Object "❌ Plugin '$providerName' not found in Posh-ACME" -ForegroundColor Red
            Write-Warning -Message "Available DNS plugins:"
            Get-PAPlugin | Where-Object { $_.ChallengeType -eq 'dns-01' } | ForEach-Object {
                Write-Host -Object "  • $($_.Name)" -ForegroundColor White
            }
            return $false
        }
        Write-Information -MessageData "✅ Plugin found: $($plugin.Name)" -InformationAction Continue
        # Show required parameters
        if ($plugin.Params) {
            Write-Warning -Message "Required parameters:"
            foreach ($param in $plugin.Params) {
                $status = if ($credentials -and $credentials.ContainsKey($param)) { "✅" } else { "❌" }
                Write-Host -Object "  $status $param" -ForegroundColor White
            }
        }
        # Test API connectivity (basic check)
        Write-Warning -Message "Testing API connectivity..."
        # This is a placeholder - actual implementation would depend on the provider
        # For now, just check if required credentials are provided
        $missingCreds = @()
        if ($plugin.Params) {
            foreach ($param in $plugin.Params) {
                if (-not $credentials -or -not $credentials.ContainsKey($param)) {
                    $missingCreds += $param
                }
            }
        }
        if ($missingCreds.Count -eq 0) {
            Write-Information -MessageData "✅ All required credentials appear to be provided" -InformationAction Continue
            return $true
        } else {
            Write-Host -Object "❌ Missing credentials: $($missingCreds -join ', ')" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Error -Message "❌ Error testing provider configuration: $($_.Exception.Message)"
        return $false
    }
}
# Function to get DNS provider recommendations based on domain
function Get-DNSProviderRecommendation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )
    Write-Host -Object "`n=== DNS Provider Recommendations for $Domain ===" -ForegroundColor Cyan
    # Get current provider info
    $currentProvider = Get-DNSProviderExtended -Domain $Domain
    if ($currentProvider -and $currentProvider.Name -ne "Unknown") {
        Write-Information -MessageData "Current Provider: $($currentProvider.Name)" -InformationAction Continue
        Write-Host -Object "Plugin: $($currentProvider.Plugin)" -ForegroundColor White
        Write-Host -Object "Confidence: $($currentProvider.Confidence)" -ForegroundColor White
        if ($currentProvider.SetupUrl) {
            Write-Host -Object "Setup URL: $($currentProvider.SetupUrl)" -ForegroundColor Blue
        }
        Write-Information -MessageData "" -InformationAction Continue
    }
    # Provide general recommendations
    Write-Warning -Message "Recommended DNS Providers (in order of preference):"
    $recommendations = @(
        @{
            Name = "Cloudflare"
            Pros = @("Free tier available", "Good performance", "Easy API setup", "Built-in CDN")
            Cons = @("Requires domain transfer for full features")
            Difficulty = "Easy"
        },
        @{
            Name = "AWS Route53"
            Pros = @("Reliable", "Integrates with AWS services", "Pay-per-use pricing")
            Cons = @("Can be complex for beginners", "Costs money")
            Difficulty = "Medium"
        },
        @{
            Name = "Google Cloud DNS"
            Pros = @("Good performance", "Integrates with Google Cloud", "Reasonable pricing")
            Cons = @("Requires Google Cloud account", "Less user-friendly")
            Difficulty = "Medium"
        },
        @{
            Name = "DigitalOcean DNS"
            Pros = @("Free with account", "Simple API", "Good documentation")
            Cons = @("Requires DigitalOcean account")
            Difficulty = "Easy"
        }
    )
    foreach ($rec in $recommendations) {
        Write-Host -Object "  📍 $($rec.Name) - $($rec.Difficulty)" -ForegroundColor White
        Write-Host -Object "     Pros: $($rec.Pros -join ', ')" -ForegroundColor Green
        Write-Host -Object "     Cons: $($rec.Cons -join ', ')" -ForegroundColor Red
        Write-Information -MessageData "" -InformationAction Continue
    }
    Write-Warning -Message "💡 Quick Start Tips:"
    Write-Host -Object "  • For beginners: Start with Cloudflare or DigitalOcean" -ForegroundColor White
    Write-Host -Object "  • For AWS users: Route53 integrates well" -ForegroundColor White
    Write-Host -Object "  • For cost-conscious: Cloudflare free tier or DigitalOcean" -ForegroundColor White
    Write-Host -Object "  • For high-volume: Consider Route53 or Google Cloud DNS" -ForegroundColor White
    Write-Host -Object "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
}
# Function to get all available DNS plugins
function Get-AvailableDNSPlugin {
    [CmdletBinding()]
    param()
    try {
        $plugins = Get-PAPlugin | Where-Object { $_.ChallengeType -eq 'dns-01' }
        # Plugin information with descriptions
        $pluginList = @()
        foreach ($plugin in $plugins) {
            $pluginInfo = @{
                Name = $plugin.Name
                ChallengeType = $plugin.ChallengeType
                RequiredParams = $plugin.Params
                Description = Get-PluginDescription -PluginName $plugin.Name
                SetupUrl = Get-PluginSetupUrl -PluginName $plugin.Name
            }
            $pluginList += $pluginInfo
        }
        return $pluginList
    } catch {
        Write-Error -Message "Failed to get DNS provider plugins: $($_.Exception.Message)"
    }
}
# Function to get plugin description
function Get-PluginDescription {
    [CmdletBinding()]
    param([string]$PluginName)
    $descriptions = @{
        'Cloudflare' = 'Cloudflare DNS - Global CDN and DNS provider'
        'Route53' = 'Amazon Route 53 - AWS DNS service'
        'Azure' = 'Microsoft Azure DNS - Azure cloud DNS'
        'GoogleDomains' = 'Google Cloud DNS - Google cloud DNS service'
        'DigitalOcean' = 'DigitalOcean DNS - Simple cloud DNS'
        'DNSMadeEasy' = 'DNS Made Easy - DNS provider'
        'Namecheap' = 'Namecheap DNS - Domain registrar DNS'
        'GoDaddy' = 'GoDaddy DNS - Domain registrar DNS'
        'Linode' = 'Linode DNS - Cloud hosting DNS'
        'Vultr' = 'Vultr DNS - Cloud hosting DNS'
        'Hetzner' = 'Hetzner DNS - German cloud provider DNS'
        'OVH' = 'OVH DNS - European cloud provider DNS'
        'Manual' = 'Manual DNS - Requires manual TXT record creation'
    }
    return $descriptions[$PluginName] ?? "DNS provider plugin: $PluginName"
}
# Function to get plugin setup URL
function Get-PluginSetupUrl {
    [CmdletBinding()]
    param([string]$PluginName)
    $setupUrls = @{
        'Cloudflare' = 'https://dash.cloudflare.com/profile/api-tokens'
        'Route53' = 'https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html'
        'Azure' = 'https://docs.microsoft.com/en-us/azure/dns/'
        'GoogleDomains' = 'https://cloud.google.com/dns/docs'
        'DigitalOcean' = 'https://cloud.digitalocean.com/account/api/tokens'
        'DNSMadeEasy' = 'https://cp.dnsmadeeasy.com/account/info'
        'Namecheap' = 'https://ap.www.namecheap.com/settings/tools/apiaccess/'
        'GoDaddy' = 'https://developer.godaddy.com/keys'
        'Linode' = 'https://cloud.linode.com/profile/tokens'
        'Vultr' = 'https://my.vultr.com/settings/#settingsapi'
        'Hetzner' = 'https://dns.hetzner.com/settings/api-token'
        'OVH' = 'https://eu.api.ovh.com/createToken/'
    }
    return $setupUrls[$PluginName]
}
# Function to validate DNS propagation
function Test-DNSPropagation {
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$dnsName,
        [Parameter(Mandatory = $true)]
        [string]$expectedValue,
        [Parameter()]
        [int]$maxAttempts = 10,
        [Parameter()]
        [int]$delaySeconds = 30
    )
    Write-ProgressHelper -Activity "DNS Propagation Check" -Status "Checking $dnsName..." -PercentComplete 0
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            $percentComplete = ($attempt / $maxAttempts) * 100
            Write-ProgressHelper -Activity "DNS Propagation Check" `
                -Status "Attempt $attempt of $maxAttempts" `
                -PercentComplete $percentComplete
            $dnsResult = Invoke-WithRetry -ScriptBlock {
                Resolve-DnsName -Name $dnsName -Type TXT -ErrorAction Stop
            } -MaxAttempts 3 -InitialDelaySeconds 5 `
              -OperationName "DNS TXT record lookup for $dnsName"
            if ($dnsResult.Strings -contains $expectedValue) {
                Write-ProgressHelper -Activity "DNS Propagation Check" -Status "Record found!" -PercentComplete 100
                Write-Log "DNS TXT record found for $dnsName`: $($dnsResult.Strings)"
                return $true
            }
            Write-Verbose "DNS TXT record not yet propagated for $dnsName. Found: $($dnsResult.Strings -join ', ')"
            if ($attempt -lt $maxAttempts) {
                Write-ProgressHelper -Activity "DNS Propagation Check" `
                    -Status "Waiting $delaySeconds seconds before retry..." `
                    -PercentComplete $percentComplete
                Start-Sleep -Seconds $delaySeconds
            }
        } catch {
            Write-Verbose "DNS lookup failed for $dnsName`: $($_.Exception.Message)"
            if ($attempt -lt $maxAttempts) {
                Start-Sleep -Seconds $delaySeconds
            }
        }
    }
    Write-Progress -Activity "DNS Propagation Check" -Completed
    Write-Log "DNS TXT record not found for $dnsName after $maxAttempts attempts" -Level 'Warning'
    return $false
}
# Function to test multiple DNS servers for propagation
function Test-DNSPropagationMultiple {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$dnsName,
        [Parameter(Mandatory = $true)]
        [string]$expectedValue,
        [Parameter()]
        [string[]]$dnsServers = @('8.8.8.8', '1.1.1.1', '208.67.222.222', '9.9.9.9')
    )
    Write-Host -Object "`nTesting DNS propagation across multiple servers:" -ForegroundColor Cyan
    $results = @()
    foreach ($server in $dnsServers) {
        try {
            Write-Host -Object "  Testing $server..." -NoNewline
            $result = Resolve-DnsName -Name $dnsName -Type TXT -Server $server -ErrorAction Stop
            if ($result.Strings -contains $expectedValue) {
                Write-Information -MessageData " ✓ FOUND" -InformationAction Continue
                $results += @{ Server = $server; Status = "Found"; Value = $result.Strings -join ', ' }
            } else {
                Write-Error -Message " ✗ NOT FOUND"
                $results += @{ Server = $server; Status = "Not Found"; Value = $result.Strings -join ', ' }
            }
        } catch {
            Write-Error -Message " ✗ ERROR"
            $results += @{ Server = $server; Status = "Error"; Value = $_.Exception.Message }
        }
    }
    $foundCount = ($results | Where-Object { $_.Status -eq "Found" }).Count
    $totalCount = $results.Count
    Write-Host -Object "`nPropagation Summary: $foundCount/$totalCount servers have the record" -ForegroundColor $(
        if ($foundCount -eq $totalCount) { "Green" }
        elseif ($foundCount -gt 0) { "Yellow" }
        else { "Red" }
    )
    return $foundCount -eq $totalCount
}
<#
    .SYNOPSIS
        Provides DNS provider suggestions based on domain analysis.
    .PARAMETER Domain
        The domain to analyze for suggestions.
    .PARAMETER nsRecords
        Optional array of NS records to analyze.
#>
function Get-DNSProviderSuggestion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter()]
        [string[]]$nsRecords
    )
    Write-Host -Object "`n=== DNS Provider Suggestions for $Domain ===" -ForegroundColor Cyan
    if ($nsRecords -and $nsRecords.Count -gt 0) {
        Write-Warning -Message "NS Records found:"
        foreach ($ns in $nsRecords) {
            Write-Host -Object "  • $ns" -ForegroundColor White
        }
        Write-Information -MessageData "" -InformationAction Continue
    }
    # Analyze NS records for hosting patterns
    $suggestions = Get-HostingProviderSuggestions -NSRecords $nsRecords
    # Display suggestions
    Write-Information -MessageData "Suggestions:" -InformationAction Continue
    if ($suggestions.Count -gt 0) {
        foreach ($suggestion in $suggestions) {
            Write-Host -Object "  • $suggestion" -ForegroundColor White
        }
    }
    # General recommendations
    Write-Host -Object "  • Check if your domain registrar offers DNS API access" -ForegroundColor White
    Write-Host -Object "  • Consider switching to a supported DNS provider:" -ForegroundColor White
    Write-Host -Object "    - Cloudflare (free tier available)" -ForegroundColor Gray
    Write-Host -Object "    - AWS Route53 (pay-per-use)" -ForegroundColor Gray
    Write-Host -Object "    - Google Cloud DNS" -ForegroundColor Gray
    Write-Host -Object "    - DigitalOcean DNS (free with account)" -ForegroundColor Gray
    Write-Host -Object "  • Manual DNS configuration is always an option" -ForegroundColor White
    Write-Warning -Message "`nFor manual configuration, you'll need to:"
    Write-Host -Object "  1. Create a TXT record when prompted" -ForegroundColor White
    Write-Host -Object "  2. Wait for DNS propagation (usually 5-15 minutes)" -ForegroundColor White
    Write-Host -Object "  3. Continue with the certificate process" -ForegroundColor White
    Write-Host -Object "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
}
<#
    .SYNOPSIS
        Analyzes NS records for hosting provider patterns.
    .PARAMETER NSRecords
        Array of NS records to analyze.
    .OUTPUTS
        [string[]] Array of suggestions based on detected patterns.
#>
function Get-HostingProviderSuggestion {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param (
        [Parameter()]
        [string[]]$NSRecords
    )
    $suggestions = @()
    if (-not $NSRecords) {
        return $suggestions
    }
    # Common hosting provider patterns
    $hostingPatterns = @{
        "dnspod.com" = "DNSPod (Tencent Cloud) - Popular in China. May need manual configuration."
        "dns.com" = "DNS.com service - May need manual configuration."
        "cloudns.net" = "ClouDNS service - May have API available."
        "zoneedit.com" = "ZoneEdit DNS service - May need manual configuration."
        "afraid.org" = "FreeDNS (afraid.org) - Free DNS service, may need manual configuration."
        "wordpress.com" = "WordPress.com hosting - May need manual configuration."
        "github.io" = "GitHub Pages - Requires manual DNS configuration."
        "netlify.com" = "Netlify hosting - May have API available."
        "vercel.com" = "Vercel hosting - May have API available."
        "shopify.com" = "Shopify hosting - May need manual configuration."
        "squarespace.com" = "Squarespace hosting - May need manual configuration."
        "wix.com" = "Wix hosting - May need manual configuration."
        "hubspot.com" = "HubSpot hosting - May need manual configuration."
    }
    foreach ($ns in $NSRecords) {
        foreach ($pattern in $hostingPatterns.Keys) {
            if ($ns -like "*$pattern*") {
                $suggestions += $hostingPatterns[$pattern]
                break
            }
        }
    }
    return $suggestions
}
#endregion



