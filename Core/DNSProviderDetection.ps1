# Core/DNSProviderDetection.ps1
<#
    .SYNOPSIS
        DNS provider detection and public suffix list management.
#>

#region Public Suffix List Functions
# Function to load and parse the public suffix list
function Get-PublicSuffixList {
    [CmdletBinding()]
    param (
        [string]$Url = "https://publicsuffix.org/list/public_suffix_list.dat"
    )
    $cacheDir = "$env:LOCALAPPDATA\PoshACME"
    $cachePath = "$cacheDir\public_suffix_list.dat"

    # Ensure cache directory exists
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    if (-not (Test-Path $cachePath -PathType Leaf) -or ((Get-Date) - (Get-Item $cachePath).LastWriteTime).TotalDays -gt 7) {
        Write-ProgressHelper -Activity "Updating Public Suffix List" -Status "Downloading latest list..."
        try {
            $wc = New-Object System.Net.WebClient
            $wc.DownloadProgressChanged = {
                param($send, $e)
                Write-ProgressHelper -Activity "Downloading Public Suffix List" `
                    -Status "Downloaded: $([math]::Round($e.BytesReceived/1KB, 2)) KB" `
                    -PercentComplete $e.ProgressPercentage
            }
            $wc.DownloadFileTaskAsync($Url, $cachePath).Wait()
        } catch {
            Write-Error "Failed to download public suffix list: $($_)"
            Write-Log "Failed to download public suffix list: $($_)" -Level 'Error'
            return @()
        }
    }

    try {
        $suffixes = Get-Content -Path $cachePath | Where-Object {
            $_ -and -not $_.StartsWith("//")
        }
        return $suffixes
    } catch {
        Write-Error "Failed to load public suffix list: $($_)"
        Write-Log "Failed to load public suffix list: $($_)" -Level 'Error'
        return @()
    }
}
#endregion

