# Core/NotificationManager.ps1
<#
    .SYNOPSIS
        Advanced notification and alerting system with multiple channels and templates.
#>

enum NotificationLevel {
    Info
    Warning
    Error
    Critical
    Success
}

enum NotificationChannel {
    Email
    EventLog
    File
    Webhook
    Teams
    Slack
}

class NotificationTemplate {
    [string]$Name
    [NotificationLevel]$Level
    [string]$Subject
    [string]$BodyTemplate
    [hashtable]$DefaultValues
    
    NotificationTemplate([string]$Name, [NotificationLevel]$Level, [string]$Subject, [string]$BodyTemplate, [hashtable]$DefaultValues) {
        $this.Name = $Name
        $this.Level = $Level
        $this.Subject = $Subject
        $this.BodyTemplate = $BodyTemplate
        $this.DefaultValues = $DefaultValues
    }
    
    [string] GenerateBody([hashtable]$Variables) {
        $body = $this.BodyTemplate
        
        # Merge default values with provided variables
        $allVariables = $this.DefaultValues.Clone()
        foreach ($key in $Variables.Keys) {
            $allVariables[$key] = $Variables[$key]
        }
        
        # Replace placeholders
        foreach ($key in $allVariables.Keys) {
            $placeholder = "{{$key}}"
            $body = $body -replace [regex]::Escape($placeholder), $allVariables[$key]
        }
        
        return $body
    }
}

function Initialize-NotificationSystem {
    [CmdletBinding()]
    param()
    
    # Initialize notification templates
    $script:NotificationTemplates = @{
        'CertificateRenewalSuccess' = [NotificationTemplate]::new(
            'CertificateRenewalSuccess',
            [NotificationLevel]::Success,
            'Certificate Renewal Successful - {{Domain}}',
            @"
Certificate Renewal Successful
==============================

Domain: {{Domain}}
Renewal Date: {{RenewalDate}}
Expiration Date: {{ExpirationDate}}
Certificate Thumbprint: {{Thumbprint}}
Renewal Duration: {{Duration}}

The certificate for {{Domain}} has been successfully renewed and is valid until {{ExpirationDate}}.

Next renewal scheduled for: {{NextRenewalDate}}

System Information:
- Server: {{ServerName}}
- AutoCert Version: {{Version}}
- Renewal Method: {{RenewalMethod}}

No action required.
"@,
            @{
                ServerName = $env:COMPUTERNAME
                Version = "2.0.0"
                RenewalMethod = "Automatic"
            }
        )
        
        'CertificateRenewalFailure' = [NotificationTemplate]::new(
            'CertificateRenewalFailure',
            [NotificationLevel]::Error,
            'URGENT: Certificate Renewal Failed - {{Domain}}',
            @"
CERTIFICATE RENEWAL FAILURE
===========================

Domain: {{Domain}}
Failure Date: {{FailureDate}}
Current Expiration: {{CurrentExpiration}}
Days Until Expiry: {{DaysUntilExpiry}}
Error: {{ErrorMessage}}

IMMEDIATE ACTION REQUIRED!

The certificate renewal for {{Domain}} has failed. The certificate will expire in {{DaysUntilExpiry}} days.

Error Details:
{{ErrorDetails}}

Recommended Actions:
1. Check DNS provider connectivity and credentials
2. Verify domain ownership and DNS propagation
3. Review system logs for additional details
4. Consider manual renewal if automated process continues to fail

System Information:
- Server: {{ServerName}}
- AutoCert Version: {{Version}}
- Last Successful Renewal: {{LastSuccessfulRenewal}}
- Failure Count: {{FailureCount}}

Log Files:
- Application Log: {{LogPath}}
- Error Details: {{ErrorLogPath}}

Contact your system administrator immediately if this issue persists.
"@,
            @{
                ServerName = $env:COMPUTERNAME
                Version = "2.0.0"
                LogPath = "$env:LOCALAPPDATA\PoshACME\certificate_script.log"
                ErrorLogPath = "$env:LOCALAPPDATA\PoshACME\error.log"
            }
        )
        
        'CertificateExpiryWarning' = [NotificationTemplate]::new(
            'CertificateExpiryWarning',
            [NotificationLevel]::Warning,
            'Certificate Expiry Warning - {{Domain}}',
            @"
Certificate Expiry Warning
==========================

Domain: {{Domain}}
Current Expiration: {{ExpirationDate}}
Days Until Expiry: {{DaysUntilExpiry}}
Certificate Thumbprint: {{Thumbprint}}

The certificate for {{Domain}} will expire in {{DaysUntilExpiry}} days.

Automatic renewal is configured and should occur within the next {{RenewalWindow}} days.

Next scheduled renewal: {{NextRenewalDate}}

If automatic renewal fails, you will receive an urgent notification requiring immediate action.

System Information:
- Server: {{ServerName}}
- AutoCert Version: {{Version}}
- Renewal Schedule: {{RenewalSchedule}}

Monitor renewal status at: {{ManagementUrl}}
"@,
            @{
                ServerName = $env:COMPUTERNAME
                Version = "2.0.0"
                RenewalWindow = "7"
                ManagementUrl = "Local AutoCert Management Console"
            }
        )
        
        'SystemHealthAlert' = [NotificationTemplate]::new(
            'SystemHealthAlert',
            [NotificationLevel]::Critical,
            'AutoCert System Health Alert',
            @"
AutoCert System Health Alert
============================

Alert Date: {{AlertDate}}
Severity: {{Severity}}
Component: {{Component}}

{{AlertMessage}}

System Status:
{{SystemStatus}}

Failed Health Checks:
{{FailedChecks}}

Recommended Actions:
{{Recommendations}}

System Information:
- Server: {{ServerName}}
- AutoCert Version: {{Version}}
- Last Successful Operation: {{LastSuccessfulOperation}}

Please address these issues promptly to ensure continued certificate management functionality.
"@,
            @{
                ServerName = $env:COMPUTERNAME
                Version = "2.0.0"
            }
        )
    }
    
    Write-Log "Notification system initialized with $($script:NotificationTemplates.Count) templates" -Level 'Info'
}

