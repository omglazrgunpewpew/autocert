# SystemDiagnostics.ps1
# System health check and diagnostic functions

function Test-SystemHealth
{
    <#
    .SYNOPSIS
        Performs comprehensive system health check

    .DESCRIPTION
        Validates system configuration, connectivity, certificates,
        and overall health of the AutoCert system.

    .OUTPUTS
        None. Displays health check results interactively.
    #>
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Information -MessageData "`n" + "="*60 -InformationAction Continue
    Write-Information -MessageData "    SYSTEM HEALTH CHECK" -InformationAction Continue
    Write-Information -MessageData "="*60 -InformationAction Continue

    $healthIssues = @()
    $healthWarnings = @()

    Write-Warning -Message "`nRunning system health check..."
    Write-ProgressHelper -Activity "System Health Check" -Status "Checking components..." -PercentComplete 10

    # Check PowerShell version
    Write-Information -MessageData "`n1. PowerShell Environment:" -InformationAction Continue
    $psVersion = $PSVersionTable.PSVersion
    Write-Information -MessageData "   Version: $psVersion" -InformationAction Continue
    Write-Information -MessageData "   Edition: $($PSVersionTable.PSEdition)" -InformationAction Continue
    Write-Information -MessageData "   Platform: $($PSVersionTable.Platform)" -InformationAction Continue

    if ($psVersion.Major -lt 5)
    {
        $healthIssues += "PowerShell version $psVersion is not supported. Minimum version 5.1 required."
    } elseif ($psVersion.Major -eq 5 -and $psVersion.Minor -eq 0)
    {
        $healthWarnings += "PowerShell 5.0 detected. Version 5.1 or later recommended for best compatibility."
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking modules..." -PercentComplete 20

    # Check Posh-ACME module
    Write-Information -MessageData "`n2. Posh-ACME Module:" -InformationAction Continue
    try
    {
        $poshAcmeModule = Get-Module -Name Posh-ACME -ListAvailable | Select-Object -First 1
        if ($poshAcmeModule)
        {
            Write-Information -MessageData "   Installed: Version $($poshAcmeModule.Version)" -InformationAction Continue
            Write-Information -MessageData "   Path: $($poshAcmeModule.ModuleBase)" -InformationAction Continue

            # Test module import
            Import-Module Posh-ACME -Force
            Write-Information -MessageData "   Status: Loaded" -InformationAction Continue

            # Check for newer version
            try
            {
                $latestVersion = (Find-Module -Name Posh-ACME -ErrorAction SilentlyContinue).Version
                if ($latestVersion -and $latestVersion -gt $poshAcmeModule.Version)
                {
                    $healthWarnings += "Newer version of Posh-ACME available: $latestVersion (current: $($poshAcmeModule.Version))"
                }
            } catch
            {
                Write-Verbose "Could not check for newer Posh-ACME version"
            }
        } else
        {
            $healthIssues += "Posh-ACME module not found"
        }
    } catch
    {
        $healthIssues += "Failed to load Posh-ACME module: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking script modules..." -PercentComplete 30

    # Check script modules
    Write-Information -MessageData "`n3. Script Modules:" -InformationAction Continue
    Write-Information -MessageData "   Loaded Modules: $($script:LoadedModules.Count)" -InformationAction Continue
    $script:LoadedModules | ForEach-Object { Write-Information -MessageData "   - $_" -InformationAction Continue }

    if ($script:InitializationErrors.Count -gt 0)
    {
        Write-Warning -Message "   Initialization Errors: $($script:InitializationErrors.Count)"
        $script:InitializationErrors | ForEach-Object { $healthWarnings += "Module loading: $_" }
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking ACME connectivity..." -PercentComplete 40

    # Check ACME server connectivity
    Write-Information -MessageData "`n4. ACME Server Connectivity:" -InformationAction Continue
    try
    {
        $server = Get-PAServer
        if ($server)
        {
            Write-Information -MessageData "   Server: $($server.Name)" -InformationAction Continue
            Write-Information -MessageData "   URL: $($server.location)" -InformationAction Continue

            # Test connectivity with timeout
            $connectivityTest = Invoke-WithRetry -ScriptBlock {
                $response = Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                return $response
            } -MaxAttempts 3 -InitialDelaySeconds 2 -OperationName "ACME server connectivity test"

            Write-Information -MessageData "   Connectivity: OK (Status: $($connectivityTest.StatusCode))" -InformationAction Continue
            Write-Information -MessageData "   Response Time: $((Measure-Command { Invoke-WebRequest -Uri $server.location -UseBasicParsing -TimeoutSec 5 }).TotalMilliseconds.ToString('F0')) ms" -InformationAction Continue
        } else
        {
            $healthWarnings += "No ACME server configured"
        }
    } catch
    {
        $healthIssues += "ACME server connectivity failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking certificates..." -PercentComplete 50

    # Check certificate status
    Write-Information -MessageData "`n5. Certificate Status:" -InformationAction Continue
    try
    {
        $orders = Get-PAOrder
        if ($orders)
        {
            $config = Get-RenewalConfig
            $renewalStatus = Get-CertificateRenewalStatus -Config $config

            Write-Information -MessageData "   Total Certificates: $($orders.Count)" -InformationAction Continue

            $expiringSoon = $renewalStatus | Where-Object { $_.NeedsRenewal }
            $criticallyExpiring = $renewalStatus | Where-Object { $_.DaysUntilExpiry -le 7 }

            if ($criticallyExpiring)
            {
                Write-Error -Message "   Critically Expiring: $($criticallyExpiring.Count)"
                foreach ($cert in $criticallyExpiring)
                {
                    Write-Error -Message "     - $($cert.Domain) (expires in $($cert.DaysUntilExpiry) days)"
                    $healthIssues += "Certificate $($cert.Domain) expires in $($cert.DaysUntilExpiry) days"
                }
            }

            if ($expiringSoon -and $expiringSoon.Count -gt $criticallyExpiring.Count)
            {
                $soonCount = $expiringSoon.Count - $criticallyExpiring.Count
                Write-Warning -Message "   Expiring Soon: $soonCount"
                foreach ($cert in ($expiringSoon | Where-Object { $_.DaysUntilExpiry -gt 7 }))
                {
                    Write-Warning -Message "     - $($cert.Domain) (expires in $($cert.DaysUntilExpiry) days)"
                }
                $healthWarnings += "$soonCount certificate(s) need renewal within $($config.RenewalThresholdDays) days"
            }

            if (-not $expiringSoon)
            {
                Write-Information -MessageData "   All certificates valid" -InformationAction Continue
            }

            # Check certificate integrity
            $integrityIssues = 0
            foreach ($order in $orders)
            {
                try
                {
                    $cert = Get-CachedPACertificate -MainDomain $order.MainDomain
                    if (-not $cert.Certificate)
                    {
                        $integrityIssues++
                    }
                } catch
                {
                    $integrityIssues++
                }
            }

            if ($integrityIssues -gt 0)
            {
                $healthWarnings += "$integrityIssues certificate(s) have integrity issues"
            }

        } else
        {
            Write-Information -MessageData "   No certificates configured" -InformationAction Continue
        }
    } catch
    {
        $healthWarnings += "Certificate status check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking file system..." -PercentComplete 60

    # Check file system permissions and paths
    Write-Information -MessageData "`n6. File System:" -InformationAction Continue
    try
    {
        $appDataPath = "$env:LOCALAPPDATA\Posh-ACME"
        if (Test-Path $appDataPath)
        {
            Write-Information -MessageData "   Data Directory: $appDataPath" -InformationAction Continue

            # Check directory size
            $dirSize = (Get-ChildItem $appDataPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $dirSizeMB = [math]::Round($dirSize / 1MB, 2)
            Write-Information -MessageData "   Directory Size: $dirSizeMB MB" -InformationAction Continue

            # Test write permissions
            $testFile = Join-Path $appDataPath "health_check_test.tmp"
            try
            {
                "health check test" | Out-File -FilePath $testFile
                Remove-Item $testFile -Force
                Write-Information -MessageData "   Write Permissions: OK" -InformationAction Continue
            } catch
            {
                $healthIssues += "Cannot write to Posh-ACME data directory"
            }
        } else
        {
            $healthWarnings += "Posh-ACME data directory does not exist"
        }

        # Check certificate stores
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
        try
        {
            $store.Open("ReadOnly")
            $certCount = $store.Certificates.Count
            Write-Information -MessageData "   Certificate Store: $certCount certificates in LocalMachine\\My" -InformationAction Continue

            # Test store write access
            try
            {
                $testStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                $testStore.Open("ReadWrite")
                $testStore.Close()
                Write-Information -MessageData "   Store Write Access: OK" -InformationAction Continue
            } catch
            {
                $healthWarnings += "Limited access to certificate store (may affect installation)"
            }
        } catch
        {
            $healthIssues += "Cannot access certificate store"
        } finally
        {
            $store.Close()
        }

    } catch
    {
        $healthWarnings += "File system check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking scheduled tasks..." -PercentComplete 70

    # Check scheduled tasks and automation
    Write-Information -MessageData "`n7. Automatic Renewal:" -InformationAction Continue
    try
    {
        $task = Get-ScheduledTask -TaskName "Posh-ACME Certificate Renewal" -ErrorAction SilentlyContinue
        if ($task)
        {
            Write-Information -MessageData "   Scheduled Task: Configured" -InformationAction Continue
            Write-Information -MessageData "   State: $($task.State)"  -InformationAction Continue-ForegroundColor $(if ($task.State -eq "Ready") { "Green" } else { "Yellow" })
            Write-Information -MessageData "   Last Run: $($task.LastRunTime)" -InformationAction Continue
            Write-Information -MessageData "   Next Run: $($task.NextRunTime)" -InformationAction Continue
            Write-Information -MessageData "   Last Result: $($task.LastTaskResult)"  -InformationAction Continue-ForegroundColor $(if ($task.LastTaskResult -eq 0) { "Green" } else { "Red" })

            if ($task.State -ne "Ready")
            {
                $healthWarnings += "Scheduled task is not in Ready state: $($task.State)"
            }

            if ($task.LastTaskResult -ne 0 -and $task.LastTaskResult -ne 267009)
            {
                # 267009 = never run
                $healthWarnings += "Scheduled task last execution failed (code: $($task.LastTaskResult))"
            }
        } else
        {
            Write-Warning -Message "   Scheduled Task: Not configured"
            $healthWarnings += "Automatic renewal not configured"
        }

        # Check task schedule validity
        if ($task)
        {
            $config = Get-RenewalConfig
            if ($config.UseRandomization -and $config.RandomizationWindow -gt 1440)
            {
                $healthWarnings += "Renewal randomization window is too large ($($config.RandomizationWindow) minutes)"
            }
        }
    } catch
    {
        $healthWarnings += "Scheduled task check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking network and DNS..." -PercentComplete 80

    # Check network connectivity and DNS
    Write-Information -MessageData "`n8. Network and DNS:" -InformationAction Continue
    try
    {
        # Test internet connectivity
        $internetHosts = @("dns.google", "one.one.one.one", "dns.opendns.com")
        $connectableHosts = 0

        foreach ($testHost in $internetHosts)
        {
            if (Test-Connection -ComputerName $testHost -Count 1 -Quiet -TimeoutSec 3)
            {
                $connectableHosts++
            }
        }

        if ($connectableHosts -gt 0)
        {
            Write-Information -MessageData "   Internet Connectivity: OK ($connectableHosts/$($internetHosts.Count) DNS servers reachable)" -InformationAction Continue
        } else
        {
            $healthIssues += "No internet connectivity detected"
        }

        # Test DNS resolution
        try
        {
            Resolve-DnsName -Name "letsencrypt.org" -Type A -ErrorAction Stop | Out-Null
            Write-Information -MessageData "   DNS Resolution: OK" -InformationAction Continue
        } catch
        {
            $healthIssues += "DNS resolution failed: $($_.Exception.Message)"
        }

        # Check proxy settings
        $proxySettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
        if ($proxySettings.ProxyEnable -eq 1)
        {
            Write-Warning -Message "   Proxy: Enabled ($($proxySettings.ProxyServer))"
            $healthWarnings += "Proxy is enabled, may affect ACME operations"
        } else
        {
            Write-Information -MessageData "   Proxy: Direct connection" -InformationAction Continue
        }

    } catch
    {
        $healthWarnings += "Network check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking event logging..." -PercentComplete 90

    # Check event logging
    Write-Information -MessageData "`n9. Event Logging:" -InformationAction Continue
    try
    {
        # Test event log source registration
        $eventSources = Get-WinEvent -ListProvider "Certificate Management" -ErrorAction SilentlyContinue
        if ($eventSources)
        {
            Write-Information -MessageData "   Event Source: Registered" -InformationAction Continue
        } else
        {
            Write-Warning -Message "   Event Source: Not registered"
            $healthWarnings += "Event log source 'Certificate Management' not registered"
        }

        # Test event log writing
        try
        {
            New-EventLog -LogName Application -Source "Certificate Management" -ErrorAction SilentlyContinue
            Write-EventLog -LogName Application -Source "Certificate Management" -EventId 9999 -Message "Health check test event" -ErrorAction Stop
            Write-Information -MessageData "   Event Writing: OK" -InformationAction Continue
        } catch
        {
            $healthWarnings += "Cannot write to event log: $($_.Exception.Message)"
        }

    } catch
    {
        $healthWarnings += "Event logging check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Finalizing health check..." -PercentComplete 95

    # Check system resources
    Write-Information -MessageData "`n10. System Resources:" -InformationAction Continue
    try
    {
        $memory = Get-CimInstance -ClassName Win32_ComputerSystem
        $totalMemoryGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        Write-Information -MessageData "   Total Memory: $totalMemoryGB GB" -InformationAction Continue

        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $memoryUsage = [math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 1)
        Write-Information -MessageData "   Memory Usage: $memoryUsage%"  -InformationAction Continue-ForegroundColor $(if ($memoryUsage -lt 80) { "Green" } else { "Yellow" })

        if ($memoryUsage -gt 90)
        {
            $healthWarnings += "High memory usage detected: $memoryUsage%"
        }

        # Check available disk space
        $systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpaceGB = [math]::Round($systemDrive.FreeSpace / 1GB, 2)
        $totalSpaceGB = [math]::Round($systemDrive.Size / 1GB, 2)
        $diskUsage = [math]::Round((($totalSpaceGB - $freeSpaceGB) / $totalSpaceGB) * 100, 1)

        Write-Information -MessageData "   Disk Space: $freeSpaceGB GB free ($diskUsage% used)"  -InformationAction Continue-ForegroundColor $(if ($diskUsage -lt 80) { "Green" } else { "Yellow" })

        if ($freeSpaceGB -lt 1)
        {
            $healthIssues += "Low disk space: Only $freeSpaceGB GB free"
        } elseif ($freeSpaceGB -lt 5)
        {
            $healthWarnings += "Limited disk space: $freeSpaceGB GB free"
        }

    } catch
    {
        $healthWarnings += "System resource check failed: $($_.Exception.Message)"
    }

    Write-ProgressHelper -Activity "System Health Check" -Status "Health check complete" -PercentComplete 100
    Write-Progress -Activity "System Health Check" -Completed

    Write-ProgressHelper -Activity "System Health Check" -Status "Checking circuit breakers..." -PercentComplete 95

    # Check circuit breaker status
    Write-Information -MessageData "`n9. Circuit Breaker Status:" -InformationAction Continue
    try
    {
        # Ensure circuit breaker module is loaded
        if (-not (Get-Command -Name Get-CircuitBreakerStatus -ErrorAction SilentlyContinue)) {
            . "$PSScriptRoot\CircuitBreaker.ps1"
        }

        $cbStatus = Get-CircuitBreakerStatus
        if ($cbStatus -and $cbStatus.Count -gt 0)
        {
            foreach ($name in $cbStatus.Keys)
            {
                $cb = $cbStatus[$name]
                $stateColor = switch ($cb.State) {
                    'Closed' { 'Green' }
                    'HalfOpen' { 'Yellow' }
                    'Open' { 'Red' }
                    default { 'Gray' }
                }

                Write-Information -MessageData "   $name`: $($cb.State)" -InformationAction Continue
                if ($cb.State -ne 'Closed')
                {
                    Write-Information -MessageData "     Failures: $($cb.FailureCount)" -InformationAction Continue
                    if ($cb.LastFailureTime -and $cb.LastFailureTime -ne [datetime]::MinValue)
                    {
                        $timeSinceFailure = (Get-Date) - $cb.LastFailureTime
                        Write-Information -MessageData "     Last Failure: $($timeSinceFailure.ToString('hh\:mm\:ss')) ago" -InformationAction Continue
                    }
                }

                # Alert on open circuit breakers
                if ($cb.State -eq 'Open')
                {
                    $healthWarnings += "Circuit breaker '$name' is OPEN due to repeated failures"
                }
                elseif ($cb.State -eq 'HalfOpen')
                {
                    $healthWarnings += "Circuit breaker '$name' is in HALF-OPEN state (testing recovery)"
                }

                # Check failure history
                if ($cb.FailureHistory -and $cb.FailureHistory.Count -gt 0)
                {
                    $recentFailures = 0
                    foreach ($key in $cb.FailureHistory.Keys)
                    {
                        $recentFailures += $cb.FailureHistory[$key].Count
                    }
                    if ($recentFailures -gt 0)
                    {
                        Write-Verbose "     Recent failure events: $recentFailures"
                    }
                }
            }
        }
        else
        {
            Write-Information -MessageData "   Circuit breakers: Not yet initialized" -InformationAction Continue
        }
    }
    catch
    {
        Write-Verbose "Circuit breaker check failed: $($_.Exception.Message)"
    }

    # Display comprehensive summary
    Write-Information -MessageData "`n" + "="*60 -InformationAction Continue
    Write-Information -MessageData "HEALTH CHECK SUMMARY" -InformationAction Continue
    Write-Information -MessageData "="*60 -InformationAction Continue

    if ($healthIssues.Count -eq 0 -and $healthWarnings.Count -eq 0)
    {
        Write-Information -MessageData "OK System health: EXCELLENT" -InformationAction Continue
        Write-Information -MessageData "  All components are functioning properly." -InformationAction Continue
        Write-Information -MessageData "  No issues or warnings detected." -InformationAction Continue
    } elseif ($healthIssues.Count -eq 0)
    {
        Write-Warning -Message "⚠ System health: GOOD (with warnings)"
        Write-Warning -Message "  System is functional but some optimization is recommended."
        Write-Warning -Message "`n  Warnings detected:"
        $healthWarnings | ForEach-Object { Write-Warning -Message "    - $_" }
    } else
    {
        Write-Error -Message "X System health: NEEDS ATTENTION"
        Write-Error -Message "  Critical issues require immediate attention."
        Write-Error -Message "`n  Critical issues:"
        $healthIssues | ForEach-Object { Write-Error -Message "    - $_" }

        if ($healthWarnings.Count -gt 0)
        {
            Write-Warning -Message "`n  Additional warnings:"
            $healthWarnings | ForEach-Object { Write-Warning -Message "    - $_" }
        }
    }

    # Health score calculation
    $issueScore = $healthIssues.Count * 3
    $warningScore = $healthWarnings.Count * 1
    $healthScore = [math]::Max(0, 100 - $issueScore - $warningScore)

    Write-Information -MessageData "`nHealth Score: $healthScore/100"  -InformationAction Continue-ForegroundColor $(if ($healthScore -ge 80) { "Green" } elseif ($healthScore -ge 60) { "Yellow" } else { "Red" })
    Write-Information -MessageData "Issues: $($healthIssues.Count) critical, $($healthWarnings.Count) warnings" -InformationAction Continue
    Write-Information -MessageData "Check completed: $(Get-Date)" -InformationAction Continue
    Write-Information -MessageData "Check duration: $((Get-Date) - $script:StartTime)" -InformationAction Continue

    # Recommendations based on health status
    if ($healthIssues.Count -gt 0 -or $healthWarnings.Count -gt 0)
    {
        Write-Information -MessageData "`nRecommended Actions:" -InformationAction Continue

        if ($healthIssues.Count -gt 0)
        {
            Write-Error -Message "- Address critical issues immediately before proceeding"
            Write-Information -MessageData "- Run configuration test: .\Main.ps1 -ConfigTest" -InformationAction Continue
        }

        if ($healthWarnings.Count -gt 0)
        {
            Write-Warning -Message "- Review warnings and optimize system configuration"
            Write-Warning -Message "- Consider setting up monitoring for detected issues"
        }

        Write-Information -MessageData "- Check log files for additional details" -InformationAction Continue
        Write-Information -MessageData "- Verify network connectivity and DNS resolution" -InformationAction Continue
        Write-Information -MessageData "- Ensure sufficient system resources are available" -InformationAction Continue
    }

    Write-Information -MessageData "`n" + "="*60 -InformationAction Continue

    # Log health check results
    Write-Log "System health check completed - Score: $healthScore/100, Issues: $($healthIssues.Count), Warnings: $($healthWarnings.Count)" -Level 'Info'

    Read-Host "Press Enter to return to the main menu"
}

function Test-SystemConfiguration
{
    <#
    .SYNOPSIS
        Validates system configuration for AutoCert

    .DESCRIPTION
        Performs a quick validation of the system configuration to ensure
        all required components and settings are properly configured.
        This is used for the -ConfigTest parameter.

    .OUTPUTS
        Boolean indicating whether the configuration is valid
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $configurationIssues = @()

    Write-Information -MessageData "Validating system configuration..." -InformationAction Continue

    try
    {
        # Check PowerShell version
        if ($PSVersionTable.PSVersion.Major -lt 5)
        {
            $configurationIssues += "PowerShell version $($PSVersionTable.PSVersion) is not supported. Minimum version is 5.1."
        } else
        {
            Write-Information -MessageData "✓ PowerShell version $($PSVersionTable.PSVersion) is supported" -InformationAction Continue
        }

        # Check if Posh-ACME module is available
        $poshAcmeModule = Get-Module -ListAvailable -Name Posh-ACME
        if (-not $poshAcmeModule)
        {
            $configurationIssues += "Posh-ACME module is not installed or not available."
        } else
        {
            Write-Information -MessageData "✓ Posh-ACME module version $($poshAcmeModule[0].Version) is available" -InformationAction Continue
        }

        # Check log directory access
        $logDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Posh-ACME"
        try
        {
            if (-not (Test-Path $logDir))
            {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            $testFile = Join-Path -Path $logDir -ChildPath "test_write.tmp"
            "test" | Out-File -FilePath $testFile -Force
            Remove-Item -Path $testFile -Force
            Write-Information -MessageData "✓ Log directory access verified: $logDir" -InformationAction Continue
        } catch
        {
            $configurationIssues += "Cannot write to log directory: $logDir - $($_.Exception.Message)"
        }

        # Check if critical functions are available
        $criticalFunctions = @('Write-AutoCertLog')
        foreach ($func in $criticalFunctions)
        {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue))
            {
                $configurationIssues += "Critical function '$func' is not available."
            } else
            {
                Write-Information -MessageData "✓ Critical function '$func' is available" -InformationAction Continue
            }
        }

        # Check certificate store access (requires admin)
        try
        {
            $store = Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction Stop | Select-Object -First 1
            Write-Information -MessageData "✓ Certificate store access verified" -InformationAction Continue
        } catch
        {
            $configurationIssues += "Cannot access certificate store: $($_.Exception.Message)"
        }

        # Report results
        if ($configurationIssues.Count -eq 0)
        {
            Write-Information -MessageData "`n✓ All configuration checks passed successfully!" -InformationAction Continue
            return $true
        } else
        {
            Write-Information -MessageData "`nConfiguration validation failed with $($configurationIssues.Count) issues:" -InformationAction Continue
            foreach ($issue in $configurationIssues)
            {
                Write-Information -MessageData "  ✗ $issue" -InformationAction Continue
            }
            return $false
        }
    } catch
    {
        Write-Information -MessageData "`nUnexpected error during configuration validation: $($_.Exception.Message)" -InformationAction Continue
        return $false
    }
}


