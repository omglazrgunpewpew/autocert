# Core/DNSProvider/DNSProviderCache.ps1
<#
    .SYNOPSIS
        DNS provider detection caching functionality.
    .DESCRIPTION
        This module provides caching capabilities for DNS provider detection results
        to improve performance and reduce redundant DNS lookups.
    .NOTES
        Version: 1.0.0
        Author: AutoCert Team
        Created: 2025-01-17
        Updated: 2025-01-17
#>

<#
    .SYNOPSIS
        Retrieves cached DNS provider information for a domain.
    .PARAMETER Domain
        The domain to check for cached provider information.
    .OUTPUTS
        [hashtable] Cached provider information or null if not found/expired.
#>
function Get-CachedDNSProvider
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    $cacheDir = "$env:TEMP\AutoCert\DNSCache"
    $cacheFile = "$cacheDir\$($Domain.ToLower()).json"

    if (Test-Path $cacheFile)
    {
        try
        {
            $cached = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $cacheAge = (Get-Date) - [datetime]$cached.Timestamp
            # Cache valid for 24 hours
            if ($cacheAge.TotalHours -lt 24)
            {
                return $cached.Provider
            }
        } catch
        {
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
function Set-CachedDNSProvider
{
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter(Mandatory = $true)]
        [hashtable]$Provider
    )

    $cacheDir = "$env:TEMP\AutoCert\DNSCache"
    $cacheFile = "$cacheDir\$($Domain.ToLower()).json"

    if ($PSCmdlet.ShouldProcess("$Domain", "Cache DNS provider information"))
    {
        try
        {
            if (-not (Test-Path $cacheDir))
            {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }

            $cacheData = @{
                Domain    = $Domain
                Provider  = $Provider
                Timestamp = (Get-Date).ToString('o')
            }

            $cacheData | ConvertTo-Json -Depth 10 | Set-Content $cacheFile -Encoding UTF8
            Write-Debug "Cached DNS provider for $Domain"
        } catch
        {
            Write-Debug "Failed to cache DNS provider for $Domain`: $($_)"
        }
    }
}

# Export functions
Export-ModuleMember -Function Get-CachedDNSProvider, Set-CachedDNSProvider