function Send-Notification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TemplateName,
        [Parameter(Mandatory)]
        [hashtable]$Variables,
        [NotificationChannel[]]$Channels = @([NotificationChannel]::Email, [NotificationChannel]::EventLog),
        [string]$OverrideRecipient,
        [switch]$HighPriority
    )
    
    if (-not $script:NotificationTemplates) {
        Initialize-NotificationSystem
    }
    
    if (-not $script:NotificationTemplates.ContainsKey($TemplateName)) {
        throw "Notification template not found: $TemplateName"
    }
    
    $template = $script:NotificationTemplates[$TemplateName]
    $subject = $template.Subject
    $body = $template.GenerateBody($Variables)
    
    # Replace placeholders in subject
    foreach ($key in $Variables.Keys) {
        $placeholder = "{{$key}}"
        $subject = $subject -replace [regex]::Escape($placeholder), $Variables[$key]
    }
    
    $results = @{}
    
    foreach ($channel in $Channels) {
        try {
            switch ($channel) {
                ([NotificationChannel]::Email) {
                    $emailResult = Send-EmailNotification -Subject $subject -Body $body -Level $template.Level -OverrideRecipient $OverrideRecipient -HighPriority:$HighPriority
                    $results[$channel] = $emailResult
                }
                
                ([NotificationChannel]::EventLog) {
                    $eventResult = Send-EventLogNotification -Subject $subject -Body $body -Level $template.Level
                    $results[$channel] = $eventResult
                }
                
                ([NotificationChannel]::File) {
                    $fileResult = Send-FileNotification -Subject $subject -Body $body -Level $template.Level
                    $results[$channel] = $fileResult
                }
                
                ([NotificationChannel]::Webhook) {
                    $webhookResult = Send-WebhookNotification -Subject $subject -Body $body -Level $template.Level -Variables $Variables
                    $results[$channel] = $webhookResult
                }
                
                ([NotificationChannel]::Teams) {
                    $teamsResult = Send-TeamsNotification -Subject $subject -Body $body -Level $template.Level -Variables $Variables
                    $results[$channel] = $teamsResult
                }
                
                ([NotificationChannel]::Slack) {
                    $slackResult = Send-SlackNotification -Subject $subject -Body $body -Level $template.Level -Variables $Variables
                    $results[$channel] = $slackResult
                }
            }
        } catch {
            Write-Log "Failed to send notification via $channel`: $($_.Exception.Message)" -Level 'Error'
            $results[$channel] = @{ Success = $false; Error = $_.Exception.Message }
        }
    }
    
    return $results
}

