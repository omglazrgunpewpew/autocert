# Core/RenewalConfig.ps1
<#
    .SYNOPSIS
        Renewal configuration management with randomization and scheduling.
#>
#region Renewal Configuration Management
# Function to get renewal configuration
function Get-RenewalConfig {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$ConfigPath = "$env:LOCALAPPDATA\PoshACME\renewal_config.json"
    )
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath | ConvertFrom-Json
            return $config
        } catch {
            Write-Warning -Message "Failed to load renewal configuration: $($_)"
            Write-Log "Failed to load renewal configuration: $($_)" -Level 'Warning'
        }
    }
    # Return default configuration with randomization
    return @{
        RenewalHour = 2  # 2 AM
        RenewalMinute = (Get-Random -Minimum 0 -Maximum 59)  # Random minute
        UseRandomization = $true
        RandomizationWindow = 60  # minutes
        RenewalThresholdDays = 30  # Renew 30 days before expiry
        MaxRetries = 3
        RetryDelayMinutes = 15
        EmailNotifications = $false
        NotificationEmail = ""
        LogRetention = 30  # days
        HealthCheckEnabled = $true
    }
}
# Function to save renewal configuration
function Save-RenewalConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter()]
        [string]$ConfigPath = "$env:LOCALAPPDATA\PoshACME\renewal_config.json"
    )
    try {
        # Ensure directory exists
        $configDir = Split-Path -Path $ConfigPath -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        $Config | ConvertTo-Json | Set-Content -Path $ConfigPath
        Write-Log "Renewal configuration saved to $ConfigPath"
        return $true
    } catch {
        $msg = "Failed to save renewal configuration to '$ConfigPath': $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'
        return $false
    }
}
# Function to create scheduled task
function New-RenewalScheduledTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )
    $taskName = "Posh-ACME Certificate Renewal"
    try {
        # Calculate trigger time with randomization
        $baseTime = [DateTime]::Today.AddHours($Config.RenewalHour).AddMinutes($Config.RenewalMinute)
        # Create scheduled task action with parameters
        $actionArgs = @(
            "-NoProfile",
            "-WindowStyle Hidden",
            "-ExecutionPolicy Bypass",
            "-File `"$ScriptPath`"",
            "-RenewAll",
            "-NonInteractive"
        )
        $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument ($actionArgs -join ' ')
        # Create trigger with randomization if enabled
        $trigger = New-ScheduledTaskTrigger -Daily -At $baseTime
        if ($Config.UseRandomization -and $Config.RandomizationWindow -gt 0) {
            $trigger.RandomDelay = [TimeSpan]::FromMinutes($Config.RandomizationWindow)
        }
        # Task settings
        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -RunOnlyIfNetworkAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
            -RestartCount $Config.MaxRetries `
            -RestartInterval (New-TimeSpan -Minutes $Config.RetryDelayMinutes)
        # Use SYSTEM account for reliability
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        # Create and register task
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
        Register-ScheduledTask -TaskName $taskName -InputObject $task -Force
        # Verify task creation
        $registeredTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($registeredTask) {
            Write-Information -MessageData "Scheduled task '$taskName' created." -InformationAction Continue
            Write-Host -Object "Base run time: $($baseTime.ToString('HH:mm'))" -ForegroundColor Cyan
            if ($Config.UseRandomization) {
                Write-Host -Object "Random delay window: $($Config.RandomizationWindow) minutes" -ForegroundColor Cyan
            }
            Write-Log "Scheduled task '$taskName' created with base time $($baseTime.ToString('HH:mm'))"
            return $true
        } else {
            throw "Task was not created"
        }
    } catch {
        $msg = "Failed to create scheduled task '$taskName': $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'
        return $false
    }
}
# Function to validate renewal configuration
function Test-RenewalConfig {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Config
    )
    $isValid = $true
    $issues = @()
    # Validate hour (0-23)
    if ($Config.RenewalHour -lt 0 -or $Config.RenewalHour -gt 23) {
        $isValid = $false
        $issues += "RenewalHour must be between 0 and 23"
    }
    # Validate minute (0-59)
    if ($Config.RenewalMinute -lt 0 -or $Config.RenewalMinute -gt 59) {
        $isValid = $false
        $issues += "RenewalMinute must be between 0 and 59"
    }
    # Validate randomization window
    if ($Config.UseRandomization -and ($Config.RandomizationWindow -lt 0 -or $Config.RandomizationWindow -gt 1440)) {
        $isValid = $false
        $issues += "RandomizationWindow must be between 0 and 1440 minutes"
    }
    # Validate renewal threshold
    if ($Config.RenewalThresholdDays -lt 1 -or $Config.RenewalThresholdDays -gt 90) {
        $isValid = $false
        $issues += "RenewalThresholdDays must be between 1 and 90"
    }
    # Validate email if notifications enabled
    if ($Config.EmailNotifications -and -not (Test-ValidEmail -Email $Config.NotificationEmail)) {
        $isValid = $false
        $issues += "Valid NotificationEmail required when EmailNotifications is enabled"
    }
    if (-not $isValid) {
        Write-Warning -Message "Renewal configuration validation failed:"
        $issues | ForEach-Object { Write-Warning -Message "  - $_" }
    }
    return $isValid
}
# Function to get renewal status for all certificates
function Get-CertificateRenewalStatus {
    [CmdletBinding()]
    param (
        [Parameter()]
        [object]$Config = (Get-RenewalConfig)
    )
    $orders = Get-PAOrder
    $renewalInfo = @()
    foreach ($order in $orders) {
        try {
            $cert = Get-CachedPACertificate -MainDomain $order.MainDomain
            if ($cert -and $cert.Certificate) {
                $daysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                $needsRenewal = $daysUntilExpiry -le $Config.RenewalThresholdDays
                $status = @{
                    Domain = $order.MainDomain
                    ExpiryDate = $cert.Certificate.NotAfter
                    DaysUntilExpiry = $daysUntilExpiry
                    NeedsRenewal = $needsRenewal
                    Status = if ($needsRenewal) { "Renewal Required" } else { "Valid" }
                    Thumbprint = $cert.Certificate.Thumbprint
                }
                $renewalInfo += $status
            }
        } catch {
            Write-Warning -Message "Failed to get renewal status for $($order.MainDomain): $_"
        }
    }
    return $renewalInfo
}
# Function to send renewal notifications (placeholder for email integration)
function Send-RenewalNotification {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        [Parameter(Mandatory = $true)]
        [string]$Body,
        [Parameter(Mandatory = $true)]
        [string]$ToEmail
    )
    # This is a placeholder - in production you'd integrate with your email system
    Write-Log "Renewal notification: $Subject" -Level 'Info'
    Write-Verbose "Would send email to $ToEmail with subject: $Subject"
    # You could integrate with:
    # - Send-MailMessage (if SMTP is configured)
    # - Microsoft Graph API
    # - SendGrid API
    # - Other email services
}
#endregion


