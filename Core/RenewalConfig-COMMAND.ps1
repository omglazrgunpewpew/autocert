# Core/RenewalConfig.ps1
<#
    .SYNOPSIS
        Renewal configuration management with randomization and scheduling.
#>
#region Renewal Configuration Management

# Helper function to handle standard error logging
function Write-RenewalError
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
    Write-Error -Message $fullMessage
    Write-AutoCertLog $fullMessage -Level 'Error'
}

# Helper function to ensure configuration directory exists
function Initialize-ConfigDirectory
{
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $configDir = Split-Path -Path $ConfigPath -Parent
    if (-not (Test-Path $configDir))
    {
        Initialize-ConfigDirectory -Path $configDir
    }
    return $configDir
}

# Function to get renewal configuration
function Get-RenewalConfig
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter()]
        [string]$ConfigPath = "$env:LOCALAPPDATA\PoshACME\renewal_config.json"
    )
    if (Test-Path $ConfigPath)
    {
        try
        {
            $config = Get-Content $ConfigPath | ConvertFrom-Json
            return $config
        } catch
        {
            Write-Warning -Message "Failed to load renewal configuration: $($_)"
            Write-AutoCertLog "Failed to load renewal configuration: $($_)" -Level 'Warning'
        }
    }
    # Return default configuration with randomization
    return @{
        RenewalHour          = 2  # 2 AM
        RenewalMinute        = (Get-Random -Minimum 0 -Maximum 59)  # Random minute
        UseRandomization     = $true
        RandomizationWindow  = 60  # minutes
        RenewalThresholdDays = 30  # Renew 30 days before expiry
        MaxRetries           = 3
        RetryDelayMinutes    = 15
        EmailNotifications   = $false
        NotificationEmail    = ""
        LogRetention         = 30  # days
        HealthCheckEnabled   = $true
    }
}
# Function to save renewal configuration
function Save-RenewalConfig
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter()]
        [string]$ConfigPath = "$env:LOCALAPPDATA\PoshACME\renewal_config.json"
    )
    try
    {
        # Ensure directory exists
        Initialize-ConfigDirectory -ConfigPath $ConfigPath
        $Config | ConvertTo-Json | Set-Content -Path $ConfigPath
        Write-AutoCertLog "Renewal configuration saved to $ConfigPath"
        return $true
    } catch
    {
        Write-RenewalError -Message "Failed to save renewal configuration to '$ConfigPath'" -ErrorRecord $_
        return $false
    }
}
# Function to create scheduled task
function New-RenewalScheduledTask
{
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )
    $taskName = "Posh-ACME Certificate Renewal"
    try
    {
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
        if ($Config.UseRandomization -and $Config.RandomizationWindow -gt 0)
        {
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

        if ($PSCmdlet.ShouldProcess($taskName, "Register scheduled task"))
        {
            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force
        } else
        {
            Write-Information -MessageData "Scheduled task registration skipped due to WhatIf parameter" -InformationAction Continue
            return $true
        }
        # Verify task creation
        $registeredTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($registeredTask)
        {
            Write-Information -MessageData "Scheduled task '$taskName' created." -InformationAction Continue
            Write-Information -MessageData "Base run time: $($baseTime.ToString('HH:mm'))" -InformationAction Continue
            if ($Config.UseRandomization)
            {
                Write-Information -MessageData "Random delay window: $($Config.RandomizationWindow) minutes" -InformationAction Continue
            }
            Write-AutoCertLog "Scheduled task '$taskName' created with base time $($baseTime.ToString('HH:mm'))"
            return $true
        } else
        {
            throw "Task was not created"
        }
    } catch
    {
        Write-RenewalError -Message "Failed to create scheduled task '$taskName'" -ErrorRecord $_
        return $false
    }
}
# Function to validate renewal configuration
function Test-RenewalConfig
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [object]$Config
    )
    $isValid = $true
    $issues = @()
    # Validate hour (0-23)
    if ($Config.RenewalHour -lt 0 -or $Config.RenewalHour -gt 23)
    {
        $isValid = $false
        $issues += "RenewalHour must be between 0 and 23"
    }
    # Validate minute (0-59)
    if ($Config.RenewalMinute -lt 0 -or $Config.RenewalMinute -gt 59)
    {
        $isValid = $false
        $issues += "RenewalMinute must be between 0 and 59"
    }
    # Validate randomization window
    if ($Config.UseRandomization -and ($Config.RandomizationWindow -lt 0 -or $Config.RandomizationWindow -gt 1440))
    {
        $isValid = $false
        $issues += "RandomizationWindow must be between 0 and 1440 minutes"
    }
    # Validate renewal threshold
    if ($Config.RenewalThresholdDays -lt 1 -or $Config.RenewalThresholdDays -gt 90)
    {
        $isValid = $false
        $issues += "RenewalThresholdDays must be between 1 and 90"
    }
    # Validate email if notifications enabled
    if ($Config.EmailNotifications -and -not (Test-ValidEmail -Email $Config.NotificationEmail))
    {
        $isValid = $false
        $issues += "Valid NotificationEmail required when EmailNotifications is enabled"
    }
    if (-not $isValid)
    {
        Write-Warning -Message "Renewal configuration validation failed:"
        $issues | ForEach-Object { Write-Warning -Message "  - $_" }
    }
    return $isValid
}
# Function to get renewal status for all certificates
function Get-CertificateRenewalStatus
{
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter()]
        [object]$Config = (Get-RenewalConfig)
    )
    $orders = Get-PAOrder
    $renewalInfo = @()
    foreach ($order in $orders)
    {
        try
        {
            $cert = Get-CachedPACertificate -MainDomain $order.MainDomain
            if ($cert -and $cert.Certificate)
            {
                $daysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                $needsRenewal = $daysUntilExpiry -le $Config.RenewalThresholdDays
                $status = @{
                    Domain          = $order.MainDomain
                    ExpiryDate      = $cert.Certificate.NotAfter
                    DaysUntilExpiry = $daysUntilExpiry
                    NeedsRenewal    = $needsRenewal
                    Status          = if ($needsRenewal) { "Renewal Required" } else { "Valid" }
                    Thumbprint      = $cert.Certificate.Thumbprint
                }
                $renewalInfo += $status
            }
        } catch
        {
            Write-Warning -Message "Failed to get renewal status for $($order.MainDomain): $_"
        }
    }
    return $renewalInfo
}
# Function to send renewal notifications (placeholder for email integration)
function Send-RenewalNotification
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        [Parameter(Mandatory = $true)]
        [string]$Body,
        [Parameter(Mandatory = $true)]
        [string]$ToEmail,
        [Parameter()]
        [string]$FromEmail,
        [Parameter()]
        [string]$SmtpServer,
        [Parameter()]
        [int]$SmtpPort = 587,
        [Parameter()]
        [bool]$UseSsl = $true,
        [Parameter()]
        [pscredential]$SmtpCredential,
        [Parameter()]
        [ValidateSet('Success', 'Warning', 'Error', 'Info')]
        [string]$Priority = 'Info'
    )

    Write-AutoCertLog "Attempting to send email notification: $Subject" -Level 'Info'

    try
    {
        # Get notification configuration
        $config = Get-RenewalConfig
        if (-not $config.EmailNotifications)
        {
            Write-AutoCertLog "Email notifications are disabled in configuration" -Level 'Warning'
            return $false
        }

        # Load SMTP configuration from secure storage or config
        $smtpConfig = Get-SmtpConfiguration
        if (-not $smtpConfig)
        {
            Write-AutoCertLog "SMTP configuration not found. Please run Set-SmtpConfiguration first." -Level 'Error'
            return $false
        }

        # Use provided parameters or fall back to stored configuration
        $actualFromEmail = if ($FromEmail) { $FromEmail } else { $smtpConfig.FromEmail }
        $actualSmtpServer = if ($SmtpServer) { $SmtpServer } else { $smtpConfig.SmtpServer }
        $actualSmtpPort = if ($SmtpPort -ne 587) { $SmtpPort } else { $smtpConfig.SmtpPort }
        $actualUseSsl = if ($PSBoundParameters.ContainsKey('UseSsl')) { $UseSsl } else { $smtpConfig.UseSsl }
        $actualCredential = if ($SmtpCredential) { $SmtpCredential } else { $smtpConfig.Credential }

        # Validate required parameters
        if (-not $actualFromEmail -or -not $actualSmtpServer)
        {
            Write-AutoCertLog "Missing required SMTP configuration (FromEmail or SmtpServer)" -Level 'Error'
            return $false
        }

        # Prepare email parameters
        $mailParams = @{
            To         = $ToEmail
            From       = $actualFromEmail
            Subject    = $Subject
            Body       = $Body
            SmtpServer = $actualSmtpServer
            Port       = $actualSmtpPort
            UseSsl     = $actualUseSsl
        }

        # Add credentials if available
        if ($actualCredential)
        {
            $mailParams.Credential = $actualCredential
        }

        # Set priority based on notification type
        switch ($Priority)
        {
            'Error' { $mailParams.Priority = 'High' }
            'Warning' { $mailParams.Priority = 'Normal' }
            'Success' { $mailParams.Priority = 'Normal' }
            'Info' { $mailParams.Priority = 'Low' }
        }

        # Add HTML formatting if body contains HTML
        if ($Body -match '<[^>]+>')
        {
            $mailParams.BodyAsHtml = $true
        }

        # Send the email
        Send-MailMessage @mailParams -ErrorAction Stop

        Write-AutoCertLog "Email notification sent successfully to $ToEmail" -Level 'Success'
        return $true

    } catch
    {
        Write-RenewalError -Message "Failed to send email notification" -ErrorRecord $_
        return $false
    }
}