function Send-EmailNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subject,
        [Parameter(Mandatory)]
        [string]$Body,
        [NotificationLevel]$Level = [NotificationLevel]::Info,
        [string]$OverrideRecipient,
        [switch]$HighPriority
    )
    
    try {
        $config = Get-RenewalConfig
        
        if (-not $config.EmailNotifications) {
            return @{ Success = $false; Error = "Email notifications disabled" }
        }
        
        $recipient = if ($OverrideRecipient) { $OverrideRecipient } else { $config.NotificationEmail }
        
        if (-not $recipient) {
            return @{ Success = $false; Error = "No email recipient configured" }
        }
        
        # Get SMTP settings
        $smtpSettings = Get-SMTPSettings
        if (-not $smtpSettings) {
            return @{ Success = $false; Error = "SMTP settings not configured" }
        }
        
        $mailParams = @{
            To = $recipient
            Subject = $Subject
            Body = $Body
            SmtpServer = $smtpSettings.Server
            Port = $smtpSettings.Port
            From = $smtpSettings.From
        }
        
        if ($smtpSettings.UseSSL) {
            $mailParams.UseSsl = $true
        }
        
        if ($smtpSettings.Credential) {
            $mailParams.Credential = $smtpSettings.Credential
        }
        
        if ($HighPriority) {
            $mailParams.Priority = 'High'
        }
        
        # Set priority based on notification level
        switch ($Level) {
            ([NotificationLevel]::Critical) { $mailParams.Priority = 'High' }
            ([NotificationLevel]::Error) { $mailParams.Priority = 'High' }
            ([NotificationLevel]::Warning) { $mailParams.Priority = 'Normal' }
            default { $mailParams.Priority = 'Normal' }
        }
        
        Send-MailMessage @mailParams
        
        Write-Log "Email notification sent to $recipient`: $Subject" -Level 'Info'
        return @{ Success = $true; Recipient = $recipient }
        
    } catch {
        Write-Log "Failed to send email notification: $($_.Exception.Message)" -Level 'Error'
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Send-EventLogNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subject,
        [Parameter(Mandatory)]
        [string]$Body,
        [NotificationLevel]$Level = [NotificationLevel]::Info
    )
    
    try {
        # Map notification level to event log entry type
        $entryType = switch ($Level) {
            ([NotificationLevel]::Critical) { 'Error' }
            ([NotificationLevel]::Error) { 'Error' }
            ([NotificationLevel]::Warning) { 'Warning' }
            default { 'Information' }
        }
        
        # Map notification level to event ID
        $eventId = switch ($Level) {
            ([NotificationLevel]::Critical) { 1001 }
            ([NotificationLevel]::Error) { 1002 }
            ([NotificationLevel]::Warning) { 1003 }
            ([NotificationLevel]::Success) { 1004 }
            default { 1000 }
        }
        
        $source = "AutoCert Certificate Management"
        $logName = "Application"
        
        # Create event source if it doesn't exist
        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            try {
                New-EventLog -LogName $logName -Source $source
            } catch {
                # Fallback to default source if creation fails
                $source = "Application"
            }
        }
        
        $message = "$Subject`n`n$Body"
        Write-EventLog -LogName $logName -Source $source -EntryType $entryType -EventId $eventId -Message $message
        
        Write-Log "Event log notification written: $Subject" -Level 'Info'
        return @{ Success = $true; EventId = $eventId }
        
    } catch {
        Write-Log "Failed to write event log notification: $($_.Exception.Message)" -Level 'Error'
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Send-FileNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subject,
        [Parameter(Mandatory)]
        [string]$Body,
        [NotificationLevel]$Level = [NotificationLevel]::Info,
        [string]$FilePath = "$env:LOCALAPPDATA\AutoCert\Logs\notifications.log"
    )
    
    try {
        $logDir = Split-Path -Path $FilePath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = @"
[$timestamp] [$Level] $Subject
$Body
$('-' * 80)

"@
        
        Add-Content -Path $FilePath -Value $logEntry -Encoding UTF8
        
        return @{ Success = $true; FilePath = $FilePath }
        
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Send-WebhookNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Subject,
        [Parameter(Mandatory)]
        [string]$Body,
        [NotificationLevel]$Level = [NotificationLevel]::Info,
        [hashtable]$Variables = @{}
    )
    
    try {
        $config = Get-RenewalConfig
        $webhookUrl = $config.WebhookUrl
        
        if (-not $webhookUrl) {
            return @{ Success = $false; Error = "Webhook URL not configured" }
        }
        
        $payload = @{
            timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
            level = $Level.ToString()
            subject = $Subject
            body = $Body
            server = $env:COMPUTERNAME
            variables = $Variables
        } | ConvertTo-Json -Depth 10
        
        $headers = @{
            'Content-Type' = 'application/json'
            'User-Agent' = 'AutoCert/2.0.0'
        }
        
        Invoke-RestMethod -Uri $webhookUrl -Method Post -Body $payload -Headers $headers -TimeoutSec 30
        
        Write-Log "Webhook notification sent: $Subject" -Level 'Info'
        return @{ Success = $true; WebhookUrl = $webhookUrl }
        
    } catch {
        Write-Log "Failed to send webhook notification: $($_.Exception.Message)" -Level 'Error'
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

function Get-SMTPSettings {
    [CmdletBinding()]
    param()
    
    try {
        $config = Get-RenewalConfig
        
        if ($config.SMTPSettings) {
            return $config.SMTPSettings
        }
        
        # Default SMTP settings (can be customized)
        return @{
            Server = 'localhost'
            Port = 25
            UseSSL = $false
            From = "autocert@$env:COMPUTERNAME"
            Credential = $null
        }
        
    } catch {
        Write-Log "Failed to get SMTP settings: $($_.Exception.Message)" -Level 'Error'
        return $null
    }
}

function Test-NotificationSystem {
    [CmdletBinding()]
    param(
        [NotificationChannel[]]$Channels = @([NotificationChannel]::Email, [NotificationChannel]::EventLog),
        [string]$TestRecipient
    )
    
    $testVariables = @{
        Domain = "test.example.com"
        RenewalDate = Get-Date
        ExpirationDate = (Get-Date).AddDays(90)
        Thumbprint = "TEST123456789ABCDEF"
        Duration = "2 minutes"
        NextRenewalDate = (Get-Date).AddDays(60)
    }
    
    Write-Host "Testing notification system..." -ForegroundColor Cyan
    
    $results = Send-Notification -TemplateName 'CertificateRenewalSuccess' -Variables $testVariables -Channels $Channels -OverrideRecipient $TestRecipient
    
    foreach ($channel in $results.Keys) {
        $result = $results[$channel]
        $status = if ($result.Success) { "✓ PASS" } else { "✗ FAIL" }
        $color = if ($result.Success) { "Green" } else { "Red" }
        
        Write-Host "$status $channel" -ForegroundColor $color
        if (-not $result.Success) {
            Write-Host "  Error: $($result.Error)" -ForegroundColor Red
        }
    }
    
    return $results
}
