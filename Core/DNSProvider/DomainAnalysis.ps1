# Core/DNSProvider/DomainAnalysis.ps1
<#
    .SYNOPSIS
        Domain parsing and analysis functionality.
    .DESCRIPTION
        This module provides domain analysis capabilities including apex domain
        determination and extended DNS provider detection with subdomain handling.
    .NOTES
        Version: 1.0.0
        Author: AutoCert Team
        Created: 2025-01-17
        Updated: 2025-01-17
#>

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
function Get-ApexDomain
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    try
    {
        # Load public suffix list
        $suffixes = Get-PublicSuffixList

        # Find the longest matching suffix
        $longestSuffix = ""
        foreach ($suffix in $suffixes)
        {
            if ($Domain.EndsWith(".$suffix", [System.StringComparison]::OrdinalIgnoreCase))
            {
                if ($suffix.Length -gt $longestSuffix.Length)
                {
                    $longestSuffix = $suffix
                }
            }
        }

        if ($longestSuffix)
        {
            $remainingDomain = $Domain.Substring(0, $Domain.Length - $longestSuffix.Length - 1)
            $parts = $remainingDomain.Split('.')
            if ($parts.Length -gt 0)
            {
                return "$($parts[-1]).$longestSuffix"
            }
        }

        # Fallback to simple logic
        $parts = $Domain.Split('.')
        if ($parts.Length -ge 2)
        {
            return "$($parts[-2]).$($parts[-1])"
        }
        return $Domain
    } catch
    {
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
function Get-DNSProviderExtended
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    # Try detection on the provided domain first
    $provider = Get-DNSProvider -Domain $Domain

    # If detection failed or confidence is low, try apex domain
    if (-not $provider -or $provider.Confidence -eq "None" -or $provider.Confidence -eq "Low")
    {
        $apexDomain = Get-ApexDomain -Domain $Domain
        if ($apexDomain -ne $Domain)
        {
            Write-Debug "Trying apex domain detection: $apexDomain"
            $apexProvider = Get-DNSProvider -Domain $apexDomain
            if ($apexProvider -and $apexProvider.Confidence -ne "None")
            {
                $apexProvider.OriginalDomain = $Domain
                $apexProvider.DetectedFromApex = $true
                return $apexProvider
            }
        }
    }
    return $provider
}

# Export functions
Export-ModuleMember -Function Get-ApexDomain, Get-DNSProviderExtended
