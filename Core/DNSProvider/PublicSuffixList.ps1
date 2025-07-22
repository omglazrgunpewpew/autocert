# Core/DNSProvider/PublicSuffixList.ps1
<#
    .SYNOPSIS
        Public suffix list management for domain analysis.
    .DESCRIPTION
        This module provides functionality to download, cache, and manage the public suffix list
        for accurate domain parsing and apex domain determination.
    .NOTES
        Version: 1.0.0
        Author: AutoCert Team
        Created: 2025-01-17
        Updated: 2025-01-17
#>

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
function Get-PublicSuffixList
{
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param (
        [string]$Url = "https://publicsuffix.org/list/public_suffix_list.dat"
    )

    $cacheDir = "$env:LOCALAPPDATA\PoshACME"
    $cachePath = "$cacheDir\public_suffix_list.dat"
    $cacheMaxAge = 7 # days

    # Ensure cache directory exists
    if (-not (Test-Path $cacheDir))
    {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    # Check if cache needs refresh
    $needsRefresh = $true
    if (Test-Path $cachePath -PathType Leaf)
    {
        $cacheAge = (Get-Date) - (Get-Item $cachePath).LastWriteTime
        $needsRefresh = $cacheAge.TotalDays -gt $cacheMaxAge
    }

    if ($needsRefresh)
    {
        Write-ProgressHelper -Activity "Updating Public Suffix List" -Status "Downloading latest list..."
        try
        {
            Invoke-WebRequest -Uri $Url -OutFile $cachePath -UseBasicParsing
            Write-Log "Public suffix list updated successfully"
        } catch
        {
            Write-Error -Message "Failed to download public suffix list: $($_)"
            Write-Log "Failed to download public suffix list: $($_)" -Level 'Error'
            # Return empty array if download fails and no cache exists
            if (-not (Test-Path $cachePath))
            {
                return @()
            }
        }
    }

    # Load and parse the suffix list
    try
    {
        $suffixes = Get-Content -Path $cachePath | Where-Object {
            $_ -and -not $_.StartsWith("//") -and $_.Trim()
        }
        return $suffixes
    } catch
    {
        Write-Error -Message "Failed to load public suffix list: $($_)"
        Write-Log "Failed to load public suffix list: $($_)" -Level 'Error'
        return @()
    }
}

# Export functions
Export-ModuleMember -Function Get-PublicSuffixList
