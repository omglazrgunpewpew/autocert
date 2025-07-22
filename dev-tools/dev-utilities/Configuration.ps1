# Configuration Management Functions
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 21, 2025

<#
.SYNOPSIS
    Configuration management functions for AutoCert system
.DESCRIPTION
    Provides centralized configuration management including settings validation,
    default values, and configuration file handling.
.NOTES
    This file contains configuration-related helper functions
#>

function Get-AutoCertConfiguration
{
    [CmdletBinding()]
    param()

    try
    {
        $configPath = Join-Path $env:LOCALAPPDATA "AutoCert\config.json"

        if (Test-Path $configPath)
        {
            $config = Get-Content $configPath | ConvertFrom-Json
            Write-Log "Loaded configuration from: $configPath" -Level 'Info'
            return $config
        } else
        {
            Write-Log "Configuration file not found, using defaults" -Level 'Info'
            return Get-DefaultConfiguration
        }
    } catch
    {
        Write-Log "Failed to load configuration: $($_.Exception.Message)" -Level 'Warning'
        return Get-DefaultConfiguration
    }
}

function Set-AutoCertConfiguration
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Configuration
    )

    try
    {
        $configPath = Join-Path $env:LOCALAPPDATA "AutoCert\config.json"
        $configDir = Split-Path $configPath

        if (-not (Test-Path $configDir))
        {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }

        if ($PSCmdlet.ShouldProcess($configPath, "Save configuration"))
        {
            $Configuration | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
            Write-Log "Configuration saved to: $configPath" -Level 'Info'
            return $true
        }
    } catch
    {
        Write-Log "Failed to save configuration: $($_.Exception.Message)" -Level 'Error'
        return $false
    }
}

function Get-DefaultConfiguration
{
    [CmdletBinding()]
    param()

    return @{
        General       = @{
            AutoRenewalEnabled = $true
            RenewalDaysBefore  = 30
            DefaultKeySize     = 2048
            PreferredChain     = ""
            LogLevel           = "Info"
        }
        Notifications = @{
            EmailEnabled = $false
            EmailTo      = @()
            EmailFrom    = ""
            SMTPServer   = ""
            SMTPPort     = 587
            UseTLS       = $true
        }
        Backup        = @{
            Enabled       = $true
            RetentionDays = 90
            BackupPath    = ""
        }
        DNS           = @{
            DefaultProvider = "Manual"
            TimeoutSeconds  = 300
            RetryAttempts   = 3
        }
        Security      = @{
            RequireSecurePasswords = $true
            EncryptCredentials     = $true
            AuditLogging           = $true
        }
    }
}

function Test-ConfigurationValid
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Configuration
    )

    $isValid = $true
    $errors = @()

    # Validate general settings
    if ($Configuration.General.RenewalDaysBefore -lt 1 -or $Configuration.General.RenewalDaysBefore -gt 89)
    {
        $errors += "RenewalDaysBefore must be between 1 and 89 days"
        $isValid = $false
    }

    if ($Configuration.General.DefaultKeySize -notin @(2048, 3072, 4096))
    {
        $errors += "DefaultKeySize must be 2048, 3072, or 4096"
        $isValid = $false
    }

    # Validate email settings if enabled
    if ($Configuration.Notifications.EmailEnabled)
    {
        if (-not $Configuration.Notifications.EmailTo -or $Configuration.Notifications.EmailTo.Count -eq 0)
        {
            $errors += "EmailTo is required when email notifications are enabled"
            $isValid = $false
        }

        if (-not $Configuration.Notifications.SMTPServer)
        {
            $errors += "SMTPServer is required when email notifications are enabled"
            $isValid = $false
        }
    }

    return @{
        IsValid = $isValid
        Errors  = $errors
    }
}

# Export functions for dot-sourcing
# Note: Functions are available globally due to dot-sourcing architecture