# Function to configure SMTP settings
function Set-SmtpConfiguration
{
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SmtpServer,
        [Parameter(Mandatory = $true)]
        [string]$FromEmail,
        [Parameter()]
        [int]$SmtpPort = 587,
        [Parameter()]
        [bool]$UseSsl = $true,
        [Parameter()]
        [pscredential]$Credential,
        [Parameter()]
        [string]$ConfigPath = "$env:LOCALAPPDATA\PoshACME\smtp_config.json"
    )

    try
    {
        # Ensure directory exists
        Initialize-ConfigDirectory -ConfigPath $ConfigPath

        # Prepare configuration object
        $smtpConfig = @{
            SmtpServer = $SmtpServer
            FromEmail  = $FromEmail
            SmtpPort   = $SmtpPort
            UseSsl     = $UseSsl
            Timestamp  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        }

        # Store credentials securely if provided
        if ($Credential)
        {
            $credentialPath = "$env:LOCALAPPDATA\PoshACME\smtp_credential.xml"
            $Credential | Export-Clixml -Path $credentialPath
            $smtpConfig.CredentialPath = $credentialPath
        }

        # Save configuration
        if ($PSCmdlet.ShouldProcess($ConfigPath, "Save SMTP configuration"))
        {
            $smtpConfig | ConvertTo-Json | Set-Content -Path $ConfigPath
            Write-AutoCertLog "SMTP configuration saved successfully" -Level 'Success'
            return $true
        } else
        {
            Write-Information -MessageData "SMTP configuration save skipped due to WhatIf parameter" -InformationAction Continue
            return $true
        }

    } catch
    {
        Write-RenewalError -Message "Failed to save SMTP configuration" -ErrorRecord $_
        return $false
    }
}