#region DNS Provider Detection
# DNS provider detection
function Get-DNSProvider {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analyzing $Domain..." -PercentComplete 25

    try {
        $nsRecords = Invoke-WithRetry -ScriptBlock {
            (Resolve-DnsName -Name $Domain -Type NS -ErrorAction Stop).NameHost
        } -MaxAttempts 3 -InitialDelaySeconds 2 `
          -OperationName "DNS NS record lookup for $Domain"

        Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analyzing NS records..." -PercentComplete 50

        $detectedProvider = $null
        $confidence = "Low"

        # Provider detection with confidence scoring
        foreach ($ns in $nsRecords) {
            Write-Debug "Checking NS record: $ns"
            
            # Cloudflare detection
            if ($ns -like "*.cloudflare.com") {
                $detectedProvider = @{
                    Name = "Cloudflare"
                    Plugin = "Cloudflare"
                    Confidence = "High"
                    NSRecords = $nsRecords
                    Description = "Cloudflare DNS - Requires API Token"
                    SetupUrl = "https://dash.cloudflare.com/profile/api-tokens"
                }
                break
            }
            # AWS Route53 detection
            elseif ($ns -like "*.awsdns-*.*.amazonaws.com") {
                $detectedProvider = @{
                    Name = "AWS Route53"
                    Plugin = "Route53"
                    Confidence = "High"
                    NSRecords = $nsRecords
                    Description = "Amazon Route53 - Requires AWS credentials or profile"
                    SetupUrl = "https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html"
                }
                break
            }
            # Azure DNS detection
            elseif ($ns -like "*.azure-dns*.info" -or 
                    $ns -like "*.azure-dns*.org" -or 
                    $ns -like "*.azure-dns*.com" -or 
                    $ns -like "*.azure-dns*.net") {
                $detectedProvider = @{
                    Name = "Azure DNS"
                    Plugin = "Azure"
                    Confidence = "High"
                    NSRecords = $nsRecords
                    Description = "Microsoft Azure DNS - Requires Azure authentication"
                    SetupUrl = "https://docs.microsoft.com/en-us/azure/dns/"
                }
                break
            }
            # Google Cloud DNS detection
            elseif ($ns -like "*.googledomains.com" -or $ns -like "*.google.com") {
                $detectedProvider = @{
                    Name = "Google Cloud DNS"
                    Plugin = "GoogleDomains"
                    Confidence = "Medium"
                    NSRecords = $nsRecords
                    Description = "Google Cloud DNS - Requires service account or OAuth"
                    SetupUrl = "https://cloud.google.com/dns/docs"
                }
                break
            }
            # DigitalOcean detection
            elseif ($ns -like "*.digitalocean.com") {
                $detectedProvider = @{
                    Name = "DigitalOcean"
                    Plugin = "DigitalOcean"
                    Confidence = "High"
                    NSRecords = $nsRecords
                    Description = "DigitalOcean DNS - Requires API token"
                    SetupUrl = "https://cloud.digitalocean.com/account/api/tokens"
                }
                break
            }
            # DNS Made Easy detection
            elseif ($ns -like "*.dnsmadeeasy.com") {
                $detectedProvider = @{
                    Name = "DNS Made Easy"
                    Plugin = "DNSMadeEasy"
                    Confidence = "High"
                    NSRecords = $nsRecords
                    Description = "DNS Made Easy - Requires API credentials"
                    SetupUrl = "https://cp.dnsmadeeasy.com/account/info"
                }
                break
            }
            # Namecheap detection
            elseif ($ns -like "*.registrar-servers.com") {
                $detectedProvider = @{
                    Name = "Namecheap"
                    Plugin = "Namecheap"
                    Confidence = "Medium"
                    NSRecords = $nsRecords
                    Description = "Namecheap DNS - Requires API key and username"
                    SetupUrl = "https://ap.www.namecheap.com/settings/tools/apiaccess/"
                }
                break
            }
            # GoDaddy detection
            elseif ($ns -like "*.domaincontrol.com") {
                $detectedProvider = @{
                    Name = "GoDaddy"
                    Plugin = "GoDaddy"
                    Confidence = "Medium"
                    NSRecords = $nsRecords
                    Description = "GoDaddy DNS - Requires API key and secret"
                    SetupUrl = "https://developer.godaddy.com/keys"
                }
                break
            }
            # Linode detection
            elseif ($ns -like "*.linode.com") {
                $detectedProvider = @{
                    Name = "Linode"
                    Plugin = "Linode"
                    Confidence = "High"
                    NSRecords = $nsRecords
                    Description = "Linode DNS - Requires API token"
                    SetupUrl = "https://cloud.linode.com/profile/tokens"
                }
                break
            }
            # Vultr detection
            elseif ($ns -like "*.vultr.com") {
                $detectedProvider = @{
                    Name = "Vultr"
                    Plugin = "Vultr"
                    Confidence = "High"
                    NSRecords = $nsRecords
                    Description = "Vultr DNS - Requires API key"
                    SetupUrl = "https://my.vultr.com/settings/#settingsapi"
                }
                break
            }
            # Hetzner detection
            elseif ($ns -like "*.hetzner.com" -or $ns -like "*.hetzner.de") {
                $detectedProvider = @{
                    Name = "Hetzner"
                    Plugin = "Hetzner"
                    Confidence = "High"
                    NSRecords = $nsRecords
                    Description = "Hetzner DNS - Requires API token"
                    SetupUrl = "https://dns.hetzner.com/settings/api-token"
                }
                break
            }
            # OVH detection
            elseif ($ns -like "*.ovh.net" -or $ns -like "*.ovh.com") {
                $detectedProvider = @{
                    Name = "OVH"
                    Plugin = "OVH"
                    Confidence = "Medium"
                    NSRecords = $nsRecords
                    Description = "OVH DNS - Requires API credentials"
                    SetupUrl = "https://eu.api.ovh.com/createToken/"
                }
                break
            }
        }

        Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analysis complete" -PercentComplete 100

        if ($detectedProvider) {
            Write-Log "DNS provider detected: $($detectedProvider.Name) (Confidence: $($detectedProvider.Confidence))"
            return $detectedProvider
        } else {
            Write-Log "DNS provider could not be automatically detected for $Domain" -Level 'Warning'
            return @{
                Name = "Unknown"
                Plugin = "Manual"
                Confidence = "None"
                NSRecords = $nsRecords
                Description = "Manual DNS - Requires manual TXT record creation"
                SetupUrl = $null
            }
        }

    } catch {
        Write-Warning "Failed to retrieve NS records for ${Domain}: $($_)"
        Write-Log "Failed to retrieve NS records for ${Domain}: $($_)" -Level 'Warning'
        return @{
            Name = "Unknown"
            Plugin = "Manual"
            Confidence = "None"
            NSRecords = @()
            Error = $_.Exception.Message
            Description = "DNS lookup failed - Manual DNS required"
            SetupUrl = $null
        }
    } finally {
        Write-Progress -Activity "DNS Provider Detection" -Completed
    }
}

# Function to get all available DNS plugins
function Get-AvailableDNSPlugins {
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
        Write-Error "Failed to get DNS provider plugins: $($_.Exception.Message)"
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
        'DNSMadeEasy' = 'DNS Made Easy - Enterprise DNS provider'
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
    param (
        [Parameter(Mandatory = $true)]
        [string]$DnsName,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedValue,
        [Parameter()]
        [int]$MaxAttempts = 10,
        [Parameter()]
        [int]$DelaySeconds = 30
    )

    Write-ProgressHelper -Activity "DNS Propagation Check" -Status "Checking $DnsName..." -PercentComplete 0

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            $percentComplete = ($attempt / $MaxAttempts) * 100
            Write-ProgressHelper -Activity "DNS Propagation Check" `
                -Status "Attempt $attempt of $MaxAttempts" `
                -PercentComplete $percentComplete

            $dnsResult = Invoke-WithRetry -ScriptBlock {
                Resolve-DnsName -Name $DnsName -Type TXT -ErrorAction Stop
            } -MaxAttempts 3 -InitialDelaySeconds 5 `
              -OperationName "DNS TXT record lookup for $DnsName"

            if ($dnsResult.Strings -contains $ExpectedValue) {
                Write-ProgressHelper -Activity "DNS Propagation Check" -Status "Record found!" -PercentComplete 100
                Write-Log "DNS TXT record found for ${DnsName}: $($dnsResult.Strings)"
                return $true
            }

            Write-Verbose "DNS TXT record not yet propagated for $DnsName. Found: $($dnsResult.Strings -join ', ')"
            
            if ($attempt -lt $MaxAttempts) {
                Write-ProgressHelper -Activity "DNS Propagation Check" `
                    -Status "Waiting $DelaySeconds seconds before retry..." `
                    -PercentComplete $percentComplete
                Start-Sleep -Seconds $DelaySeconds
            }

        } catch {
            Write-Verbose "DNS lookup failed for ${DnsName}: $($_.Exception.Message)"
            
            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds $DelaySeconds
            }
        }
    }

    Write-Progress -Activity "DNS Propagation Check" -Completed
    Write-Log "DNS TXT record not found for $DnsName after $MaxAttempts attempts" -Level 'Warning'
    return $false
}

