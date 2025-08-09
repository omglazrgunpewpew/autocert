# RenewalManager.ps1
# Handles automated certificate renewal operations

<#
.SYNOPSIS
    Manages automated certificate renewal operations for scheduled tasks.

.DESCRIPTION
    Provides functionality for running certificate renewals in non-interactive mode,
    suitable for scheduled tasks and automation scenarios.
#>

function Invoke-AutomatedRenewal {
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    Write-Host -Object "Running in renewal mode..." -ForegroundColor Cyan
    Write-Log "Starting renewal process (Version: $script:ScriptVersion)" -Level 'Info'

    try {
        # Load renewal configuration
        $config = Get-RenewalConfig

        # Get all certificates and check renewal status
        $orders = Get-PAOrder
        if (-not $orders) {
            Write-Warning -Message "No certificates found to renew."
            Write-Log "No certificates found for renewal" -Level 'Warning'
            return @{
                Success = $true
                RenewedCount = 0
                FailedCount = 0
                SkippedCount = 0
                Message = "No certificates found"
            }
        }

        Write-Information -MessageData "Found $($orders.Count) certificate(s) to check for renewal." -InformationAction Continue

        # Check renewal status for all certificates
        $renewalStatus = Get-CertificateRenewalStatus -Config $config
        $needsRenewal = $renewalStatus | Where-Object { $_.NeedsRenewal -or $Force }

        if (-not $needsRenewal) {
            Write-Information -MessageData "No certificates need renewal at this time." -InformationAction Continue
            Write-Log "No certificates require renewal" -Level 'Info'
            return @{
                Success = $true
                RenewedCount = 0
                FailedCount = 0
                SkippedCount = $orders.Count
                Message = "No certificates need renewal"
            }
        }

        Write-Warning -Message "Found $($needsRenewal.Count) certificate(s) that need renewal."

        # Initialize counters and results
        $renewalCount = 0
        $errorCount = 0
        $skippedCount = 0
        $results = @()

        # Process each certificate that needs renewal
        foreach ($cert in $needsRenewal) {
            Write-Host -Object "`nProcessing: $($cert.Domain)" -ForegroundColor Cyan
            Write-Log "Starting renewal for certificate: $($cert.Domain)" -Level 'Info'

            try {
                # Apply randomization if configured
                if ($config.UseRandomization -and -not $Force) {
                    $randomDelay = Get-Random -Minimum 0 -Maximum $config.RandomizationWindow
                    Write-Host -Object "Applying randomization delay: $randomDelay minutes" -ForegroundColor Gray
                    Write-Log "Randomization delay applied: $randomDelay minutes for $($cert.Domain)" -Level 'Debug'

                    if ($randomDelay -gt 0) {
                        Start-Sleep -Seconds ($randomDelay * 60)
                    }
                }

                # Attempt certificate renewal with retry logic
                $renewalResult = Invoke-WithRetry -ScriptBlock {
                    Submit-Renewal -MainDomain $cert.Domain -Force:$Force
                } -MaxAttempts $config.RetryAttempts -InitialDelaySeconds $config.RetryDelay -OperationName "Certificate renewal for $($cert.Domain)"

                if ($renewalResult) {
                    Write-Information -MessageData "✓ Renewed: $($cert.Domain)" -InformationAction Continue
                    Write-Log "Certificate renewed: $($cert.Domain)" -Level 'Success'
                    $renewalCount++

                    $results += @{
                        Domain = $cert.Domain
                        Status = "Renewed"
                        Timestamp = Get-Date
                        ExpiryDate = $renewalResult.NotAfter
                    }

                    # Install certificate if auto-installation is enabled
                    if ($config.AutoInstall) {
                        try {
                            Write-Host -Object "Auto-installing renewed certificate..." -ForegroundColor Cyan
                            Install-Certificate -MainDomain $cert.Domain -AutoMode
                            Write-Information -MessageData "✓ Certificate installed" -InformationAction Continue
                            Write-Log "Certificate auto-installed: $($cert.Domain)" -Level 'Success'
                        } catch {
                            Write-Warning -Message "Certificate renewed but installation failed: $($_.Exception.Message)"
                            Write-Log "Auto-installation failed for $($cert.Domain): $($_.Exception.Message)" -Level 'Warning'
                        }
                    }
                } else {
                    throw "Renewal returned null result"
                }

            } catch {
                $errorMsg = "Failed to renew certificate '$($cert.Domain)': $($_.Exception.Message)"
                Write-Error -Message "✗ $errorMsg"
                Write-Log $errorMsg -Level 'Error'
                $errorCount++

                $results += @{
                    Domain = $cert.Domain
                    Status = "Failed"
                    Timestamp = Get-Date
                    Error = $_.Exception.Message
                }
            }
        }

        # Handle certificates that were skipped
        $skippedCount = $orders.Count - $needsRenewal.Count

        # Generate summary
        Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
        Write-Host -Object "RENEWAL SUMMARY" -ForegroundColor Cyan
        Write-Host -Object "="*60 -ForegroundColor Cyan
        Write-Host -Object "Certificates processed: $($orders.Count)" -ForegroundColor White
        Write-Information -MessageData "Renewed: $renewalCount" -InformationAction Continue
        Write-Error -Message "Failed renewals: $errorCount"
        Write-Warning -Message "Skipped (not due): $skippedCount"
        Write-Host -Object "Completion time: $(Get-Date)" -ForegroundColor Gray

        # Send notification if configured
        if ($config.NotificationEmail -and ($renewalCount -gt 0 -or $errorCount -gt 0)) {
            Send-RenewalNotificationSummary -Config $config -Results $results -RenewedCount $renewalCount -ErrorCount $errorCount -SkippedCount $skippedCount
        }

        Write-Log "Automatic renewal completed - Renewed: $renewalCount, Failed: $errorCount, Skipped: $skippedCount" -Level 'Info'

        return @{
            Success = ($errorCount -eq 0)
            RenewedCount = $renewalCount
            FailedCount = $errorCount
            SkippedCount = $skippedCount
            Results = $results
            Message = "Renewed: $renewalCount, Failed: $errorCount, Skipped: $skippedCount"
        }

    } catch {
        $criticalError = "Critical error in automated renewal: $($_.Exception.Message)"
        Write-Error -Message $criticalError
        Write-Log $criticalError -Level 'Error'

        return @{
            Success = $false
            RenewedCount = 0
            FailedCount = 1
            SkippedCount = 0
            Results = @()
            Message = "Critical error: $($_.Exception.Message)"
        }
    }
}