# Function to retrieve SMTP configuration
function Get-SmtpConfiguration
{
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter()]
        [string]$ConfigPath = "$env:LOCALAPPDATA\PoshACME\smtp_config.json"
    )

    try
    {
        if (-not (Test-Path $ConfigPath))
        {
            Write-AutoCertLog "SMTP configuration file not found: $ConfigPath" -Level 'Warning'
            return $null
        }

        $config = Get-Content $ConfigPath | ConvertFrom-Json

        # Load credentials if path is specified
        if ($config.CredentialPath -and (Test-Path $config.CredentialPath))
        {
            $config.Credential = Import-Clixml -Path $config.CredentialPath
        }

        return $config

    } catch
    {
        Write-RenewalError -Message "Failed to load SMTP configuration" -ErrorRecord $_
        return $null
    }
}

# Function to test email notification system
function Test-EmailNotification
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ToEmail,
        [Parameter()]
        [string]$TestMessage = "This is a test email from AutoCert notification system."
    )

    $subject = "AutoCert Test Notification - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $body = @"
AutoCert Email Test
==================

$TestMessage

System Information:
- Server: $env:COMPUTERNAME
- User: $env:USERNAME
- Time: $(Get-Date)
- PowerShell Version: $($PSVersionTable.PSVersion)

If you received this email, the notification system is working correctly.
"@

    $result = Send-RenewalNotification -Subject $subject -Body $body -ToEmail $ToEmail -Priority 'Info'

    if ($result)
    {
        Write-Information -MessageData "Test email sent successfully to $ToEmail" -InformationAction Continue
    } else
    {
        Write-Error -Message "Failed to send test email to $ToEmail"
    }

    return $result
}

# Function to send certificate renewal notifications using templates
function Send-CertificateNotification
{
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Success', 'Failure', 'Warning', 'Expiry')]
        [string]$NotificationType,
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter()]
        [hashtable]$AdditionalData = @{}
    )

    try
    {
        # NotificationManager is now loaded via SystemInitialization.ps1
        # Check if notification functions are available
        if (-not (Get-Command Initialize-NotificationSystem -ErrorAction SilentlyContinue))
        {
            Write-Warning "NotificationManager functions not available. Notifications may not work properly."
            return
        }

        Initialize-NotificationSystem

        $config = Get-RenewalConfig
        if (-not $config.EmailNotifications -or -not $config.NotificationEmail)
        {
            Write-AutoCertLog "Email notifications not configured" -Level 'Warning'
            return $false
        }

        # Prepare template variables
        $templateVars = @{
            Domain     = $Domain
            ServerName = $env:COMPUTERNAME
            Timestamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        }

        # Merge additional data
        foreach ($key in $AdditionalData.Keys)
        {
            $templateVars[$key] = $AdditionalData[$key]
        }

        # Select appropriate template
        $templateName = switch ($NotificationType)
        {
            'Success' { 'CertificateRenewalSuccess' }
            'Failure' { 'CertificateRenewalFailure' }
            'Warning' { 'CertificateRenewalWarning' }
            'Expiry' { 'CertificateExpiryWarning' }
        }

        if ($script:NotificationTemplates.ContainsKey($templateName))
        {
            $template = $script:NotificationTemplates[$templateName]
            $subject = $template.Subject -replace '\{\{Domain\}\}', $Domain
            $body = $template.GenerateBody($templateVars)
            $priority = $template.Level.ToString()

            return Send-RenewalNotification -Subject $subject -Body $body -ToEmail $config.NotificationEmail -Priority $priority
        } else
        {
            Write-AutoCertLog "Notification template '$templateName' not found" -Level 'Error'
            return $false
        }

    } catch
    {
        Write-RenewalError -Message "Failed to send certificate notification" -ErrorRecord $_
        return $false
    }
}
#endregion


