# RenewalOperations.ps1
# Certificate renewal and automation functions

function Invoke-AutomaticRenewal
{
    <#
    .SYNOPSIS
        Executes automatic certificate renewal process

    .DESCRIPTION
        Handles the automatic renewal of all certificates that need renewal.
        Designed for scheduled task execution with comprehensive reporting.

    .PARAMETER Force
        Forces renewal even if certificates are not yet due

    .OUTPUTS
        Exit code: 0 for success, 1 for failure
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [switch]$Force
    )

    Write-Information -MessageData "Running in automatic renewal mode..." -InformationAction Continue
    Write-Log "Starting automatic renewal process (Version: $script:ScriptVersion)" -Level 'Info'

    try
    {
        $completeViewConfig = Get-CompleteViewDeploymentConfig -ErrorAction SilentlyContinue
        if ($completeViewConfig -and $completeViewConfig.Enabled) {
            Write-Information -MessageData "CompleteView deployment detected. Running CompleteView renewal orchestration..." -InformationAction Continue
            $cvResult = Update-CompleteViewCertificates -Force:$Force
            if ($cvResult.Success) {
                Write-Log "CompleteView automatic renewal completed successfully" -Level 'Info'
                return 0
            }

            Write-Log "CompleteView automatic renewal completed with failures" -Level 'Error'
            return 1
        }

        # Load renewal configuration
        $config = Get-RenewalConfig

        # Get all certificates and check renewal status
        $orders = Get-PAOrder
        if (-not $orders)
        {
            Write-Warning -Message "No certificates found to renew."
            Write-Log "No certificates found for renewal" -Level 'Warning'
            return 0
        }

        Write-Information -MessageData "Found $($orders.Count) certificate(s) to check for renewal." -InformationAction Continue

        $renewalCount = 0
        $errorCount = 0
        $skippedCount = 0
        $results = @()

        foreach ($order in $orders)
        {
            $mainDomain = $order.MainDomain
            Write-Information -MessageData "`nProcessing certificate for $mainDomain..." -InformationAction Continue

            try
            {
                # Check if renewal is needed
                $cert = Get-PACertificate -MainDomain $mainDomain
                $daysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days

                $result = [PSCustomObject]@{
                    Domain          = $mainDomain
                    Status          = ""
                    ExpiryDate      = $cert.Certificate.NotAfter.ToString('yyyy-MM-dd')
                    DaysUntilExpiry = $daysUntilExpiry
                    Error           = $null
                }

                if ($Force -or $daysUntilExpiry -le $config.RenewalThresholdDays)
                {
                    Write-Information -MessageData "Renewing certificate for $mainDomain (expires in $daysUntilExpiry days)..." -InformationAction Continue

                    # Attempt renewal with retries
                    $renewed = Invoke-WithRetry -ScriptBlock {
                        return New-PACertificate -MainDomain $mainDomain -Force
                    } -MaxAttempts 3 -InitialDelaySeconds 30 -OperationName "Certificate renewal for $mainDomain"

                    if ($renewed)
                    {
                        Write-Information -MessageData "Successfully renewed certificate for $mainDomain" -InformationAction Continue
                        $result.Status = "Renewed"
                        $renewalCount++

                        # Install the renewed certificate
                        Install-Certificate -PACertificate $renewed

                        Write-Log "Certificate renewed successfully: $mainDomain" -Level 'Success'
                    } else
                    {
                        throw "Renewal returned null result"
                    }
                } else
                {
                    Write-Information -MessageData "Certificate for $mainDomain is still valid ($daysUntilExpiry days remaining)" -InformationAction Continue
                    $result.Status = "Valid"
                    $skippedCount++
                }

                $results += $result
            } catch
            {
                $errorMsg = "Failed to renew certificate for ${mainDomain}: $($_.Exception.Message)"
                Write-Error -Message $errorMsg
                Write-Log $errorMsg -Level 'Error'

                $result.Status = "Failed"
                $result.Error = $_.Exception.Message
                $results += $result
                $errorCount++
            }
        }

        # Generate renewal summary
        Write-Information -MessageData "`n" + "="*60 -InformationAction Continue
        Write-Information -MessageData "AUTOMATIC RENEWAL SUMMARY" -InformationAction Continue
        Write-Information -MessageData "="*60 -InformationAction Continue
        Write-Information -MessageData "Certificates processed: $($orders.Count)" -InformationAction Continue
        Write-Information -MessageData "Successful renewals: $renewalCount" -InformationAction Continue
        Write-Warning -Message "Skipped (still valid): $skippedCount"
        Write-Error -Message "Failed renewals: $errorCount"
        Write-Information -MessageData "Completion time: $(Get-Date)" -InformationAction Continue
        Write-Information -MessageData "Total runtime: $((Get-Date) - $script:StartTime)" -InformationAction Continue

        # Results table
        if ($results.Count -gt 0)
        {
            Write-Information -MessageData "`nResults:" -InformationAction Continue
            foreach ($result in $results)
            {
                $statusLine = "$($result.Domain): $($result.Status)"
                if ($result.Status -eq "Failed" -and $result.Error)
                {
                    $statusLine += " - $($result.Error)"
                } elseif ($result.ExpiryDate -ne "Unknown")
                {
                    $statusLine += " (expires $($result.ExpiryDate))"
                }

                Write-Information -MessageData "  $statusLine" -InformationAction Continue
            }
        }

        # Send summary email if configured
        if ($config.EmailNotifications -and $config.NotificationEmail -and ($renewalCount -gt 0 -or $errorCount -gt 0))
        {
            Send-RenewalSummaryEmail -Results $results -Config $config -RenewalCount $renewalCount -ErrorCount $errorCount -SkippedCount $skippedCount
        }

        Write-Log "Automatic renewal completed - Renewed: $renewalCount, Failed: $errorCount, Skipped: $skippedCount" -Level 'Info'

        # Return appropriate exit code
        return $(if ($errorCount -gt 0) { 1 } else { 0 })

    } catch
    {
        $msg = "Critical error during automatic renewal: $($_.Exception.Message)"
        Write-Error -Message $msg
        Write-Log $msg -Level 'Error'

        # Send critical error notification
        $config = Get-RenewalConfig
        if ($config.EmailNotifications -and $config.NotificationEmail)
        {
            Send-RenewalNotification -Subject "Critical Certificate Renewal Error" -Body $msg -ToEmail $config.NotificationEmail
        }

        return 1
    }
}

