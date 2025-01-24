<#
    .SYNOPSIS
        Helper functions shared across the script.
#>

# Provide a single place for our input validation logic
function Get-ValidatedInput {
    param (
        [string]$Prompt,
        [int[]]$ValidOptions
    )
    do {
        $userInput = Read-Host $Prompt
        if ([int]::TryParse($userInput, [ref]$null) -and $ValidOptions -contains [int]$userInput) {
            return [int]$userInput
        } elseif ($userInput -eq '0') {
            return 0
        } else {
            Write-Host "Invalid selection. Please choose $($ValidOptions -join ', ') or 0 to go back." -ForegroundColor Yellow
        }
    } while ($true)
}

# Confirm an action with a Y/N
function Confirm-Action {
    param (
        [string]$Message
    )
    $response = Read-Host $Message
    return $response -match '^(Y|y)$'
}

# Securely store and retrieve credentials
function Get-SecureCredential {
    param (
        [string]$ProviderName
    )
    $credPath = "$env:APPDATA\PoshACME\Creds\$ProviderName.cred"
    if (Test-Path $credPath) {
        try {
            return Import-Clixml -Path $credPath
        } catch {
            Write-Host "Failed to import credentials for ${ProviderName}: $($_)" -ForegroundColor Red
            Write-Log "Failed to import credentials for ${ProviderName}: $($_)" -Level 'Error'
            return $null
        }
    } else {
        return $null
    }
}

function Set-SecureCredential {
    param (
        [string]$ProviderName,
        [pscredential]$Credential
    )
    $credDir = "$env:APPDATA\PoshACME\Creds"
    if (-not (Test-Path $credDir)) {
        New-Item -ItemType Directory -Path $credDir -Force | Out-Null
    }
    $credPath = "$credDir\$ProviderName.cred"
    try {
        $Credential | Export-Clixml -Path $credPath
    } catch {
        Write-Host "Failed to save credentials for ${ProviderName}: $($_)" -ForegroundColor Red
        Write-Log "Failed to save credentials for ${ProviderName}: $($_)" -Level 'Error'
    }
}

# Instead of manual PSL logic, rely on Posh-ACME's built-in domain detection
function Get-BaseDomain {
    param(
        [string]$domainName
    )
    if (-not $domainName) {
        Write-Host "Domain name is empty." -ForegroundColor Yellow
        return $null
    }

    try {
        return (Get-PARegisteredDomain $domainName)
    } catch {
        Write-Host "Failed to detect base domain for '$domainName': $($_)" -ForegroundColor Yellow
        return $domainName
    }
}

# Some short utility for reading the next file version in a directory
function Get-NextFileVersion {
    param(
        [string]$folderPath,
        [string]$baseName,
        [string]$extension = ".pem"
    )
    $latestVersion = -1
    Get-ChildItem -Path $folderPath -Filter "$baseName*${extension}" |
    ForEach-Object {
        if ($_.Name -match "${baseName}(\d+)$extension") {
            [int]$versionNumber = $Matches[1]
            if ($versionNumber -gt $latestVersion) {
                $latestVersion = $versionNumber
            }
        }
    }
    return ($latestVersion + 1).ToString("D3")
}

# Get the Recording Server certificate folder path
function Get-RSCertFolder {
    $certFolderPaths = @(
        "C:\Program Files\Salient Security Platform\CompleteView 2020\Recording Server\Certificates",
        "C:\Program Files\Salient Security Platform\CompleteView\Recording Server\Certificates"
    )
    foreach ($path in $certFolderPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    Write-Host "Failed to find any predefined certificate folders." -ForegroundColor Red
    Write-Log "Failed to find any predefined certificate folders." -Level 'Error'
    return $null
}

# Save PEM files with auto-versioning
function Save-PEMFiles {
    param(
        [string]$directory,
        [string]$certContent,
        [string]$keyContent,
        [bool]$autoVersioning = $true
    )

    if (-not (Test-Path $directory)) {
        Write-Host "The specified directory does not exist: $directory" -ForegroundColor Red
        Write-Log "The specified directory does not exist: $directory" -Level 'Error'
        return $null
    }

    if ($autoVersioning) {
        $certVersion   = Get-NextFileVersion -folderPath $directory -baseName "cert"
        $certOutputFile = Join-Path -Path $directory -ChildPath ("cert" + $certVersion + ".pem")
        $keyOutputFile  = Join-Path -Path $directory -ChildPath ("pvkey" + $certVersion + ".pem")
    }
    else {
        $certOutputFile = Join-Path -Path $directory -ChildPath "cert.pem"
        $keyOutputFile  = Join-Path -Path $directory -ChildPath "pvkey.pem"
    }

    try {
        Set-Content -Path $certOutputFile -Value $certContent -Encoding ascii
        Set-Content -Path $keyOutputFile  -Value $keyContent  -Encoding ascii
    } catch {
        Write-Host "Failed to save PEM files: $($_)" -ForegroundColor Red
        Write-Log "Failed to save PEM files: $($_)" -Level 'Error'
        return $null
    }

    return @{
        CertFile = $certOutputFile
        KeyFile  = $keyOutputFile
    }
}

# Path to the file storing revoked certificates
$script:RevokedCertsFile = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Posh-ACME\revoked_certs.json"

# Load revoked certificates
function Get-RevokedCertificates {
    if (Test-Path $script:RevokedCertsFile) {
        try {
            return Get-Content $script:RevokedCertsFile | ConvertFrom-Json
        } catch {
            Write-Host "Failed to load revoked certificates: $($_)" -ForegroundColor Yellow
            Write-Log "Failed to load revoked certificates: $($_)" -Level 'Warning'
            return @()
        }
    } else {
        return @()
    }
}

# Save revoked certificates
function Save-RevokedCertificates($revokedCerts) {
    try {
        $revokedCerts | ConvertTo-Json | Set-Content -Path $script:RevokedCertsFile
    } catch {
        Write-Host "Failed to save revoked certificates: $($_)" -ForegroundColor Yellow
        Write-Log "Failed to save revoked certificates: $($_)" -Level 'Warning'
    }
}
