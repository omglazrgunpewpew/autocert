# Functions/Set-AutomaticRenewal.ps1
<#
    .SYNOPSIS
        Automatic renewal configuration with scheduling,
        randomization, retry logic, and monitoring capabilities.
#>
function Set-AutomaticRenewal
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [switch]$Force
    )
    Write-ProgressHelper -Activity "Automatic Renewal Setup" -Status "Loading configuration..." -PercentComplete 10
    # Load current configuration
    $config = Get-RenewalConfig
    $settings = Get-ScriptSettings
    Write-Host -Object "`n=== Automatic Certificate Renewal Configuration ===" -ForegroundColor Cyan
    Write-Warning -Message "Current Renewal Schedule Settings:"
    Write-Host -Object "  Renewal Time: $($config.RenewalHour):$($config.RenewalMinute.ToString('00'))"
    Write-Host -Object "  Use Randomization: $($config.UseRandomization)"
    if ($config.UseRandomization)
    {
        Write-Host -Object "  Randomization Window: $($config.RandomizationWindow) minutes"
    }
    Write-Host -Object "  Renewal Threshold: $($config.RenewalThresholdDays) days before expiry"
    Write-Host -Object "  Max Retries: $($config.MaxRetries)"
    Write-Host -Object "  Retry Delay: $($config.RetryDelayMinutes) minutes"
    Write-Host -Object "  Email Notifications: $($config.EmailNotifications)"
    if ($config.EmailNotifications)
    {
        Write-Host -Object "  Notification Email: $($config.NotificationEmail)"
    }
    Write-ProgressHelper -Activity "Automatic Renewal Setup" -Status "Displaying configuration options..." -PercentComplete 25
    while ($true)
    {
        Write-Host -Object "`nConfiguration Options:" -ForegroundColor Cyan
        Write-Host -Object "1) Modify renewal schedule"
        Write-Host -Object "2) Configure randomization settings"
        Write-Host -Object "3) Set renewal threshold"
        Write-Host -Object "4) Configure retry settings"
        Write-Host -Object "5) Set up email notifications"
        Write-Host -Object "6) Logging options"
        Write-Host -Object "7) Test current configuration"
        Write-Host -Object "8) Apply configuration and create scheduled task"
        Write-Host -Object "9) Quick setup (recommended defaults)"
        Write-Host -Object "0) Back to main menu"
        $choice = Get-ValidatedInput -Prompt "`nEnter your choice (0-9)" -ValidOptions (0..9)
        switch ($choice)
        {
            0 { return }
            1
            {
                # Modify renewal schedule
                Write-Warning -Message "`nCurrent schedule: $($config.RenewalHour):$($config.RenewalMinute.ToString('00'))"
                do
                {
                    $hour = Read-Host "`nEnter the hour for renewal (0-23, current: $($config.RenewalHour))"
                    if ([string]::IsNullOrWhiteSpace($hour))
                    {
                        $hour = $config.RenewalHour
                        break
                    }
                    if ($hour -match '^\d+$' -and [int]$hour -ge 0 -and [int]$hour -le 23)
                    {
                        $config.RenewalHour = [int]$hour
                        break
                    }
                    Write-Warning -Message "Invalid hour. Please enter a number between 0 and 23."
                } while ($true)
                do
                {
                    $minute = Read-Host "Enter the minute for renewal (0-59, current: $($config.RenewalMinute))"
                    if ([string]::IsNullOrWhiteSpace($minute))
                    {
                        $minute = $config.RenewalMinute
                        break
                    }
                    if ($minute -match '^\d+$' -and [int]$minute -ge 0 -and [int]$minute -le 59)
                    {
                        $config.RenewalMinute = [int]$minute
                        break
                    }
                    Write-Warning -Message "Invalid minute. Please enter a number between 0 and 59."
                } while ($true)
                Write-Information -MessageData "Schedule updated to: $($config.RenewalHour):$($config.RenewalMinute.ToString('00'))" -InformationAction Continue
            }
            2
            {
                # Configure randomization
                $useRandom = Read-Host "`nEnable randomization to spread load? (Y/N, current: $($config.UseRandomization))"
                if ($useRandom -match '^[YyNn]$')
                {
                    $config.UseRandomization = $useRandom -match '^[Yy]$'
                }
                if ($config.UseRandomization)
                {
                    do
                    {
                        $window = Read-Host "Enter randomization window in minutes (15-180, current: $($config.RandomizationWindow))"
                        if ([string]::IsNullOrWhiteSpace($window))
                        {
                            $window = $config.RandomizationWindow
                            break
                        }
                        if ($window -match '^\d+$' -and [int]$window -ge 15 -and [int]$window -le 180)
                        {
                            $config.RandomizationWindow = [int]$window
                            break
                        }
                        Write-Warning -Message "Invalid window. Please enter a number between 15 and 180."
                    } while ($true)
                }
                $status = if ($config.UseRandomization) { "enabled with $($config.RandomizationWindow) minute window" } else { "disabled" }
                Write-Information -MessageData "Randomization $status" -InformationAction Continue
            }
            3
            {
                # Set renewal threshold
                Write-Warning -Message "`nCurrent threshold: $($config.RenewalThresholdDays) days before expiry"
                do
                {
                    $threshold = Read-Host "Enter renewal threshold in days (1-90, current: $($config.RenewalThresholdDays))"
                    if ([string]::IsNullOrWhiteSpace($threshold))
                    {
                        $threshold = $config.RenewalThresholdDays
                        break
                    }
                    if ($threshold -match '^\d+$' -and [int]$threshold -ge 1 -and [int]$threshold -le 90)
                    {
                        $config.RenewalThresholdDays = [int]$threshold
                        break
                    }
                    Write-Warning -Message "Invalid threshold. Please enter a number between 1 and 90."
                } while ($true)
                Write-Information -MessageData "Renewal threshold set to $($config.RenewalThresholdDays) days" -InformationAction Continue
            }
            4
            {
                # Configure retry settings
                Write-Warning -Message "`nCurrent retry settings:"
                Write-Host -Object "  Max Retries: $($config.MaxRetries)"
                Write-Host -Object "  Retry Delay: $($config.RetryDelayMinutes) minutes"
                do
                {
                    $maxRetries = Read-Host "Enter maximum retries (1-10, current: $($config.MaxRetries))"
                    if ([string]::IsNullOrWhiteSpace($maxRetries))
                    {
                        $maxRetries = $config.MaxRetries
                        break
                    }
                    if ($maxRetries -match '^\d+$' -and [int]$maxRetries -ge 1 -and [int]$maxRetries -le 10)
                    {
                        $config.MaxRetries = [int]$maxRetries
                        break
                    }
                    Write-Warning -Message "Invalid retry count. Please enter a number between 1 and 10."
                } while ($true)
                do
                {
                    $retryDelay = Read-Host "Enter retry delay in minutes (5-60, current: $($config.RetryDelayMinutes))"
                    if ([string]::IsNullOrWhiteSpace($retryDelay))
                    {
                        $retryDelay = $config.RetryDelayMinutes
                        break
                    }
                    if ($retryDelay -match '^\d+$' -and [int]$retryDelay -ge 5 -and [int]$retryDelay -le 60)
                    {
                        $config.RetryDelayMinutes = [int]$retryDelay
                        break
                    }
                    Write-Warning -Message "Invalid delay. Please enter a number between 5 and 60."
                } while ($true)
                Write-Information -MessageData "Retry settings updated" -InformationAction Continue
            }
            5
            {
                # Email notifications
                $enableEmail = Read-Host "`nEnable email notifications? (Y/N, current: $($config.EmailNotifications))"
                if ($enableEmail -match '^[YyNn]$')
                {
                    $config.EmailNotifications = $enableEmail -match '^[Yy]$'
                }
                if ($config.EmailNotifications)
                {
                    do
                    {
                        $email = Read-Host "Enter notification email address (current: $($config.NotificationEmail))"
                        if ([string]::IsNullOrWhiteSpace($email))
                        {
                            $email = $config.NotificationEmail
                        }
                        if (Test-ValidEmail -Email $email)
                        {
                            $config.NotificationEmail = $email
                            break
                        }
                        Write-Warning -Message "Invalid email address format."
                    } while ($true)
                    Write-Information -MessageData "Email notifications configured for: $($config.NotificationEmail)" -InformationAction Continue
                } else
                {
                    Write-Warning -Message "Email notifications disabled"
                }
            }
            6
            {
                # Logging options
                Write-Warning -Message "`nLogging Configuration:"
                Write-Host -Object "  Log Retention: $($config.LogRetention) days"
                Write-Host -Object "  Health Check: $($config.HealthCheckEnabled)"
                do
                {
                    $retention = Read-Host "Enter log retention in days (7-365, current: $($config.LogRetention))"
                    if ([string]::IsNullOrWhiteSpace($retention))
                    {
                        $retention = $config.LogRetention
                        break
                    }
                    if ($retention -match '^\d+$' -and [int]$retention -ge 7 -and [int]$retention -le 365)
                    {
                        $config.LogRetention = [int]$retention
                        break
                    }
                    Write-Warning -Message "Invalid retention period. Please enter a number between 7 and 365."
                } while ($true)
                $enableHealthCheck = Read-Host "Enable health checks? (Y/N, current: $($config.HealthCheckEnabled))"
                if ($enableHealthCheck -match '^[YyNn]$')
                {
                    $config.HealthCheckEnabled = $enableHealthCheck -match '^[Yy]$'
                }
                Write-Information -MessageData "Logging configuration updated" -InformationAction Continue
            }
            7
            {
                # Test configuration
                Write-Host -Object "`nTesting current configuration..." -ForegroundColor Cyan
                Write-ProgressHelper -Activity "Configuration Test" -Status "Validating settings..." -PercentComplete 50
                if (Test-RenewalConfig -Config $config)
                {
                    Write-Information -MessageData "OK Configuration is valid" -InformationAction Continue
                    # Show what would happen
                    $baseTime = [DateTime]::Today.AddHours($config.RenewalHour).AddMinutes($config.RenewalMinute)
                    Write-Information -MessageData "OK Base renewal time: $($baseTime.ToString('HH:mm'))" -InformationAction Continue
                    if ($config.UseRandomization)
                    {
                        $earliestTime = $baseTime.AddMinutes(-$config.RandomizationWindow / 2)
                        $latestTime = $baseTime.AddMinutes($config.RandomizationWindow / 2)
                        Write-Host -Object "OK Randomized window: $($earliestTime.ToString('HH:mm')) - $($latestTime.ToString('HH:mm'))" -ForegroundColor Green
                    }
                    # Check certificate status
                    $renewalStatus = Get-CertificateRenewalStatus -Config $config
                    if ($renewalStatus.Count -gt 0)
                    {
                        Write-Host -Object "`nCertificate Status:" -ForegroundColor Cyan
                        foreach ($cert in $renewalStatus)
                        {
                            $color = if ($cert.NeedsRenewal) { "Yellow" } else { "Green" }
                            Write-Host -Object "  $($cert.Domain): $($cert.Status) ($($cert.DaysUntilExpiry) days)" -ForegroundColor $color
                        }
                    }
                } else
                {
                    Write-Warning -Message "Configuration validation failed. Please review settings."
                }
                Write-Progress -Activity "Configuration Test" -Completed
            }
            8
            {
                # Apply configuration
                Write-Host -Object "`nApplying configuration and creating scheduled task..." -ForegroundColor Cyan
                Write-ProgressHelper -Activity "Automatic Renewal Setup" -Status "Validating configuration..." -PercentComplete 60
                if (-not (Test-RenewalConfig -Config $config))
                {
                    Write-Error -Message "Configuration validation failed. Please fix errors before applying."
                    continue
                }
                Write-ProgressHelper -Activity "Automatic Renewal Setup" -Status "Saving configuration..." -PercentComplete 70
                if ($PSCmdlet.ShouldProcess("Automatic certificate renewal configuration", "Apply configuration and create scheduled task"))
                {
                    if (-not (Save-RenewalConfig -Config $config))
                    {
                        Write-Error -Message "Failed to save configuration."
                        continue
                    }
                    Write-ProgressHelper -Activity "Automatic Renewal Setup" -Status "Creating scheduled task..." -PercentComplete 80
                    # Get main script path
                    $mainScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Main.ps1"
                    if (-not (Test-Path $mainScriptPath))
                    {
                        Write-Error -Message "Cannot find Main.ps1 script at: $mainScriptPath"
                        continue
                    }
                    if (New-RenewalScheduledTask -Config $config -ScriptPath $mainScriptPath)
                    {
                        Write-ProgressHelper -Activity "Automatic Renewal Setup" -Status "Setup complete!" -PercentComplete 100
                        Write-Information -MessageData "`nAutomatic renewal configured!" -InformationAction Continue
                        Write-Host -Object "`nConfiguration Summary:" -ForegroundColor Cyan
                        Write-Host -Object "  Schedule: Daily at $($config.RenewalHour):$($config.RenewalMinute.ToString('00'))"
                        if ($config.UseRandomization)
                        {
                            Write-Host -Object "  Randomization: +/-$($config.RandomizationWindow/2) minutes"
                        }
                        Write-Host -Object "  Renewal Threshold: $($config.RenewalThresholdDays) days before expiry"
                        Write-Host -Object "  Max Retries: $($config.MaxRetries)"
                        Write-Host -Object "  Email Notifications: $($config.EmailNotifications)"
                        Write-Host -Object "`nNext automatic renewal check: $(Get-Date -Hour $config.RenewalHour -Minute $config.RenewalMinute -Second 0)" -ForegroundColor Yellow
                        Write-Log "Automatic renewal configured"
                        Write-Progress -Activity "Automatic Renewal Setup" -Completed
                        return
                    } else
                    {
                        Write-Error -Message "Failed to create scheduled task."
                    }
                }
            }
            9
            {
                # Quick setup with recommended defaults
                Write-Host -Object "`nSetting up automatic renewal with recommended defaults..." -ForegroundColor Cyan
                # Apply recommended settings
                $config.RenewalHour = 2
                $config.RenewalMinute = Get-Random -Minimum 0 -Maximum 59
                $config.UseRandomization = $true
                $config.RandomizationWindow = 60
                $config.RenewalThresholdDays = 30
                $config.MaxRetries = 3
                $config.RetryDelayMinutes = 15
                $config.HealthCheckEnabled = $true
                $config.LogRetention = 30
                # Prompt for email if not configured
                if (-not $config.EmailNotifications -or -not $config.NotificationEmail)
                {
                    $setupEmail = Read-Host "`nWould you like to configure email notifications? (Y/N)"
                    if ($setupEmail -match '^[Yy]$')
                    {
                        do
                        {
                            $email = Read-Host "Enter notification email address"
                            if (Test-ValidEmail -Email $email)
                            {
                                $config.EmailNotifications = $true
                                $config.NotificationEmail = $email
                                break
                            }
                            Write-Warning -Message "Invalid email address format."
                        } while ($true)
                    }
                }
                Write-Warning -Message "`nQuick setup configuration:"
                Write-Host -Object "  Schedule: Daily at $($config.RenewalHour):$($config.RenewalMinute.ToString('00')) +/-30 minutes"
                Write-Host -Object "  Renewal Threshold: 30 days before expiry"
                Write-Host -Object "  Retry: 3 attempts with 15-minute delays"
                Write-Host -Object "  Email Notifications: $($config.EmailNotifications)"
                $confirm = Read-Host "`nApply these settings? (Y/N)"
                if ($confirm -match '^[Yy]$')
                {
                    # Save and apply
                    Save-RenewalConfig -Config $config
                    $mainScriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "Main.ps1"
                    if (New-RenewalScheduledTask -Config $config -ScriptPath $mainScriptPath)
                    {
                        Write-Information -MessageData "`nQuick setup completed!" -InformationAction Continue
                        Write-Log "Quick setup automatic renewal configured"
                        return
                    }
                }
            }
        }
    }
}


