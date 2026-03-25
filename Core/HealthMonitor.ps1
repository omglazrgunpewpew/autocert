# Core/HealthMonitor.ps1
<#
    .SYNOPSIS
        Health monitoring and alerting system.
#>
class HealthCheck {
    [string]$Name
    [scriptblock]$CheckScript
    [int]$TimeoutSeconds
    [string]$Category
    [string]$Description
    [string]$SeverityLevel
    [bool]$IsCritical
    HealthCheck([string]$Name, [scriptblock]$CheckScript, [int]$TimeoutSeconds, [string]$Category, [string]$Description, [string]$SeverityLevel, [bool]$IsCritical) {
        $this.Name = $Name
        $this.CheckScript = $CheckScript
        $this.TimeoutSeconds = $TimeoutSeconds
        $this.Category = $Category
        $this.Description = $Description
        $this.SeverityLevel = $SeverityLevel
        $this.IsCritical = $IsCritical
    }
    [hashtable] Execute() {
        $result = @{
            Name = $this.Name
            Category = $this.Category
            Description = $this.Description
            Status = 'Unknown'
            Message = ''
            Duration = 0
            Timestamp = Get-Date
            IsCritical = $this.IsCritical
            SeverityLevel = $this.SeverityLevel
        }
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $job = Start-Job -ScriptBlock $this.CheckScript -ArgumentList $this
            if (Wait-Job -Job $job -Timeout $this.TimeoutSeconds) {
                $jobResult = Receive-Job -Job $job
                $result.Status = 'Pass'
                $result.Message = if ($jobResult) { $jobResult.ToString() } else { 'Check completed' }
            } else {
                $result.Status = 'Fail'
                $result.Message = "Health check timed out after $($this.TimeoutSeconds) seconds"
            }
            Remove-Job -Job $job -Force
            $stopwatch.Stop()
            $result.Duration = $stopwatch.ElapsedMilliseconds
        } catch {
            $result.Status = 'Fail'
            $result.Message = $_.Exception.Message
        }
        return $result
    }
}
function Initialize-HealthChecks {
    [CmdletBinding()]
    [OutputType([void])]
    param()
    $script:HealthChecks = @{
        'PowerShellVersion' = [HealthCheck]::new(
            'PowerShellVersion',
            {
                if ($PSVersionTable.PSVersion.Major -lt 5) {
                    throw "PowerShell version $($PSVersionTable.PSVersion) is not supported. Minimum version is 5.1"
                }
                return "PowerShell version $($PSVersionTable.PSVersion) is supported"
            },
            10,
            'System',
            'Validates PowerShell version compatibility',
            'High',
            $true
        )
        'AdminPrivileges' = [HealthCheck]::new(
            'AdminPrivileges',
            {
                $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
                if (-not $isAdmin) {
                    throw "Administrator privileges required for certificate operations"
                }
                return "Running with administrator privileges"
            },
            5,
            'Security',
            'Validates administrator privileges',
            'Critical',
            $true
        )
        'PoshACMEModule' = [HealthCheck]::new(
            'PoshACMEModule',
            {
                $module = Get-Module -ListAvailable -Name Posh-ACME
                if (-not $module) {
                    throw "Posh-ACME module not found"
                }
                return "Posh-ACME module version $($module.Version) is available"
            },
            15,
            'Dependencies',
            'Validates Posh-ACME module availability',
            'Critical',
            $true
        )
        'NetworkConnectivity' = [HealthCheck]::new(
            'NetworkConnectivity',
            {
                $testResults = @()
                $servers = @("acme-v02.api.letsencrypt.org", "8.8.8.8", "1.1.1.1")
                foreach ($server in $servers) {
                    try {
                        $result = Test-NetConnection -ComputerName $server -Port 443 -WarningAction SilentlyContinue
                        if ($result.TcpTestSucceeded) {
                            $testResults += "✓ $server"
                        } else {
                            $testResults += "✗ $server"
                        }
                    } catch {
                        $testResults += "✗ $server (Error: $($_.Exception.Message))"
                    }
                }
                return "Network connectivity: $($testResults -join ', ')"
            },
            30,
            'Network',
            'Tests network connectivity to key services',
            'High',
            $true
        )
        'CertificateStore' = [HealthCheck]::new(
            'CertificateStore',
            {
                try {
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                    $store.Open("ReadWrite")
                    $store.Close()
                    return "Certificate store access verified"
                } catch {
                    throw "Cannot access certificate store: $($_.Exception.Message)"
                }
            },
            10,
            'Security',
            'Validates certificate store access',
            'High',
            $true
        )
        'DiskSpace' = [HealthCheck]::new(
            'DiskSpace',
            {
                $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
                $freeSpaceGB = [math]::Round($drive.FreeSpace / 1GB, 2)
                if ($freeSpaceGB -lt 1) {
                    throw "Insufficient disk space: $freeSpaceGB GB free"
                }
                return "Disk space: $freeSpaceGB GB free"
            },
            10,
            'System',
            'Validates available disk space',
            'Medium',
            $false
        )
        'LogFileAccess' = [HealthCheck]::new(
            'LogFileAccess',
            {
                $logPath = "$env:LOCALAPPDATA\PoshACME\certificate_script.log"
                $logDir = Split-Path -Path $logPath -Parent
                if (-not (Test-Path $logDir)) {
                    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
                }
                try {
                    "Health check test" | Out-File -FilePath $logPath -Append
                    return "Log file access verified"
                } catch {
                    throw "Cannot write to log file: $($_.Exception.Message)"
                }
            },
            10,
            'System',
            'Validates log file write access',
            'Medium',
            $false
        )
        'ScheduledTaskAccess' = [HealthCheck]::new(
            'ScheduledTaskAccess',
            {
                try {
                    $tasks = Get-ScheduledTask -TaskName "*AutoCert*" -ErrorAction SilentlyContinue
                    return "Scheduled task access verified (Found $($tasks.Count) AutoCert tasks)"
                } catch {
                    throw "Cannot access scheduled tasks: $($_.Exception.Message)"
                }
            },
            15,
            'System',
            'Validates scheduled task access',
            'Medium',
            $false
        )
        'CertificateExpiry' = [HealthCheck]::new(
            'CertificateExpiry',
            {
                try {
                    Import-Module Posh-ACME -Force
                    $orders = Get-PAOrder -ErrorAction SilentlyContinue
                    if ($orders) {
                        $expiringSoon = @()
                        foreach ($order in $orders) {
                            try {
                                $cert = Get-PACertificate -MainDomain $order.MainDomain -ErrorAction SilentlyContinue
                                if ($cert -and $cert.NotAfter) {
                                    $daysUntilExpiry = ($cert.NotAfter - (Get-Date)).Days
                                    if ($daysUntilExpiry -lt 30) {
                                        $expiringSoon += "$($order.MainDomain) ($daysUntilExpiry days)"
                                    }
                                }
                            } catch {
                                Write-Log "Failed to load certificate for $($order.MainDomain): $($_.Exception.Message)" -Level 'Warning'
                                # Skip certificates that can't be loaded
                            }
                        }
                        if ($expiringSoon.Count -gt 0) {
                            throw "Certificates expiring soon: $($expiringSoon -join ', ')"
                        }
                        return "All certificates have sufficient validity period"
                    } else {
                        return "No certificates found to check"
                    }
                } catch {
                    throw "Certificate expiry check failed: $($_.Exception.Message)"
                }
            },
            30,
            'Certificates',
            'Monitors certificate expiration dates',
            'High',
            $false
        )
    }
}

