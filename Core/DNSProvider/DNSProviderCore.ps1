# Core/DNSProvider/DNSProviderCore.ps1
<#
    .SYNOPSIS
        Core DNS provider detection functionality.
    .DESCRIPTION
        This module provides the main DNS provider detection logic, including
        NS record analysis, SOA record fallback, and pattern matching.
    .NOTES
        Version: 1.0.0
        Author: AutoCert Team
        Created: 2025-01-17
        Updated: 2025-01-17
#>

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
function Get-DNSProvider
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analyzing $Domain..." -PercentComplete 10

    # Check cache first
    $cachedResult = Get-CachedDNSProvider -Domain $Domain
    if ($cachedResult)
    {
        Write-Log "Using cached DNS provider for $Domain`: $($cachedResult.Name)"
        return $cachedResult
    }

    try
    {
        # Get NS records with retry logic
        $nsRecords = Invoke-WithRetry -ScriptBlock {
            (Resolve-DnsName -Name $Domain -Type NS -ErrorAction Stop).NameHost
        } -MaxAttempts 3 -InitialDelaySeconds 2 -OperationName "DNS NS record lookup for $Domain"

        Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analyzing NS records..." -PercentComplete 30

        # Primary detection via NS records
        $detectedProvider = Get-ProviderFromNSRecord -NSRecords $nsRecords

        # Fallback detection methods for low confidence results
        if (-not $detectedProvider -or $detectedProvider.Confidence -eq "Low")
        {
            Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Trying fallback methods..." -PercentComplete 60

            # Try SOA record detection
            $soaProvider = Get-ProviderFromSOA -Domain $Domain
            if ($soaProvider -and $soaProvider.Confidence -ne "None")
            {
                $detectedProvider = $soaProvider
            }
        }

        Write-ProgressHelper -Activity "DNS Provider Detection" -Status "Analysis complete" -PercentComplete 100

        # Return results
        $finalProvider = if ($detectedProvider -and $detectedProvider.Name -ne "Unknown")
        {
            Write-Log "DNS provider detected: $($detectedProvider.Name) (Confidence: $($detectedProvider.Confidence))"
            $detectedProvider
        } else
        {
            Write-Log "DNS provider could not be automatically detected for $Domain" -Level 'Warning'
            @{
                Name            = "Unknown"
                Plugin          = "Manual"
                Confidence      = "None"
                NSRecords       = $nsRecords
                Description     = "Manual DNS - Requires manual TXT record creation"
                SetupUrl        = $null
                DetectionMethod = "NS Records"
            }
        }

        # Cache and return result
        Set-CachedDNSProvider -Domain $Domain -Provider $finalProvider
        return $finalProvider
    } catch
    {
        Write-Warning -Message "Failed to retrieve DNS information for $Domain`: $($_)"
        Write-Log "Failed to retrieve DNS information for $Domain`: $($_)" -Level 'Warning'
        return @{
            Name            = "Unknown"
            Plugin          = "Manual"
            Confidence      = "None"
            NSRecords       = @()
            Error           = $_.Exception.Message
            Description     = "DNS lookup failed - Manual DNS required"
            SetupUrl        = $null
            DetectionMethod = "Error"
        }
    } finally
    {
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
    .OUTPUTS
        [hashtable] Provider information or null if no match found.
#>
function Get-ProviderFromNSRecord
{
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
    foreach ($ns in $NSRecords)
    {
        Write-Debug "Checking NS record: $ns"
        foreach ($providerName in $providerPatterns.Keys)
        {
            $provider = $providerPatterns[$providerName]
            foreach ($pattern in $provider.Patterns)
            {
                if ($ns -like $pattern)
                {
                    $result = @{
                        Name            = $providerName
                        Plugin          = $provider.Plugin
                        Confidence      = $provider.Confidence
                        NSRecords       = $NSRecords
                        Description     = $provider.Description
                        SetupUrl        = $provider.SetupUrl
                        DetectionMethod = "NS Records"
                        MatchedPattern  = $pattern
                        MatchedRecord   = $ns
                    }

                    # Return immediately for high confidence matches
                    if ($provider.Confidence -eq "High")
                    {
                        return $result
                    }

                    # Store medium confidence matches for potential return
                    if ($provider.Confidence -eq "Medium")
                    {
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
        Detects DNS provider from SOA record using pattern matching.
    .DESCRIPTION
        Attempts DNS provider detection using SOA record as fallback method
        when NS record detection fails or has low confidence.
    .PARAMETER Domain
        The domain to analyze for SOA record detection.
    .OUTPUTS
        [hashtable] Provider information or null if no match found.
#>
function Get-ProviderFromSOA
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain
    )

    try
    {
        $soaRecord = Resolve-DnsName -Name $Domain -Type SOA -ErrorAction Stop
        $primaryNS = $soaRecord.PrimaryServer
        Write-Debug "SOA primary server: $primaryNS"

        # Use the same pattern matching logic as NS records
        return Get-ProviderFromNSRecord -NSRecords @($primaryNS)
    } catch
    {
        Write-Debug "SOA detection failed for $Domain`: $($_)"
        return $null
    }
}

# Export functions
Export-ModuleMember -Function Get-DNSProvider, Get-ProviderFromNSRecord, Get-ProviderFromSOA
