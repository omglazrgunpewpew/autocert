# Core/ConfigurationManager.ps1
<#
    .SYNOPSIS
        Configuration management with validation, backup, and recovery capabilities.
#>
function Get-ConfigurationSchema {
    [CmdletBinding()]
    param()
    return @{
        Version = '2.0.0'
        RequiredProperties = @(
            'RenewalThresholdDays',
            'MaxRetries',
            'RetryDelayMinutes',
            'EmailNotifications',
            'BackupBeforeRenewal'
        )
        DefaultValues = @{
            RenewalThresholdDays = 30
            MaxRetries = 3
            RetryDelayMinutes = 15
            UseRandomization = $true
            RandomizationWindow = 60
            EmailNotifications = $false
            BackupBeforeRenewal = $true
            RollbackOnFailure = $true
            HealthCheckEnabled = $true
            LogRetention = 30
            PreRenewalHooks = @()
            PostRenewalHooks = @()
            FailureHooks = @()
        }
        ValidationRules = @{
            RenewalThresholdDays = @{ Min = 1; Max = 89 }
            MaxRetries = @{ Min = 1; Max = 10 }
            RetryDelayMinutes = @{ Min = 1; Max = 180 }
            RandomizationWindow = @{ Min = 15; Max = 360 }
            LogRetention = @{ Min = 1; Max = 365 }
        }
    }
}
function Test-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )
    $schema = Get-ConfigurationSchema
    $validationErrors = @()
    # Check required properties
    foreach ($property in $schema.RequiredProperties) {
        if (-not $Config.ContainsKey($property)) {
            $validationErrors += "Missing required property: $property"
        }
    }
    # Validate property values
    foreach ($property in $schema.ValidationRules.Keys) {
        if ($Config.ContainsKey($property)) {
            $value = $Config[$property]
            $rules = $schema.ValidationRules[$property]
            if ($rules.Min -and $value -lt $rules.Min) {
                $validationErrors += "$property value ($value) is below minimum ($($rules.Min))"
            }
            if ($rules.Max -and $value -gt $rules.Max) {
                $validationErrors += "$property value ($value) is above maximum ($($rules.Max))"
            }
        }
    }
    return @{
        IsValid = $validationErrors.Count -eq 0
        Errors = $validationErrors
    }
}
function Backup-Configuration {
    [CmdletBinding()]
    param(
        [string]$BackupPath = "$env:LOCALAPPDATA\AutoCert\Backups\Config"
    )
    try {
        if (-not (Test-Path $BackupPath)) {
            New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        }
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = Join-Path $BackupPath "config_backup_$timestamp.json"
        $currentConfig = Get-RenewalConfig
        $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $backupFile
        Write-Log "Configuration backed up to: $backupFile" -Level 'Info'
        return $backupFile
    } catch {
        Write-Log "Failed to backup configuration: $($_.Exception.Message)" -Level 'Error'
        throw
    }
}
function Restore-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupFile
    )
    try {
        if (-not (Test-Path $BackupFile)) {
            throw "Backup file not found: $BackupFile"
        }
        $config = Get-Content $BackupFile | ConvertFrom-Json -AsHashtable
        $validation = Test-Configuration -Config $config
        if (-not $validation.IsValid) {
            throw "Invalid configuration: $($validation.Errors -join ', ')"
        }
        Save-RenewalConfig -Config $config
        Write-Log "Configuration restored from: $BackupFile" -Level 'Info'
        return $true
    } catch {
        Write-Log "Failed to restore configuration: $($_.Exception.Message)" -Level 'Error'
        throw
    }
}
function Initialize-DefaultConfiguration {
    [CmdletBinding()]
    param(
        [switch]$Force
    )
    $configPath = "$env:LOCALAPPDATA\PoshACME\renewal_config.json"
    if ((Test-Path $configPath) -and -not $Force) {
        return Get-RenewalConfig
    }
    $schema = Get-ConfigurationSchema
    $config = $schema.DefaultValues.Clone()
    # Add system-specific randomization
    $config.RenewalMinute = Get-Random -Minimum 0 -Maximum 59
    $config.RenewalHour = Get-Random -Minimum 1 -Maximum 5  # Between 1-5 AM
    Save-RenewalConfig -Config $config
    Write-Log "Default configuration initialized" -Level 'Info'
    return $config
}