function Initialize-HealthCheck {
    [CmdletBinding()]
    param()
    Initialize-HealthChecks
}
function Invoke-HealthCheck {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable[]])]
    param(
        [string[]]$CheckNames = @(),
        [string[]]$Categories = @(),
        [switch]$CriticalOnly,
        [switch]$Detailed
    )
    if (-not $script:HealthChecks) {
        Initialize-HealthChecks
    }
    $checksToRun = @()
    if ($CheckNames.Count -gt 0) {
        $checksToRun = $script:HealthChecks.Keys | Where-Object { $CheckNames -contains $_ }
    } elseif ($Categories.Count -gt 0) {
        $checksToRun = $script:HealthChecks.Keys | Where-Object { $Categories -contains $script:HealthChecks[$_].Category }
    } else {
        $checksToRun = $script:HealthChecks.Keys
    }
    if ($CriticalOnly) {
        $checksToRun = $checksToRun | Where-Object { $script:HealthChecks[$_].IsCritical }
    }
    $results = @()
    $totalChecks = $checksToRun.Count
    $currentCheck = 0
    foreach ($checkName in $checksToRun) {
        $currentCheck++
        if (-not $NonInteractive) {
            Write-Progress -Activity "Running Health Checks" -Status "Running: $checkName" -PercentComplete (($currentCheck / $totalChecks) * 100)
        }
        $result = $script:HealthChecks[$checkName].Execute()
        $results += $result
        if ($Detailed) {
            $status = if ($result.Status -eq 'Pass') { '✓' } else { '✗' }
            $message = "$status $($result.Name): $($result.Message)"
            if ($result.Status -eq 'Pass') {
                Write-Information -MessageData $message -InformationAction Continue
            } else {
                Write-Warning -Message $message
            }
        }
    }
    if (-not $NonInteractive) {
        Write-Progress -Activity "Running Health Checks" -Completed
    }
    return $results
}
function Get-HealthReport {
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param(
        [hashtable[]]$HealthResults
    )
    $report = @{
        Timestamp = Get-Date
        TotalChecks = $HealthResults.Count
        PassedChecks = ($HealthResults | Where-Object { $_.Status -eq 'Pass' }).Count
        FailedChecks = ($HealthResults | Where-Object { $_.Status -eq 'Fail' }).Count
        CriticalFailures = ($HealthResults | Where-Object { $_.Status -eq 'Fail' -and $_.IsCritical }).Count
        OverallStatus = 'Unknown'
        Details = $HealthResults
        Recommendations = @()
    }
    if ($report.CriticalFailures -gt 0) {
        $report.OverallStatus = 'Critical'
        $report.Recommendations += "Address critical failures immediately"
    } elseif ($report.FailedChecks -gt 0) {
        $report.OverallStatus = 'Warning'
        $report.Recommendations += "Review and address non-critical failures"
    } else {
        $report.OverallStatus = 'Healthy'
    }
    # Add specific recommendations based on failures
    $failedChecks = $HealthResults | Where-Object { $_.Status -eq 'Fail' }
    foreach ($failure in $failedChecks) {
        switch ($failure.Name) {
            'PowerShellVersion' { $report.Recommendations += "Update PowerShell to version 5.1 or later" }
            'AdminPrivileges' { $report.Recommendations += "Run the script as Administrator" }
            'NetworkConnectivity' { $report.Recommendations += "Check firewall and internet connectivity" }
            'CertificateStore' { $report.Recommendations += "Verify certificate store permissions" }
            'DiskSpace' { $report.Recommendations += "Free up disk space on system drive" }
            'CertificateExpiry' { $report.Recommendations += "Schedule certificate renewal immediately" }
        }
    }
    return $report
}
function Send-HealthAlert {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$HealthReport,
        [string]$EmailAddress,
        [string]$Subject = "AutoCert Health Alert"
    )
    if (-not $EmailAddress) {
        $config = Get-RenewalConfig
        if ($config.EmailNotifications -and $config.NotificationEmail) {
            $EmailAddress = $config.NotificationEmail
        } else {
            Write-Log "No email address configured for health alerts" -Level 'Warning'
            return
        }
    }
    $body = @"