function Send-RenewalSummaryEmail
{
    <#
    .SYNOPSIS
        Sends email summary of renewal operations

    .DESCRIPTION
        Generates and sends an HTML email with detailed renewal results

    .PARAMETER Results
        Array of renewal result objects

    .PARAMETER Config
        Renewal configuration object

    .PARAMETER RenewalCount
        Number of successful renewals

    .PARAMETER ErrorCount
        Number of failed renewals

    .PARAMETER SkippedCount
        Number of skipped certificates
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Results,

        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [int]$RenewalCount,

        [Parameter(Mandatory = $true)]
        [int]$ErrorCount,

        [Parameter(Mandatory = $true)]
        [int]$SkippedCount
    )

    $subject = "Certificate Renewal Summary - $RenewalCount renewed, $ErrorCount failed"

    # Generate detailed HTML results for email
    $htmlResults = ConvertTo-HtmlFragment -InputObject $Results

    $body = @"
<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: Arial, sans-serif; }
        h2 { color: #333; }
        .summary { margin-bottom: 20px; }
        .summary-table { border-collapse: collapse; width: 400px; }
        .summary-table td { padding: 5px; border: 1px solid #ddd; }
        .summary-label { font-weight: bold; }
        .results-table { border-collapse: collapse; width: 100%; }
        .results-table th, .results-table td { padding: 8px; text-align: left; border: 1px solid #ddd; }
        .results-table th { background-color: #f2f2f2; }
        .status-renewed { color: green; }
        .status-skipped { color: orange; }
        .status-failed { color: red; }
    </style>
</head>
<body>
    <h2>Certificate Renewal Summary</h2>
    <div class="summary">
        <table class="summary-table">
            <tr><td class="summary-label">Processed</td><td>$($Results.Count) certificates</td></tr>
            <tr><td class="summary-label">Renewed</td><td>$RenewalCount</td></tr>
            <tr><td class="summary-label">Skipped</td><td>$SkippedCount</td></tr>
            <tr><td class="summary-label">Failed</td><td>$ErrorCount</td></tr>
        </table>
    </div>
    <h3>Results:</h3>
    $htmlResults
    <p>Completion Time: $(Get-Date -Format 'u')</p>
    <p>Runtime: $((Get-Date) - $script:StartTime)</p>
</body>
</html>
"@

    Send-RenewalNotification -Subject $subject -Body $body -ToEmail $Config.NotificationEmail -BodyAsHtml
}

# Note: Invoke-MenuOperation is implemented in Utilities\ErrorHandling.ps1
# This avoids duplication and provides consistent error handling across the application
