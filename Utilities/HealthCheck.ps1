# System Health Check Module
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 8, 2025

<#
.SYNOPSIS
    Health check system for AutoCert
.DESCRIPTION
    Performs analysis of the certificate management system's health
    including PowerShell environment, module status, connectivity, certificates,
    file system, scheduled tasks, network connectivity, and system resources
.NOTES
    Returns a health score and provides recommendations for remediation
#>

function Test-SystemHealth {
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    SYSTEM HEALTH CHECK" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    $healthIssues = @()
    $healthWarnings = @()

    Write-Warning -Message "`nRunning system health check..."
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking components..." -PercentComplete 10

    # Check PowerShell version
    Write-Host -Object "`n1. PowerShell Environment:" -ForegroundColor Cyan
    $psVersion = $PSVersionTable.PSVersion
    Write-Information -MessageData "   Version: $psVersion" -InformationAction Continue
    Write-Information -MessageData "   Edition: $($PSVersionTable.PSEdition)" -InformationAction Continue
    Write-Information -MessageData "   Platform: $($PSVersionTable.Platform)" -InformationAction Continue

    if ($psVersion.Major -lt 5) {
        $healthIssues += "PowerShell version $psVersion is not supported. Minimum version 5.1 required."
    } elseif ($psVersion.Major -eq 5 -and $psVersion.Minor -eq 0) {
        $healthWarnings += "PowerShell 5.0 detected. Version 5.1 or later recommended for best compatibility."
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking modules..." -PercentComplete 20

    # Check Posh-ACME module
    Write-Host -Object "`n2. Posh-ACME Module:" -ForegroundColor Cyan
    try {
        $poshAcmeModule = Get-Module -Name Posh-ACME -ListAvailable | Select-Object -First 1
        if ($poshAcmeModule) {
            Write-Information -MessageData "   Installed: Version $($poshAcmeModule.Version)" -InformationAction Continue
            Write-Host -Object "   Path: $($poshAcmeModule.ModuleBase)" -ForegroundColor Gray

            # Test module import
            Import-Module Posh-ACME -Force
            Write-Information -MessageData "   Status: Loaded" -InformationAction Continue

            # Check for newer version
            try {
                $latestModule = Find-Module -Name Posh-ACME -ErrorAction Stop
                $latestVersion = $latestModule.Version
                if ($latestVersion -gt $poshAcmeModule.Version) {
                    Write-Warning -Message "   Update Available: Version $latestVersion"
                    $healthWarnings += "Posh-ACME module update available: $latestVersion (current: $($poshAcmeModule.Version))"
                } else {
                    Write-Information -MessageData "   Version Status: Up to date" -InformationAction Continue
                }
            } catch {
                Write-Verbose "Could not check for newer Posh-ACME version"
            }
        } else {
            $healthIssues += "Posh-ACME module not found"
        }
    } catch {
        $healthIssues += "Failed to load Posh-ACME module: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking script modules..." -PercentComplete 30

    # Check script modules
    Write-Host -Object "`n3. Script Modules:" -ForegroundColor Cyan
    Write-Information -MessageData "   Loaded Modules: $($script:LoadedModules.Count)" -InformationAction Continue
    $script:LoadedModules | ForEach-Object { Write-Host -Object "   • $_" -ForegroundColor Gray }

    if ($script:InitializationErrors.Count -gt 0) {
        Write-Warning -Message "   Initialization Errors: $($script:InitializationErrors.Count)"
        $script:InitializationErrors | ForEach-Object { $healthWarnings += "Module loading: $_" }
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking ACME connectivity..." -PercentComplete 40

    # Check ACME server connectivity
    Write-Host -Object "`n4. ACME Server Connectivity:" -ForegroundColor Cyan
    try {
        $server = Get-PAServer
        if ($server) {
            Write-Information -MessageData "   Server: $($server.Name)" -InformationAction Continue
            Write-Information -MessageData "   URL: $($server.location)" -InformationAction Continue

            # Test connectivity with timeout
            $connectivityTest = Invoke-WithRetry -ScriptBlock {
                $response = Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                return $response
            } -MaxAttempts 3 -InitialDelaySeconds 2 -OperationName "ACME server connectivity test"

            Write-Information -MessageData "   Connectivity: OK (Status: $($connectivityTest.StatusCode))" -InformationAction Continue
            Write-Host -Object "   Response Time: $((Measure-Command { Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 5 }).TotalMilliseconds.ToString('F0')) ms" -ForegroundColor Gray
        } else {
            $healthWarnings += "No ACME server configured"
        }
    } catch {
        $healthIssues += "ACME server connectivity failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking certificates..." -PercentComplete 50

    # Check certificate status
    Write-Host -Object "`n5. Certificate Status:" -ForegroundColor Cyan
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config

            Write-Information -MessageData "   Total Certificates: $($orders.Count)" -InformationAction Continue

            $expiringSoon = $renewalStatus | Where-Object { $_.NeedsRenewal }
            $criticallyExpiring = $renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }

            if ($criticallyExpiring) {
                Write-Error -Message "   Critically Expiring: $($criticallyExpiring.Count)"
                foreach ($cert in $criticallyExpiring) {
                    Write-Host -Object "    • $($cert.Domain) - Expires in $($cert.DaysUntilExpiry) days" -ForegroundColor Red
                }

                if ($criticallyExpiring.Count -gt 0) {
                    $healthIssues += "$($criticallyExpiring.Count) certificate(s) critically expiring within 7 days"
                }
            }

            if ($expiringSoon -and $expiringSoon.Count -gt $criticallyExpiring.Count) {
                $soonCount = $expiringSoon.Count - $criticallyExpiring.Count
                Write-Warning -Message "   Expiring Soon: $soonCount"
                foreach ($cert in ($expiringSoon | Where-Object { $_.DaysUntilExpiry -gt 7 })) {
                    Write-Host -Object "    • $($cert.Domain) - Expires in $($cert.DaysUntilExpiry) days" -ForegroundColor Yellow
                }
                $healthWarnings += "$soonCount certificate(s) need renewal within $($config.RenewalThresholdDays) days"
            }

            if (-not $expiringSoon) {
                Write-Information -MessageData "   All certificates valid" -InformationAction Continue
            }

            # Check certificate integrity
            $integrityIssues = 0
            foreach ($order in $orders) {
                try {
                    $cert = Get-PACertificate -MainDomain $order.MainDomain -ErrorAction Stop
                    if (-not (Test-Path $cert.CertFile) -or -not (Test-Path $cert.KeyFile)) {
                        $integrityIssues++
                    }
                } catch {
                    $integrityIssues++
                }
            }

            if ($integrityIssues -gt 0) {
                $healthWarnings += "$integrityIssues certificate(s) have integrity issues"
            }

        } else {
            Write-Host -Object "   No certificates configured" -ForegroundColor Gray
        }
    } catch {
        $healthWarnings += "Certificate status check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking file system..." -PercentComplete 60

    # Check file system permissions and paths
    Write-Host -Object "`n6. File System:" -ForegroundColor Cyan
    try {
        $appDataPath = "$env:LOCALAPPDATA\Posh-ACME"
        if (Test-Path $appDataPath) {
            Write-Information -MessageData "   Data Directory: $appDataPath" -InformationAction Continue

            # Check directory size
            $dirSize = (Get-ChildItem $appDataPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $dirSizeMB = [math]::Round($dirSize / 1MB, 2)
            Write-Host -Object "   Directory Size: $dirSizeMB MB" -ForegroundColor Gray

            # Test write permissions
            $testFile = Join-Path $appDataPath "health_check_test.tmp"
            try {
                "health check test" | Out-File -FilePath $testFile
                Remove-Item $testFile -Force
                Write-Information -MessageData "   Write Permissions: OK" -InformationAction Continue
            } catch {
                $healthIssues += "Cannot write to Posh-ACME data directory"
            }
        } else {
            $healthWarnings += "Posh-ACME data directory does not exist"
        }

        # Check certificate stores
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
        try {
            $store.Open("ReadOnly")
            $certCount = $store.Certificates.Count
            Write-Information -MessageData "   Certificate Store: $certCount certificates in LocalMachine\\My" -InformationAction Continue

            # Test store write access
            try {
                $testStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                $testStore.Open("ReadWrite")
                $testStore.Close()
                Write-Information -MessageData "   Store Write Access: OK" -InformationAction Continue
            } catch {
                $healthWarnings += "Limited access to certificate store (may affect installation)"
            }
        } catch {
            $healthIssues += "Cannot access certificate store"
        } finally {
            $store.Close()
        }

    } catch {
        $healthWarnings += "File system check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking scheduled tasks..." -PercentComplete 70

    # Check scheduled tasks and automation
    Write-Host -Object "`n7. Automatic Renewal:" -ForegroundColor Cyan
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            Write-Information -MessageData "   Scheduled Task: Configured" -InformationAction Continue
            Write-Host -Object "   State: $($task.State)" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
            Write-Host -Object "   Last Run: $($task.LastRunTime)" -ForegroundColor Gray
            Write-Host -Object "   Next Run: $($task.NextRunTime)" -ForegroundColor Gray
            Write-Host -Object "   Last Result: $($task.LastTaskResult)" -ForegroundColor $(if ($task.LastTaskResult -eq 0) { "Green" } else { "Red" })

            if ($task.State -ne "Ready") {
                $healthWarnings += "Scheduled task is not in Ready state: $($task.State)"
            }

            if ($task.LastTaskResult -ne 0 -and $task.LastTaskResult -ne 267009) { # 267009 = never run
                $healthWarnings += "Scheduled task last execution failed (code: $($task.LastTaskResult))"
            }
        } else {
            Write-Warning -Message "   Scheduled Task: Not configured"
            $healthWarnings += "Automatic renewal not configured"
        }

        # Check task schedule validity
        if ($task) {
            $config = Get-RenewalConfig
            if ($config.UseRandomization -and $config.RandomizationWindow -gt 1440) {
                $healthWarnings += "Renewal randomization window is too large ($($config.RandomizationWindow) minutes)"
            }
        }
    } catch {
        $healthWarnings += "Scheduled task check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking network and DNS..." -PercentComplete 80

    # Check network connectivity and DNS
    Write-Host -Object "`n8. Network and DNS:" -ForegroundColor Cyan
    try {
        # Test internet connectivity
        $internetHosts = @("8.8.8.8", "1.1.1.1", "208.67.222.222")
        $connectableHosts = 0

        foreach ($testHost in $internetHosts) {
            if (Test-Connection -ComputerName $testHost -Count 1 -Quiet -TimeoutSec 3) {
                $connectableHosts++
            }
        }

        if ($connectableHosts -gt 0) {
            Write-Information -MessageData "   Internet Connectivity: OK ($connectableHosts/$($internetHosts.Count) DNS servers reachable)" -InformationAction Continue
        } else {
            $healthIssues += "No internet connectivity detected"
        }

        # Test DNS resolution
        try {
            Resolve-DnsName -Name "letsencrypt.org" -Type A -ErrorAction Stop | Out-Null
            Write-Information -MessageData "   DNS Resolution: OK" -InformationAction Continue
        } catch {
            $healthIssues += "DNS resolution failed: $($_.Exception.Message)"
        }

        # Check proxy settings
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            Write-Warning -Message "   Proxy: Enabled ($($proxySettings.ProxyServer))"
            $healthWarnings += "Proxy is enabled, may affect ACME operations"
        } else {
            Write-Information -MessageData "   Proxy: Direct connection" -InformationAction Continue
        }

    } catch {
        $healthWarnings += "Network check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking event logging..." -PercentComplete 90

    # Check event logging
    Write-Host -Object "`n9. Event Logging:" -ForegroundColor Cyan
    try {
        # Test event log source registration
        $eventSources = Get-WinEvent -ListProvider "Certificate Management" -ErrorAction SilentlyContinue
        if ($eventSources) {
            Write-Information -MessageData "   Event Source: Registered" -InformationAction Continue
        } else {
            Write-Warning -Message "   Event Source: Not registered"
            $healthWarnings += "Event log source 'Certificate Management' not registered"
        }

        # Test event log writing
        try {
            New-EventLog -LogName Application -Source "Certificate Management" -ErrorAction SilentlyContinue
            Write-EventLog -LogName Application -Source "Certificate Management" -EventId 9999 -Message "Health check test event" -ErrorAction Stop
            Write-Information -MessageData "   Event Writing: OK" -InformationAction Continue
        } catch {
            $healthWarnings += "Cannot write to event log: $($_.Exception.Message)"
        }

    } catch {
        $healthWarnings += "Event logging check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Finalizing health check..." -PercentComplete 95

    # Check system resources
    Write-Host -Object "`n10. System Resources:" -ForegroundColor Cyan
    try {
        $memory = Get-CimInstance -ClassName Win32_ComputerSystem
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        Write-Information -MessageData "   Total Memory: $totalMemoryGB GB" -InformationAction Continue

        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $memoryUsage = [math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 1)
        Write-Host -Object "   Memory Usage: $memoryUsage%" -ForegroundColor $(if ($memoryUsage -lt 80) { "Green" } else { "Yellow" })

        if ($memoryUsage -gt 90) {
            $healthWarnings += "High memory usage detected: $memoryUsage%"
        }

        # Check available disk space
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
        $diskUsage = [math]::Round((($totalSpaceGB - $freeSpaceGB) / $totalSpaceGB) * 100, 1)

        Write-Host -Object "   Disk Space: $freeSpaceGB GB free ($diskUsage% used)" -ForegroundColor $(if ($diskUsage -lt 80) { "Green" } else { "Yellow" })

        if ($freeSpaceGB -lt 1) {
            $healthIssues += "Low disk space: Only $freeSpaceGB GB free"
        } elseif ($freeSpaceGB -lt 5) {
            $healthWarnings += "Limited disk space: $freeSpaceGB GB free"
        }

    } catch {
        $healthWarnings += "System resource check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Health check complete" -PercentComplete 100
    Write-Progress -Activity "System Health Check" -Completed

    # Display summary
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "HEALTH CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    if ($healthIssues.Count -eq 0 -and $healthWarnings.Count -eq 0) {
        Write-Information -MessageData "✓ System health: EXCELLENT" -InformationAction Continue
        Write-Information -MessageData "  All components are functioning optimally." -InformationAction Continue
        Write-Information -MessageData "  No issues or warnings detected." -InformationAction Continue
    } elseif ($healthIssues.Count -eq 0) {
        Write-Warning -Message "⚠ System health: GOOD (with warnings)"
        Write-Warning -Message "  System is functional but some optimization is recommended."
        Write-Warning -Message "`n  Warnings detected:"
        $healthWarnings | ForEach-Object { Write-Warning -Message "    • $_" }
    } else {
        Write-Error -Message "✗ System health: NEEDS ATTENTION"
        Write-Error -Message "  Critical issues require immediate attention."
        Write-Error -Message "`n  Critical issues:"
        $healthIssues | ForEach-Object { Write-Error -Message "    • $_" }

        if ($healthWarnings.Count -gt 0) {
            Write-Warning -Message "`n  Additional warnings:"
            $healthWarnings | ForEach-Object { Write-Warning -Message "    • $_" }
        }
    }

    # Health score calculation
    $issueScore = $healthIssues.Count * 3
    $warningScore = $healthWarnings.Count * 1
    $healthScore = [math]::Max(0, 100 - $issueScore - $warningScore)

    Write-Host -Object "`nHealth Score: $healthScore/100" -ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
    Write-Warning -Message "Issues: $($healthIssues.Count) critical, $($healthWarnings.Count) warnings" -ForegroundColor White
    Write-Host -Object "Check completed: $(Get-Date)" -ForegroundColor Gray
    Write-Host -Object "Check duration: $((Get-Date) - $script:StartTime)" -ForegroundColor Gray

    # Recommendations based on health status
    if ($healthIssues.Count -gt 0 -or $healthWarnings.Count -gt 0) {
        Write-Host -Object "`nRecommended Actions:" -ForegroundColor Cyan

        if ($healthIssues.Count -gt 0) {
            Write-Error -Message "• Address critical issues immediately before proceeding"
            Write-Host -Object "• Run configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor Red
        }

        if ($healthWarnings.Count -gt 0) {
            Write-Warning -Message "• Review warnings and optimize system configuration"
            Write-Warning -Message "• Consider setting up monitoring for detected issues"
        }

        Write-Host -Object "• Check log files for additional details" -ForegroundColor White
        Write-Host -Object "• Verify network connectivity and DNS resolution" -ForegroundColor White
        Write-Host -Object "• Ensure sufficient system resources are available" -ForegroundColor White
    }

    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan

    # Log health check results
    Write-Log "System health check completed - Score: $healthScore/100, Issues: $($healthIssues.Count), Warnings: $($healthWarnings.Count)" -Level 'Info'

    Read-Host "Press Enter to return to the main menu"
}

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Test-SystemHealth




