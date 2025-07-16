# Core/Helpers.ps1
<#
    .SYNOPSIS
        Helper functions shared across the utility.
#>
#region Core Utility Functions
# Retry operations with exponential backoff
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [Parameter()]
        [int]$MaxAttempts = 5,
        [Parameter()]
        [int]$InitialDelaySeconds = 2,
        [Parameter()]
        [double]$BackoffMultiplier = 2,
        [Parameter()]
        [string]$OperationName = "Operation",
        [Parameter()]
        [scriptblock]$SuccessCondition = { $true }
    )
    $attempt = 1
    $delay = $InitialDelaySeconds
    while ($attempt -le $MaxAttempts) {
        Write-Debug "Attempt $attempt of $MaxAttempts for $OperationName"
        try {
            $result = & $ScriptBlock
            if (& $SuccessCondition) {
                Write-Debug "$OperationName succeeded on attempt $attempt"
                return $result
            }
            Write-Verbose "$OperationName attempt ${attempt}: Condition not met, retrying..."
        }
        catch {
            Write-Verbose "$OperationName attempt $attempt failed: $($_.Exception.Message)"
        }
        if ($attempt -eq $MaxAttempts) {
            Write-Error -Message "All $MaxAttempts attempts for $OperationName failed"
            throw "Failed to complete $OperationName after $MaxAttempts attempts"
        }
        Write-Debug "Waiting $delay seconds before next attempt"
        Start-Sleep -Seconds $delay
        $delay = [math]::Min($delay * $BackoffMultiplier, 60) # Cap at 60 seconds
        $attempt++
    }
}
# Function for progress reporting
function Write-ProgressHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Activity,
        [Parameter()]
        [string]$Status = "In Progress",
        [Parameter()]
        [int]$PercentComplete,
        [Parameter()]
        [string]$CurrentOperation,
        [Parameter()]
        [int]$StepNumber,
        [Parameter()]
        [int]$TotalSteps
    )
    if ($StepNumber -and $TotalSteps) {
        $PercentComplete = ($StepNumber / $TotalSteps) * 100
    }
    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete -CurrentOperation $CurrentOperation
}
#endregion
#region Validation Functions
# Input validation
function Get-ValidatedInput {
    [CmdletBinding()]
    param (
        [string]$Prompt,
        [int[]]$ValidOptions
    )
    do {
        $formattedPrompt = "${Prompt}: "
        $userInput = Read-Host $formattedPrompt
        if ([int]::TryParse($userInput, [ref]$null) -and $ValidOptions -contains [int]$userInput) {
            return [int]$userInput
        } elseif ($userInput -eq '0') {
            return 0
        } else {
            $validChoices = ($ValidOptions | Sort-Object) -join ', '
            Write-Warning -Message "Please enter a valid option ($validChoices) or 0 to go back."
        }
    } while ($true)
}
# Function to validate file paths
function Test-ValidPath {
    [CmdletBinding()]
    param (
        [string]$Path,
        [switch]$IsDirectory,
        [switch]$MustExist,
        [switch]$MustNotExist,
        [switch]$RequireWrite
    )
    try {
        # Check if path is null or empty
        if ([string]::IsNullOrWhiteSpace($Path)) {
            Write-Warning -Message "Path cannot be empty."
            return $false
        }
        # Check for invalid characters
        $invalidChars = [System.IO.Path]::GetInvalidPathChars()
        if ($Path.IndexOfAny($invalidChars) -ge 0) {
            Write-Warning -Message "Path contains invalid characters."
            return $false
        }
        # Check if the path exists
        if ($MustExist -and -not (Test-Path $Path)) {
            Write-Warning -Message "Path does not exist: $Path"
            return $false
        }
        # Check if the path must not exist
        if ($MustNotExist -and (Test-Path $Path)) {
            Write-Warning -Message "Path already exists: $Path"
            return $false
        }
        # Check if the path is a directory
        if ($IsDirectory -and (Test-Path $Path) -and -not (Test-Path $Path -PathType Container)) {
            Write-Warning -Message "Path is not a directory: $Path"
            return $false
        }
        # Check if the path is a file
        if (-not $IsDirectory -and (Test-Path $Path) -and -not (Test-Path $Path -PathType Leaf)) {
            Write-Warning -Message "Path is not a file: $Path"
            return $false
        }
        # Check if the path is writable
        if ($RequireWrite) {
            $testPath = if ($IsDirectory) { $Path } else { Split-Path -Path $Path -Parent }
            $testFile = [System.IO.Path]::Combine($testPath, [System.IO.Path]::GetRandomFileName())
            try {
                [System.IO.File]::Create($testFile).Dispose()
                [System.IO.File]::Delete($testFile)
            } catch {
                Write-Warning -Message "Path is not writable: $Path"
                return $false
            }
        }
        return $true
    } catch {
        Write-Warning -Message "An error occurred while validating the path: $($_)"
        return $false
    }
}
# Function to validate email addresses
function Test-ValidEmail {
    [CmdletBinding()]
    param (
        [string]$Email
    )
    if ([string]::IsNullOrWhiteSpace($Email)) {
        Write-Warning -Message "Email address cannot be empty."
        return $false
    }
    if ($Email -notmatch '^[\w\.-]+@[\w\.-]+\.\w+$') {
        Write-Warning -Message "Invalid email address format: $Email"
        return $false
    }
    return $true
}
# Function to validate domain names
function Test-ValidDomain {
    [CmdletBinding()]
    param (
        [string]$Domain
    )
    if ([string]::IsNullOrWhiteSpace($Domain)) {
        Write-Warning -Message "Domain name cannot be empty."
        return $false
    }
    if ($Domain -notmatch '^[a-zA-Z0-9.-]+$') {
        Write-Warning -Message "Invalid domain name format: $Domain"
        return $false
    }
    return $true
}
# Function to validate plugin parameters
function Test-PluginParameters {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Plugin,
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )
    $validationRules = @{
        'Cloudflare' = @{
            'CFToken' = '^[a-zA-Z0-9_-]{40,}$'
        }
        'Route53' = @{
            'ProfileName' = '^[a-zA-Z0-9_-]+$'
            'AccessKey' = '^[A-Z0-9]{20}$'
            'SecretKey' = '^[a-zA-Z0-9/+]{40}$'
        }
        'Azure' = @{
            'SubscriptionId' = '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
            'TenantId' = '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
        }
    }
    if (-not $validationRules.ContainsKey($Plugin)) {
        Write-Debug "No validation rules defined for plugin: $Plugin"
        return $true
    }
    $rules = $validationRules[$Plugin]
    $isValid = $true
    foreach ($param in $Parameters.GetEnumerator()) {
        if ($rules.ContainsKey($param.Key)) {
            if ($param.Value -notmatch $rules[$param.Key]) {
                Write-Error -Message "Invalid format for $($param.Key) in $Plugin plugin"
                $isValid = $false
            }
        }
    }
    return $isValid
}
#endregion
#region Configuration Management
# Function to get script settings
function Get-ScriptSettings {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$SettingsPath = "$env:LOCALAPPDATA\PoshACME\script_settings.json"
    )
    if (Test-Path $SettingsPath) {
        try {
            $settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
            return $settings
        } catch {
            Write-Warning -Message "Failed to load settings: $($_)"
            Write-Log "Failed to load settings: $($_)" -Level 'Warning'
        }
    }
    # Return default settings
    return @{
        DefaultDNSPlugin = 'Manual'
        CloudflareToken = $null
        AWSProfile = ''
        AzureSubscriptionId = ''
        AzureTenantId = ''
        LastUsedEmail = ''
        DefaultCertPath = [Environment]::GetFolderPath("Desktop")
        AlwaysExportable = $true
        PreferredInstallLocation = 'ManagementServer'
        DefaultPEMLocation = ''
        DefaultPFXLocation = [Environment]::GetFolderPath("Desktop")
    }
}
# Function to save script settings
function Save-ScriptSettings {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Settings,
        [Parameter()]
        [string]$SettingsPath = "$env:LOCALAPPDATA\PoshACME\script_settings.json"
    )
    try {
        # Ensure directory exists
        $settingsDir = Split-Path -Path $SettingsPath -Parent
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }
        $Settings | ConvertTo-Json | Set-Content -Path $SettingsPath
        return $true
    } catch {
        Write-Warning -Message "Failed to save settings: $($_)"
        Write-Log "Failed to save settings: $($_)" -Level 'Warning'
        return $false
    }
}
#endregion
#region Credential Management
# Function to store credentials
function Set-SecureCredential {
    [CmdletBinding()]
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
        $msg = "Failed to save credentials for ${ProviderName} to '$credPath': $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'
    }
}
# Function to retrieve credentials
function Get-SecureCredential {
    [CmdletBinding()]
    param (
        [string]$ProviderName
    )
    $credPath = "$env:APPDATA\PoshACME\Creds\$ProviderName.cred"
    if (Test-Path $credPath) {
        try {
            $cred = Import-Clixml -Path $credPath
            if ($null -eq $cred) { return $null }
            return $cred
        } catch {
            $msg = "Failed to import credentials for ${ProviderName} from '$credPath': $($_.Exception.Message)"
            Write-Error -Message $msg
            Write-Log $msg -Level 'Error'
            return $null
        }
    }
    return $null
}
#endregion
# Confirm an action with a Y/N
function Confirm-Action {
    [CmdletBinding()]
    param (
        [string]$Message
    )
    $response = Read-Host "$Message (Y/N)"
    return $response -match '^[Yy]$'
}
# Base domain detection using public suffix list
function Get-BaseDomain {
    [CmdletBinding()]
    param (
        [string]$domainName,
        [string[]]$Suffixes
    )
    if ([string]::IsNullOrWhiteSpace($domainName)) {
        Write-Warning -Message "Domain name is empty."
        return $null
    }
    if ($null -eq $Suffixes -or $Suffixes.Count -eq 0) {
        Write-Warning -Message "Suffixes list is empty."
        return $domainName
    }
    $domainLabels = $domainName.ToLower().Split('.')
    for ($i = 0; $i -lt $domainLabels.Length; $i++) {
        $candidate = ($domainLabels[$i..($domainLabels.Length - 1)] -join '.')
        if ($Suffixes -contains $candidate) {
            if ($i -gt 0) {
                $registeredDomain = ($domainLabels[($i - 1)..($domainLabels.Length - 1)] -join '.')
                return $registeredDomain
            } else {
                return $domainName
            }
        }
    }
    return $domainName
}
# Get next file version from Recording Server certificate folder
function Get-NextFileVersion {
    [CmdletBinding()]
    param(
        [string]$folderPath,
        [string]$baseName, # 'cert' or 'pvkey'
        [string]$extension = ".pem"
    )
    $latestVersion = -1
    $files = Get-ChildItem -Path $folderPath -Filter "$baseName*${extension}"
    foreach ($file in $files) {
        if ($file.Name -match "${baseName}(\d+)$extension") {
            [int]$versionNumber = $Matches[1]
            if ($versionNumber -gt $latestVersion) {
                $latestVersion = $versionNumber
            }
        }
    }
    return ($latestVersion + 1).ToString("D3")
}
# Get Recording Server certificate folder path
function Get-RSCertFolder {
    [CmdletBinding()]
    param ()
    $certFolderPaths = @(
        "C:\Program Files\Salient Security Platform\CompleteView 2020\Recording Server\Certificates",
        "C:\Program Files\Salient Security Platform\CompleteView\Recording Server\Certificates"
    )
    foreach ($path in $certFolderPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    Write-Error -Message "Failed to find any predefined certificate folders."
    Write-Log "Failed to find any predefined certificate folders." -Level 'Error'
    return $null
}
# Save PEM files with auto-versioning and retry logic
function Save-PEMFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$directory,
        [Parameter(Mandatory = $true)]
        [string]$certContent,
        [Parameter(Mandatory = $true)]
        [string]$keyContent,
        [Parameter()]
        [switch]$NoVersioning
    )
    Write-Debug "Saving PEM files to $directory"
    if (-not (Test-Path $directory)) {
        $msg = "Certificate directory does not exist: '$directory'"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'
        return $null
    }
    try {
        # Get next version with retry for file system operations
        if (-not $NoVersioning) {
            $certVersion = Invoke-WithRetry -ScriptBlock {
                Get-NextFileVersion -folderPath $directory -baseName "cert"
            } -MaxAttempts 3 -InitialDelaySeconds 1 `
              -OperationName "Version number generation"
            $certOutputFile = Join-Path -Path $directory -ChildPath ("cert" + $certVersion + ".pem")
            $keyOutputFile = Join-Path -Path $directory -ChildPath ("pvkey" + $certVersion + ".pem")
        } else {
            $certOutputFile = Join-Path -Path $directory -ChildPath "cert.pem"
            $keyOutputFile = Join-Path -Path $directory -ChildPath "pvkey.pem"
        }
        # Save files with retry for locked files
        Invoke-WithRetry -ScriptBlock {
            Set-Content -Path $certOutputFile -Value $certContent -Encoding ascii -ErrorAction Stop
            Set-Content -Path $keyOutputFile -Value $keyContent -Encoding ascii -ErrorAction Stop
        } -MaxAttempts 5 -InitialDelaySeconds 2 `
          -OperationName "PEM file save" `
          -SuccessCondition { Test-Path $certOutputFile -and Test-Path $keyOutputFile }
        return @{
            CertFile = $certOutputFile
            KeyFile = $keyOutputFile
        }
    } catch {
        $msg = "Failed to save PEM files to '$directory' after multiple attempts. Certificate: '$certOutputFile', Key: '$keyOutputFile'. Error: $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'
        throw
    }
}
# Path to the file storing revoked certificates
$script:RevokedCertsFile = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Posh-ACME\revoked_certs.json"
# Load revoked certificates
function Get-RevokedCertificates {
    [CmdletBinding()]
    param ()
    if (Test-Path $script:RevokedCertsFile) {
        try {
            $revokedCerts = Get-Content $script:RevokedCertsFile | ConvertFrom-Json
        } catch {
            Write-Warning -Message "Failed to load revoked certificates: $($_)"
            Write-Log "Failed to load revoked certificates: $($_)" -Level 'Warning'
            $revokedCerts = @()
        }
    } else {
        $revokedCerts = @()
    }
    return $revokedCerts
}
# Save revoked certificates
function Save-RevokedCertificates {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$revokedCerts
    )
    try {
        # Ensure directory exists
        $revokedDir = Split-Path -Path $script:RevokedCertsFile -Parent
        if (-not (Test-Path $revokedDir)) {
            New-Item -ItemType Directory -Path $revokedDir -Force | Out-Null
        }
        $revokedCerts | ConvertTo-Json | Set-Content -Path $script:RevokedCertsFile
    } catch {
        Write-Warning -Message "Failed to save revoked certificates: $($_)"
        Write-Log "Failed to save revoked certificates: $($_)" -Level 'Warning'
    }
}