AutoCert Health Report
======================
Overall Status: $($HealthReport.OverallStatus)
Timestamp: $($HealthReport.Timestamp)
Summary:
- Total Checks: $($HealthReport.TotalChecks)
- Passed: $($HealthReport.PassedChecks)
- Failed: $($HealthReport.FailedChecks)
- Critical Failures: $($HealthReport.CriticalFailures)
"@
    if ($HealthReport.CriticalFailures -gt 0 -or $HealthReport.FailedChecks -gt 0) {
        $body += "`nFailed Checks:`n"
        $failedChecks = $HealthReport.Details | Where-Object { $_.Status -eq 'Fail' }
        foreach ($failure in $failedChecks) {
            $body += "- $($failure.Name): $($failure.Message)`n"
        }
    }
    if ($HealthReport.Recommendations.Count -gt 0) {
        $body += "`nRecommendations:`n"
        foreach ($rec in $HealthReport.Recommendations) {
            $body += "- $rec`n"
        }
    }
    try {
        Send-MailMessage -To $EmailAddress -Subject $Subject -Body $body -SmtpServer "localhost" -ErrorAction Stop
        Write-Log "Health alert sent to $EmailAddress" -Level 'Info'
    } catch {
        Write-Log "Failed to send health alert: $($_.Exception.Message)" -Level 'Error'
    }
}

