# Core/CertificateCache.ps1
<#
    .SYNOPSIS
        Certificate caching system.
#>
#region Certificate Cache Functions
# Function to get cache file path
function Get-CacheFilePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MainDomain
    )
    $cacheDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Posh-ACME\cache"
    if (-not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    return Join-Path -Path $cacheDir -ChildPath "$($MainDomain.Replace('*', '_wild_')).json"
}
# Function to get cached certificate
function Get-CachedPACertificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$MainDomain,
        [switch]$Force
    )
    Write-Debug "Attempting to retrieve certificate for $MainDomain"
    $cachePath = Get-CacheFilePath -MainDomain $MainDomain
    if (-not $Force -and (Test-Path $cachePath)) {
        try {
            $cacheData = Get-Content -Path $cachePath -Raw | ConvertFrom-Json
            if ((Get-Date) -lt [DateTime]::Parse($cacheData.ExpiryTime)) {
                Write-Verbose "Retrieved certificate from cache for $MainDomain"
                return $cacheData.Certificate
            }
        } catch {
            Write-Debug "Cache read failed: $($_.Exception.Message)"
        }
    }
    Write-Verbose "Fetching fresh certificate for $MainDomain"
    try {
        $maxAttempts = 3
        $attempt = 1
        $lastError = $null
        while ($attempt -le $maxAttempts) {
            try {
                $cert = Get-PACertificate -MainDomain $MainDomain -ErrorAction Stop
                if ($null -eq $cert) {
                    throw "Get-PACertificate returned null"
                }
                # Save to cache with file lock handling
                $cacheData = @{
                    Certificate = $cert
                    ExpiryTime = (Get-Date).AddMinutes(30).ToString('o')
                }
                Invoke-WithRetry -ScriptBlock {
                    $cacheData | ConvertTo-Json | Set-Content -Path $cachePath -Force
                } -MaxAttempts 3 -InitialDelaySeconds 1 `
                  -OperationName "Cache write for $MainDomain"
                return $cert
            } catch {
                $lastError = $_
                Write-Debug "Attempt $attempt failed: $($_.Exception.Message)"
                $attempt++
                if ($attempt -le $maxAttempts) {
                    Start-Sleep -Seconds (2 * $attempt)
                }
            }
        }
        throw "Failed to retrieve certificate after $maxAttempts attempts: $($lastError.Exception.Message)"
    } catch {
        Write-Error "Critical error retrieving certificate for ${MainDomain}: $($_.Exception.Message)"
        Write-Log "Critical error retrieving certificate for ${MainDomain}: $($_.Exception.Message)" -Level 'Error'
        throw
    }
}
# Function to clear the certificate cache
function Clear-CertificateCache {
    [CmdletBinding()]
    param ()
    Write-Debug "Clearing certificate cache"
    $cacheDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Posh-ACME\cache"
    if (Test-Path $cacheDir) {
        Get-ChildItem -Path $cacheDir -Filter "*.json" | Remove-Item -Force
    }
    Write-Verbose "Certificate cache cleared"
}
# Function to get certificate PEM content
function Get-CertificatePEMContent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Certificate,
        [Parameter()]
        [switch]$IncludeKey
    )
    $result = @{
        CertContent = $null
        KeyContent = $null
        Success = $false
        ErrorMessage = $null
    }
    try {
        # Get certificate content
        if ($Certificate.CertificatePEM) {
            $result.CertContent = Get-Content -Path $Certificate.CertificatePEM -Raw
        } elseif ($Certificate.PEM) {
            $result.CertContent = $Certificate.PEM
        } elseif ($Certificate.CertFile) {
            $result.CertContent = Get-Content -Path $Certificate.CertFile -Raw
        } else {
            throw "Unable to retrieve PEM content from certificate object."
        }
        # Get key content if requested
        if ($IncludeKey) {
            if ($Certificate.KeyFile) {
                $result.KeyContent = Get-Content -Path $Certificate.KeyFile -Raw
            } else {
                throw "Unable to retrieve key content from certificate object."
            }
        }
        $result.Success = $true
    } catch {
        $result.ErrorMessage = $_.Exception.Message
        Write-Error $result.ErrorMessage
        Write-Log $result.ErrorMessage -Level 'Error'
    }
    return $result
}
#endregion