function Send-RenewalNotificationSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Config,
        [Parameter(Mandatory = $true)]
        [array]$Results,
        [Parameter(Mandatory = $true)]
        [int]$RenewedCount,
        [Parameter(Mandatory = $true)]
        [int]$ErrorCount,
        [Parameter(Mandatory = $true)]
        [int]$SkippedCount
    )

    try {
        # Determine notification type and subject
        if ($ErrorCount -gt 0) {
            $subject = "AutoCert: Certificate Renewal Issues Detected"
            $priority = "High"
        } elseif ($RenewedCount -gt 0) {
            $subject = "AutoCert: Certificates Renewed"
            $priority = "Normal"
        } else {
            $subject = "AutoCert: Renewal Check Completed"
            $priority = "Low"
        }

        # Build HTML summary
        $htmlResults = ""
        foreach ($result in $Results) {
            $statusColor = switch ($result.Status) {
                "Renewed" { "green" }
                "Failed" { "red" }
                default { "orange" }
            }

            $domain   = [System.Web.HttpUtility]::HtmlEncode($result.Domain)
            $status   = [System.Web.HttpUtility]::HtmlEncode($result.Status)
            $processed = [System.Web.HttpUtility]::HtmlEncode($result.Timestamp.ToString('yyyy-MM-dd HH:mm'))

            $htmlResults += "<tr style='color: $statusColor;'>"
            $htmlResults += "<td>$domain</td>"
            $htmlResults += "<td>$status</td>"
            $htmlResults += "<td>$processed</td>"
            if ($result.ExpiryDate) {
                $expiry = [System.Web.HttpUtility]::HtmlEncode($result.ExpiryDate.ToString('yyyy-MM-dd'))
                $htmlResults += "<td>$expiry</td>"
            } elseif ($result.Error) {
                $errorMsg = [System.Web.HttpUtility]::HtmlEncode($result.Error)
                $htmlResults += "<td>$errorMsg</td>"
            } else {
                $htmlResults += "<td>-</td>"
            }
            $htmlResults += "</tr>"
        }

        $body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .summary { background-color: #f5f5f5; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .success { color: green; }
        .error { color: red; }
        .warning { color: orange; }
    </style>
</head>
<body>
    <h2>AutoCert Certificate Renewal Summary</h2>
    <div class="summary">
        <p><strong>Renewal Status:</strong></p>
        <ul>
            <li class="success">Renewed: $RenewedCount</li>
            <li class="error">Failed Renewals: $ErrorCount</li>
            <li class="warning">Skipped (not due): $SkippedCount</li>
        </ul>
    </div>

    <h3>Certificate Details:</h3>
    <table>
        <tr>
            <th>Domain</th>
            <th>Status</th>
            <th>Processed</th>
            <th>Details</th>
        </tr>
        $htmlResults
    </table>

    <p><strong>Completion Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p><strong>Runtime:</strong> $((Get-Date) - $script:StartTime)</p>
    <p><strong>System:</strong> $env:COMPUTERNAME</p>
</body>
</html>
"@

        Send-RenewalNotification -Subject $subject -Body $body -ToEmail $Config.NotificationEmail -Priority $priority
        Write-Log "Renewal notification sent to $($Config.NotificationEmail)" -Level 'Info'

    } catch {
        Write-Warning -Message "Failed to send renewal notification: $($_.Exception.Message)"
        Write-Log "Notification sending failed: $($_.Exception.Message)" -Level 'Warning'
    }
}

