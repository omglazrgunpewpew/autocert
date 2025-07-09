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
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    SYSTEM HEALTH CHECK" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    $healthIssues = @()
    $healthWarnings = @()
    
    Write-Host "`nRunning system health check..." -ForegroundColor Yellow
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking components..." -PercentComplete 10
    
    # Check PowerShell version
    Write-Host "`n1. PowerShell Environment:" -ForegroundColor Cyan
    $psVersion = $PSVersionTable.PSVersion
    Write-Host "   Version: $psVersion" -ForegroundColor Green
    Write-Host "   Edition: $($PSVersionTable.PSEdition)" -ForegroundColor Green
    Write-Host "   Platform: $($PSVersionTable.Platform)" -ForegroundColor Green
    
    if ($psVersion.Major -lt 5) {
        $healthIssues += "PowerShell version $psVersion is not supported. Minimum version 5.1 required."
    } elseif ($psVersion.Major -eq 5 -and $psVersion.Minor -eq 0) {
        $healthWarnings += "PowerShell 5.0 detected. Version 5.1 or later recommended for best compatibility."
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking modules..." -PercentComplete 20
    
    # Check Posh-ACME module
    Write-Host "`n2. Posh-ACME Module:" -ForegroundColor Cyan
    try {
        $poshAcmeModule = Get-Module -Name Posh-ACME -ListAvailable | Select-Object -First 1
        if ($poshAcmeModule) {
            Write-Host "   Installed: Version $($poshAcmeModule.Version)" -ForegroundColor Green
            Write-Host "   Path: $($poshAcmeModule.ModuleBase)" -ForegroundColor Gray
            
            # Test module import
            Import-Module Posh-ACME -Force
            Write-Host "   Status: Loaded" -ForegroundColor Green
            
            # Check for newer version
            try {
                $latestModule = Find-Module -Name Posh-ACME -ErrorAction Stop
                $latestVersion = $latestModule.Version
                if ($latestVersion -gt $poshAcmeModule.Version) {
                    Write-Host "   Update Available: Version $latestVersion" -ForegroundColor Yellow
                    $healthWarnings += "Posh-ACME module update available: $latestVersion (current: $($poshAcmeModule.Version))"
                } else {
                    Write-Host "   Version Status: Up to date" -ForegroundColor Green
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
    Write-Host "`n3. Script Modules:" -ForegroundColor Cyan
    Write-Host "   Loaded Modules: $($script:LoadedModules.Count)" -ForegroundColor Green
    $script:LoadedModules | ForEach-Object { Write-Host "   • $_" -ForegroundColor Gray }
    
    if ($script:InitializationErrors.Count -gt 0) {
        Write-Host "   Initialization Errors: $($script:InitializationErrors.Count)" -ForegroundColor Yellow
        $script:InitializationErrors | ForEach-Object { $healthWarnings += "Module loading: $_" }
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking ACME connectivity..." -PercentComplete 40
    
    # Check ACME server connectivity
    Write-Host "`n4. ACME Server Connectivity:" -ForegroundColor Cyan
    try {
        $server = Get-PAServer
        if ($server) {
            Write-Host "   Server: $($server.Name)" -ForegroundColor Green
            Write-Host "   URL: $($server.location)" -ForegroundColor Green
            
            # Test connectivity with timeout
            $connectivityTest = Invoke-WithRetry -ScriptBlock {
                $response = Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                return $response
            } -MaxAttempts 3 -InitialDelaySeconds 2 -OperationName "ACME server connectivity test"
            
            Write-Host "   Connectivity: OK (Status: $($connectivityTest.StatusCode))" -ForegroundColor Green
            Write-Host "   Response Time: $((Measure-Command { Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 5 }).TotalMilliseconds.ToString('F0')) ms" -ForegroundColor Gray
        } else {
            $healthWarnings += "No ACME server configured"
        }
    } catch {
        $healthIssues += "ACME server connectivity failed: $($_.Exception.Message)"
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking certificates..." -PercentComplete 50
    
    # Check certificate status
    Write-Host "`n5. Certificate Status:" -ForegroundColor Cyan
    try {
        $orders = Get-PAOrder
        if ($orders) {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config
            
            Write-Host "   Total Certificates: $($orders.Count)" -ForegroundColor Green
            
            $expiringSoon = $renewalStatus | Where-Object { $_.NeedsRenewal }
            $criticallyExpiring = $renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }
            
            if ($criticallyExpiring) {
                Write-Host "   Critically Expiring: $($criticallyExpiring.Count)" -ForegroundColor Red
                foreach ($cert in $criticallyExpiring) {
                    Write-Host "    • $($cert.Domain) - Expires in $($cert.DaysUntilExpiry) days" -ForegroundColor Red
                }
                
                if ($criticallyExpiring.Count -gt 0) {
                    $healthIssues += "$($criticallyExpiring.Count) certificate(s) critically expiring within 7 days"
                }
            }
            
            if ($expiringSoon -and $expiringSoon.Count -gt $criticallyExpiring.Count) {
                $soonCount = $expiringSoon.Count - $criticallyExpiring.Count
                Write-Host "   Expiring Soon: $soonCount" -ForegroundColor Yellow
                foreach ($cert in ($expiringSoon | Where-Object { $_.DaysUntilExpiry -gt 7 })) {
                    Write-Host "    • $($cert.Domain) - Expires in $($cert.DaysUntilExpiry) days" -ForegroundColor Yellow
                }
                $healthWarnings += "$soonCount certificate(s) need renewal within $($config.RenewalThresholdDays) days"
            }
            
            if (-not $expiringSoon) {
                Write-Host "   All certificates valid" -ForegroundColor Green
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
            Write-Host "   No certificates configured" -ForegroundColor Gray
        }
    } catch {
        $healthWarnings += "Certificate status check failed: $($_.Exception.Message)"
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking file system..." -PercentComplete 60
    
    # Check file system permissions and paths
    Write-Host "`n6. File System:" -ForegroundColor Cyan
    try {
        $appDataPath = "$env:LOCALAPPDATA\Posh-ACME"
        if (Test-Path $appDataPath) {
            Write-Host "   Data Directory: $appDataPath" -ForegroundColor Green
            
            # Check directory size
            $dirSize = (Get-ChildItem $appDataPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $dirSizeMB = [math]::Round($dirSize / 1MB, 2)
            Write-Host "   Directory Size: $dirSizeMB MB" -ForegroundColor Gray
            
            # Test write permissions
            $testFile = Join-Path $appDataPath "health_check_test.tmp"
            try {
                "health check test" | Out-File -FilePath $testFile
                Remove-Item $testFile -Force
                Write-Host "   Write Permissions: OK" -ForegroundColor Green
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
            Write-Host "   Certificate Store: $certCount certificates in LocalMachine\\My" -ForegroundColor Green
            
            # Test store write access
            try {
                $testStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                $testStore.Open("ReadWrite")
                $testStore.Close()
                Write-Host "   Store Write Access: OK" -ForegroundColor Green
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
    Write-Host "`n7. Automatic Renewal:" -ForegroundColor Cyan
    try {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task) {
            Write-Host "   Scheduled Task: Configured" -ForegroundColor Green
            Write-Host "   State: $($task.State)" -ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
            Write-Host "   Last Run: $($task.LastRunTime)" -ForegroundColor Gray
            Write-Host "   Next Run: $($task.NextRunTime)" -ForegroundColor Gray
            Write-Host "   Last Result: $($task.LastTaskResult)" -ForegroundColor $(if ($task.LastTaskResult -eq 0) { "Green" } else { "Red" })
            
            if ($task.State -ne "Ready") {
                $healthWarnings += "Scheduled task is not in Ready state: $($task.State)"
            }
            
            if ($task.LastTaskResult -ne 0 -and $task.LastTaskResult -ne 267009) { # 267009 = never run
                $healthWarnings += "Scheduled task last execution failed (code: $($task.LastTaskResult))"
            }
        } else {
            Write-Host "   Scheduled Task: Not configured" -ForegroundColor Yellow
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
    Write-Host "`n8. Network and DNS:" -ForegroundColor Cyan
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
            Write-Host "   Internet Connectivity: OK ($connectableHosts/$($internetHosts.Count) DNS servers reachable)" -ForegroundColor Green
        } else {
            $healthIssues += "No internet connectivity detected"
        }
        
        # Test DNS resolution
        try {
            Resolve-DnsName -Name "letsencrypt.org" -Type A -ErrorAction Stop | Out-Null
            Write-Host "   DNS Resolution: OK" -ForegroundColor Green
        } catch {
            $healthIssues += "DNS resolution failed: $($_.Exception.Message)"
        }
        
        # Check proxy settings
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1) {
            Write-Host "   Proxy: Enabled ($($proxySettings.ProxyServer))" -ForegroundColor Yellow
            $healthWarnings += "Proxy is enabled, may affect ACME operations"
        } else {
            Write-Host "   Proxy: Direct connection" -ForegroundColor Green
        }
        
    } catch {
        $healthWarnings += "Network check failed: $($_.Exception.Message)"
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking event logging..." -PercentComplete 90
    
    # Check event logging
    Write-Host "`n9. Event Logging:" -ForegroundColor Cyan
    try {
        # Test event log source registration
        $eventSources = Get-WinEvent -ListProvider "Certificate Management" -ErrorAction SilentlyContinue
        if ($eventSources) {
            Write-Host "   Event Source: Registered" -ForegroundColor Green
        } else {
            Write-Host "   Event Source: Not registered" -ForegroundColor Yellow
            $healthWarnings += "Event log source 'Certificate Management' not registered"
        }
        
        # Test event log writing
        try {
            New-EventLog -LogName Application -Source "Certificate Management" -ErrorAction SilentlyContinue
            Write-EventLog -LogName Application -Source "Certificate Management" -EventId 9999 -Message "Health check test event" -ErrorAction Stop
            Write-Host "   Event Writing: OK" -ForegroundColor Green
        } catch {
            $healthWarnings += "Cannot write to event log: $($_.Exception.Message)"
        }
        
    } catch {
        $healthWarnings += "Event logging check failed: $($_.Exception.Message)"
    }
    
    Write-ProgressHelper -Activity "System Health Check" -Status "Finalizing health check..." -PercentComplete 95
    
    # Check system resources
    Write-Host "`n10. System Resources:" -ForegroundColor Cyan
    try {
        $memory = Get-CimInstance -ClassName Win32_ComputerSystem
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        Write-Host "   Total Memory: $totalMemoryGB GB" -ForegroundColor Green
        
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $memoryUsage = [math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 1)
        Write-Host "   Memory Usage: $memoryUsage%" -ForegroundColor $(if ($memoryUsage -lt 80) { "Green" } else { "Yellow" })
        
        if ($memoryUsage -gt 90) {
            $healthWarnings += "High memory usage detected: $memoryUsage%"
        }
        
        # Check available disk space
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
        $diskUsage = [math]::Round((($totalSpaceGB - $freeSpaceGB) / $totalSpaceGB) * 100, 1)
        
        Write-Host "   Disk Space: $freeSpaceGB GB free ($diskUsage% used)" -ForegroundColor $(if ($diskUsage -lt 80) { "Green" } else { "Yellow" })
        
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
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "HEALTH CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    if ($healthIssues.Count -eq 0 -and $healthWarnings.Count -eq 0) {
        Write-Host "✓ System health: EXCELLENT" -ForegroundColor Green
        Write-Host "  All components are functioning optimally." -ForegroundColor Green
        Write-Host "  No issues or warnings detected." -ForegroundColor Green
    } elseif ($healthIssues.Count -eq 0) {
        Write-Host "⚠ System health: GOOD (with warnings)" -ForegroundColor Yellow
        Write-Host "  System is functional but some optimization is recommended." -ForegroundColor Yellow
        Write-Host "`n  Warnings detected:" -ForegroundColor Yellow
        $healthWarnings | ForEach-Object { Write-Host "    • $_" -ForegroundColor Yellow }
    } else {
        Write-Host "✗ System health: NEEDS ATTENTION" -ForegroundColor Red
        Write-Host "  Critical issues require immediate attention." -ForegroundColor Red
        Write-Host "`n  Critical issues:" -ForegroundColor Red
        $healthIssues | ForEach-Object { Write-Host "    • $_" -ForegroundColor Red }
        
        if ($healthWarnings.Count -gt 0) {
            Write-Host "`n  Additional warnings:" -ForegroundColor Yellow
            $healthWarnings | ForEach-Object { Write-Host "    • $_" -ForegroundColor Yellow }
        }
    }
    
    # Health score calculation
    $issueScore = $healthIssues.Count * 3
    $warningScore = $healthWarnings.Count * 1
    $healthScore = [math]::Max(0, 100 - $issueScore - $warningScore)
    
    Write-Host "`nHealth Score: $healthScore/100" -ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
    Write-Host "Issues: $($healthIssues.Count) critical, $($healthWarnings.Count) warnings" -ForegroundColor White
    Write-Host "Check completed: $(Get-Date)" -ForegroundColor Gray
    Write-Host "Check duration: $((Get-Date) - $script:StartTime)" -ForegroundColor Gray
    
    # Recommendations based on health status
    if ($healthIssues.Count -gt 0 -or $healthWarnings.Count -gt 0) {
        Write-Host "`nRecommended Actions:" -ForegroundColor Cyan
        
        if ($healthIssues.Count -gt 0) {
            Write-Host "• Address critical issues immediately before proceeding" -ForegroundColor Red
            Write-Host "• Run configuration test: .\Main.ps1 -ConfigTest" -ForegroundColor Red
        }
        
        if ($healthWarnings.Count -gt 0) {
            Write-Host "• Review warnings and optimize system configuration" -ForegroundColor Yellow
            Write-Host "• Consider setting up monitoring for detected issues" -ForegroundColor Yellow
        }
        
        Write-Host "• Check log files for additional details" -ForegroundColor White
        Write-Host "• Verify network connectivity and DNS resolution" -ForegroundColor White
        Write-Host "• Ensure sufficient system resources are available" -ForegroundColor White
    }
    
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    
    # Log health check results
    Write-Log "System health check completed - Score: $healthScore/100, Issues: $($healthIssues.Count), Warnings: $($healthWarnings.Count)" -Level 'Info'
    
    Read-Host "Press Enter to return to the main menu"
}

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Test-SystemHealth