# Function to test multiple DNS servers for propagation
function Test-DNSPropagationMultiple {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$DnsName,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedValue,
        [Parameter()]
        [string[]]$DNSServers = @('8.8.8.8', '1.1.1.1', '208.67.222.222', '9.9.9.9')
    )

    Write-Host "`nTesting DNS propagation across multiple servers:" -ForegroundColor Cyan
    $results = @()

    foreach ($server in $DNSServers) {
        try {
            Write-Host "  Testing $server..." -NoNewline
            $result = Resolve-DnsName -Name $DnsName -Type TXT -Server $server -ErrorAction Stop
            
            if ($result.Strings -contains $ExpectedValue) {
                Write-Host " ✓ FOUND" -ForegroundColor Green
                $results += @{ Server = $server; Status = "Found"; Value = $result.Strings -join ', ' }
            } else {
                Write-Host " ✗ NOT FOUND" -ForegroundColor Red
                $results += @{ Server = $server; Status = "Not Found"; Value = $result.Strings -join ', ' }
            }
        } catch {
            Write-Host " ✗ ERROR" -ForegroundColor Red
            $results += @{ Server = $server; Status = "Error"; Value = $_.Exception.Message }
        }
    }

    $foundCount = ($results | Where-Object { $_.Status -eq "Found" }).Count
    $totalCount = $results.Count
    
    Write-Host "`nPropagation Summary: $foundCount/$totalCount servers have the record" -ForegroundColor $(
        if ($foundCount -eq $totalCount) { "Green" } 
        elseif ($foundCount -gt 0) { "Yellow" } 
        else { "Red" }
    )

    return $foundCount -eq $totalCount
}
#endregion