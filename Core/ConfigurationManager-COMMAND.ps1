# Core/ConfigurationManager.ps1
<#
    .SYNOPSIS
        Configuration management with validation, backup, and recovery capabilities.
#>

# Helper function to ensure directory exists
function Initialize-Directory
{
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path))
    {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Helper function to handle configuration errors
function Write-ConfigurationError
{
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $fullMessage = "$Message`: $($ErrorRecord.Exception.Message)"
    Write-AutoCertLog $fullMessage -Level 'Error'
}

# Helper function to convert PSCustomObject to hashtable (PowerShell 5.1 compatibility)
function ConvertTo-Hashtable
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$InputObject
    )

    $hashtable = @{}
    $InputObject.PSObject.Properties | ForEach-Object {
        $value = $_.Value
        if ($value -is [PSCustomObject])
        {
            $value = ConvertTo-Hashtable -InputObject $value
        } elseif ($value -is [Array])
        {
            $value = $value | ForEach-Object {
                if ($_ -is [PSCustomObject])
                {
                    ConvertTo-Hashtable -InputObject $_
                } else
                {
                    $_
                }
            }
        }
        $hashtable[$_.Name] = $value
    }
    return $hashtable
}

function Get-ConfigurationSchema
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    return @{
        Version            = '2.0.0'
        RequiredProperties = @(
            'RenewalThresholdDays',
            'MaxRetries',
            'RetryDelayMinutes',
            'EmailNotifications',
            'BackupBeforeRenewal'
        )
        DefaultValues      = @{
            RenewalThresholdDays = 30
            MaxRetries           = 3
            RetryDelayMinutes    = 15
            UseRandomization     = $true
            RandomizationWindow  = 60
            EmailNotifications   = $false
            BackupBeforeRenewal  = $true
            RollbackOnFailure    = $true
            HealthCheckEnabled   = $true
            LogRetention         = 30
            PreRenewalHooks      = @()
            PostRenewalHooks     = @()
            FailureHooks         = @()
        }
        ValidationRules    = @{
            RenewalThresholdDays = @{ Min = 1; Max = 89; Type = 'int' }
            MaxRetries           = @{ Min = 1; Max = 10; Type = 'int' }
            RetryDelayMinutes    = @{ Min = 1; Max = 180; Type = 'int' }
            RandomizationWindow  = @{ Min = 15; Max = 360; Type = 'int' }
            LogRetention         = @{ Min = 1; Max = 365; Type = 'int' }
        }
    }
}
function Test-Configuration
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $schema = Get-ConfigurationSchema
    $validationErrors = @()
    # Check required properties
    foreach ($property in $schema.RequiredProperties)
    {
        if (-not $Config.ContainsKey($property))
        {
            $validationErrors += "Missing required property: $property"
        }
    }
    # Validate property values
    foreach ($property in $schema.ValidationRules.Keys)
    {
        if ($Config.ContainsKey($property))
        {
            $value = $Config[$property]
            $rules = $schema.ValidationRules[$property]

            # Type validation
            if ($rules.Type)
            {
                $expectedType = switch ($rules.Type)
                {
                    'int' { [int] }
                    'bool' { [bool] }
                    'string' { [string] }
                    default { [object] }
                }

                if ($value -isnot $expectedType)
                {
                    $validationErrors += "$property must be of type $($rules.Type), but got $($value.GetType().Name)"
                    continue
                }
            }

            # Numeric range validation
            if ($rules.Min -and $value -lt $rules.Min)
            {
                $validationErrors += "$property value ($value) is below minimum ($($rules.Min))"
            }
            if ($rules.Max -and $value -gt $rules.Max)
            {
                $validationErrors += "$property value ($value) is above maximum ($($rules.Max))"
            }
        }
    }
    return @{
        IsValid = $validationErrors.Count -eq 0
        Errors  = $validationErrors
    }
}
function Backup-Configuration
{
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$BackupPath = "$env:LOCALAPPDATA\AutoCert\Backups\Config"
    )
    try
    {
        Initialize-Directory -Path $BackupPath

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = Join-Path $BackupPath "config_backup_$timestamp.json"
        $currentConfig = Get-RenewalConfig
        $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile
        Write-AutoCertLog "Configuration backed up to: $backupFile" -Level 'Info'
        return $backupFile
    } catch
    {
        Write-ConfigurationError -Message "Failed to backup configuration" -ErrorRecord $_
        throw
    }
}
function Restore-Configuration
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$BackupFile
    )
    try
    {
        if (-not (Test-Path $BackupFile))
        {
            throw "Backup file not found: $BackupFile"
        }

        # Read and convert JSON with PowerShell 5.1 compatibility
        $jsonContent = Get-Content $BackupFile -Raw
        $configObject = ConvertFrom-Json $jsonContent
        $config = ConvertTo-Hashtable -InputObject $configObject
        $validation = Test-Configuration -Config $config
        if (-not $validation.IsValid)
        {
            throw "Invalid configuration: $($validation.Errors -join ', ')"
        }
        Save-RenewalConfig -Config $config
        Write-AutoCertLog "Configuration restored from: $BackupFile" -Level 'Info'
        return $true
    } catch
    {
        Write-ConfigurationError -Message "Failed to restore configuration" -ErrorRecord $_
        throw
    }
}
function Initialize-DefaultConfiguration
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [switch]$Force
    )
    $configPath = "$env:LOCALAPPDATA\PoshACME\renewal_config.json"
    if ((Test-Path $configPath) -and -not $Force)
    {
        return Get-RenewalConfig
    }
    $schema = Get-ConfigurationSchema
    $config = $schema.DefaultValues.Clone()
    # Add system-specific randomization
    $config.RenewalMinute = Get-Random -Minimum 0 -Maximum 59
    $config.RenewalHour = Get-Random -Minimum 1 -Maximum 5  # Between 1-5 AM
    Save-RenewalConfig -Config $config
    Write-AutoCertLog "Default configuration initialized" -Level 'Info'
    return $config
}