function Get-RenewalScheduleRecommendation {
    <#
    .SYNOPSIS
        Provides recommendations for renewal scheduling based on current certificates.
    #>
    [CmdletBinding()]
    param()

    try {
        $orders = Get-PAOrder
        if (-not $orders) {
            return @{
                HasCertificates = $false
                Recommendation = "No certificates found. Set up certificates first before scheduling renewals."
            }
        }

        $config = Get-RenewalConfig
        $renewalStatus = Get-CertificateRenewalStatus -Config $config

        # Analyze certificate expiration patterns
        $expirationDays = $renewalStatus | ForEach-Object { $_.DaysUntilExpiry }
        $avgDaysToExpiry = ($expirationDays | Measure-Object -Average).Average
        $minDaysToExpiry = ($expirationDays | Measure-Object -Minimum).Minimum

        # Generate recommendations
        $recommendations = @()

        # Frequency recommendation
        if ($minDaysToExpiry -le 7) {
            $recommendations += "URGENT: Run renewal immediately - certificates expiring within 7 days"
            $frequency = "Daily"
        } elseif ($minDaysToExpiry -le 30) {
            $recommendations += "Run renewal soon - certificates expiring within 30 days"
            $frequency = "Weekly"
        } else {
            $frequency = "Weekly"
        }

        # Time recommendation
        $recommendedHour = Get-Random -Minimum 2 -Maximum 6  # Early morning hours
        $recommendedMinute = Get-Random -Minimum 0 -Maximum 59

        $recommendations += "Recommended schedule: $frequency at $($recommendedHour.ToString('00')):$($recommendedMinute.ToString('00'))"
        $recommendations += "Use randomization to avoid peak times: Enable with 60-120 minute window"

        if ($orders.Count -gt 5) {
            $recommendations += "Consider staggered renewals for large certificate sets"
        }

        return @{
            HasCertificates = $true
            CertificateCount = $orders.Count
            MinDaysToExpiry = $minDaysToExpiry
            AverageDaysToExpiry = [math]::Round($avgDaysToExpiry, 1)
            RecommendedFrequency = $frequency
            RecommendedTime = "$($recommendedHour.ToString('00')):$($recommendedMinute.ToString('00'))"
            Recommendations = $recommendations
        }

    } catch {
        Write-Error -Message "Failed to analyze renewal schedule: $($_.Exception.Message)"
        return @{
            HasCertificates = $false
            Recommendation = "Error analyzing certificates: $($_.Exception.Message)"
        }
    }
}

# Export functions for module use
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Invoke-AutomatedRenewal, Send-RenewalNotificationSummary, Get-RenewalScheduleRecommendation



