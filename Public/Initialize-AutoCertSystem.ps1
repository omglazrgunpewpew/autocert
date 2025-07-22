# Public/Initialize-AutoCertSystem.ps1
<#
    .SYNOPSIS
        Comprehensive initialization of the AutoCert system
    
    .DESCRIPTION
        Initializes all AutoCert subsystems including health checks, circuit breakers,
        error handling, and validates system readiness. This function provides a
        one-stop initialization for the complete AutoCert certificate management system.
    
    .PARAMETER Force
        Force re-initialization of all subsystems
    
    .PARAMETER SkipHealthChecks
        Skip health check initialization
    
    .PARAMETER SkipCircuitBreakers
        Skip circuit breaker initialization
    
    .PARAMETER Detailed
        Provide detailed initialization progress and results
    
    .EXAMPLE
        Initialize-AutoCertSystem
        Initialize all AutoCert subsystems with default settings
    
    .EXAMPLE
        Initialize-AutoCertSystem -Force -Detailed
        Force complete re-initialization with detailed output
    
    .OUTPUTS
        System.Collections.Hashtable
        Comprehensive initialization report
#>

function Initialize-AutoCertSystem {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Collections.Hashtable])]
    param(
        [switch]$Force,
        [switch]$SkipHealthChecks,
        [switch]$SkipCircuitBreakers,
        [switch]$Detailed
    )
    
    $initReport = @{
        StartTime = Get-Date
        OverallSuccess = $false
        InitializationSteps = @()
        SubsystemResults = @{}
        Errors = @()
        Recommendations = @()
    }
    
    Write-Log "Starting comprehensive AutoCert system initialization..." -Level 'Info'
    
    if ($PSCmdlet.ShouldProcess("AutoCert System", "Initialize all subsystems")) {
        try {
            # Step 1: Core Error Handling Initialization
            $step = @{ Name = "Core Error Handling"; StartTime = Get-Date; Success = $false }
            try {
                if ($Detailed) {
                    Write-Host "Initializing Core Error Handling..." -ForegroundColor Yellow
                }
                
                # Initialize error tracking if not already done
                if (-not $script:CoreModuleErrors) {
                    $script:CoreModuleErrors = @()
                }
                
                $step.Success = $true
                $step.Message = "Core error handling initialized"
                $initReport.SubsystemResults['ErrorHandling'] = @{ Success = $true; Message = "Initialized successfully" }
                
                if ($Detailed) {
                    Write-Host "✅ Core Error Handling initialized" -ForegroundColor Green
                }
            }
            catch {
                $step.Error = $_.Exception.Message
                $initReport.Errors += "Core Error Handling: $($_.Exception.Message)"
                $initReport.SubsystemResults['ErrorHandling'] = @{ Success = $false; Error = $_.Exception.Message }
                
                if ($Detailed) {
                    Write-Host "❌ Core Error Handling failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            finally {
                $step.EndTime = Get-Date
                $step.Duration = ($step.EndTime - $step.StartTime).TotalMilliseconds
                $initReport.InitializationSteps += $step
            }
            
            # Step 2: Health Checks Initialization
            if (-not $SkipHealthChecks) {
                $step = @{ Name = "Health Checks"; StartTime = Get-Date; Success = $false }
                try {
                    if ($Detailed) {
                        Write-Host "Initializing Health Check System..." -ForegroundColor Yellow
                    }
                    
                    $healthResult = Initialize-HealthChecks -Force:$Force
                    $step.Success = $healthResult.Success
                    $step.Message = $healthResult.Message
                    $initReport.SubsystemResults['HealthChecks'] = $healthResult
                    
                    if ($healthResult.Success) {
                        if ($Detailed) {
                            Write-Host "✅ Health Checks initialized ($($healthResult.CheckCount) checks)" -ForegroundColor Green
                        }
                    } else {
                        $initReport.Errors += "Health Checks: $($healthResult.Message)"
                        if ($Detailed) {
                            Write-Host "❌ Health Checks failed: $($healthResult.Message)" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    $step.Error = $_.Exception.Message
                    $initReport.Errors += "Health Checks: $($_.Exception.Message)"
                    $initReport.SubsystemResults['HealthChecks'] = @{ Success = $false; Error = $_.Exception.Message }
                    
                    if ($Detailed) {
                        Write-Host "❌ Health Checks failed: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                finally {
                    $step.EndTime = Get-Date
                    $step.Duration = ($step.EndTime - $step.StartTime).TotalMilliseconds
                    $initReport.InitializationSteps += $step
                }
            }
            
            # Step 3: Circuit Breakers Initialization
            if (-not $SkipCircuitBreakers) {
                $step = @{ Name = "Circuit Breakers"; StartTime = Get-Date; Success = $false }
                try {
                    if ($Detailed) {
                        Write-Host "Initializing Circuit Breaker System..." -ForegroundColor Yellow
                    }
                    
                    $circuitResult = Initialize-CircuitBreakers -Force:$Force
                    $step.Success = $circuitResult.Success
                    $step.Message = $circuitResult.Message
                    $initReport.SubsystemResults['CircuitBreakers'] = $circuitResult
                    
                    if ($circuitResult.Success) {
                        if ($Detailed) {
                            Write-Host "✅ Circuit Breakers initialized ($($circuitResult.CircuitBreakerCount) breakers)" -ForegroundColor Green
                        }
                    } else {
                        $initReport.Errors += "Circuit Breakers: $($circuitResult.Message)"
                        if ($Detailed) {
                            Write-Host "❌ Circuit Breakers failed: $($circuitResult.Message)" -ForegroundColor Red
                        }
                    }
                }
                catch {
                    $step.Error = $_.Exception.Message
                    $initReport.Errors += "Circuit Breakers: $($_.Exception.Message)"
                    $initReport.SubsystemResults['CircuitBreakers'] = @{ Success = $false; Error = $_.Exception.Message }
                    
                    if ($Detailed) {
                        Write-Host "❌ Circuit Breakers failed: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                finally {
                    $step.EndTime = Get-Date
                    $step.Duration = ($step.EndTime - $step.StartTime).TotalMilliseconds
                    $initReport.InitializationSteps += $step
                }
            }
            
            # Step 4: System Validation
            $step = @{ Name = "System Validation"; StartTime = Get-Date; Success = $false }
            try {
                if ($Detailed) {
                    Write-Host "Performing System Validation..." -ForegroundColor Yellow
                }
                
                $validationResults = @{}
                
                # Validate health checks if initialized
                if (-not $SkipHealthChecks -and $initReport.SubsystemResults['HealthChecks'].Success) {
                    $validationResults['HealthChecks'] = Test-HealthCheckInitialization
                }
                
                # Validate circuit breakers if initialized
                if (-not $SkipCircuitBreakers -and $initReport.SubsystemResults['CircuitBreakers'].Success) {
                    $validationResults['CircuitBreakers'] = Test-CircuitBreakerInitialization
                }
                
                # Check critical functions are available
                $criticalFunctions = @(
                    'Write-Log', 'Write-AutoCertLog', 'Initialize-HealthChecks', 
                    'Initialize-CircuitBreakers', 'Invoke-CoreModuleOperation'
                )
                $missingFunctions = @()
                foreach ($func in $criticalFunctions) {
                    if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                        $missingFunctions += $func
                    }
                }
                
                $validationResults['Functions'] = $missingFunctions.Count -eq 0
                
                if ($missingFunctions.Count -gt 0) {
                    $step.Message = "Missing critical functions: $($missingFunctions -join ', ')"
                    $initReport.Errors += $step.Message
                } else {
                    $step.Success = $true
                    $step.Message = "System validation passed"
                }
                
                $initReport.SubsystemResults['Validation'] = $validationResults
                
                if ($Detailed) {
                    if ($step.Success) {
                        Write-Host "✅ System validation passed" -ForegroundColor Green
                    } else {
                        Write-Host "❌ System validation failed: $($step.Message)" -ForegroundColor Red
                    }
                }
            }
            catch {
                $step.Error = $_.Exception.Message
                $initReport.Errors += "System Validation: $($_.Exception.Message)"
                
                if ($Detailed) {
                    Write-Host "❌ System validation failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            finally {
                $step.EndTime = Get-Date
                $step.Duration = ($step.EndTime - $step.StartTime).TotalMilliseconds
                $initReport.InitializationSteps += $step
            }
            
            # Determine overall success
            $initReport.OverallSuccess = $initReport.Errors.Count -eq 0
            
            # Generate recommendations
            if ($initReport.Errors.Count -gt 0) {
                $initReport.Recommendations += "Address initialization errors before proceeding with certificate operations"
                
                if ($initReport.SubsystemResults.ContainsKey('HealthChecks') -and -not $initReport.SubsystemResults['HealthChecks'].Success) {
                    $initReport.Recommendations += "Health check system is required for monitoring - fix health check initialization"
                }
                
                if ($initReport.SubsystemResults.ContainsKey('CircuitBreakers') -and -not $initReport.SubsystemResults['CircuitBreakers'].Success) {
                    $initReport.Recommendations += "Circuit breakers provide resilience - fix circuit breaker initialization"
                }
            } else {
                $initReport.Recommendations += "System initialization successful - AutoCert is ready for operation"
                $initReport.Recommendations += "Run Test-SystemHealth to verify system components"
            }
            
        }
        catch {
            $initReport.Errors += "Critical initialization failure: $($_.Exception.Message)"
            Write-Log "Critical AutoCert initialization failure: $($_.Exception.Message)" -Level 'Error'
        }
        finally {
            $initReport.EndTime = Get-Date
            $initReport.TotalDuration = ($initReport.EndTime - $initReport.StartTime).TotalMilliseconds
            
            # Log initialization summary
            $successCount = ($initReport.InitializationSteps | Where-Object { $_.Success }).Count
            $totalSteps = $initReport.InitializationSteps.Count
            
            $logMessage = "AutoCert initialization completed: $successCount/$totalSteps steps successful"
            if ($initReport.OverallSuccess) {
                Write-Log "$logMessage - System ready" -Level 'Info'
            } else {
                Write-Log "$logMessage - $($initReport.Errors.Count) errors encountered" -Level 'Warning'
            }
            
            if ($Detailed) {
                Write-Host "`nAutoCert System Initialization Summary:" -ForegroundColor Cyan
                Write-Host "Overall Success: $($initReport.OverallSuccess)" -ForegroundColor $(if ($initReport.OverallSuccess) { 'Green' } else { 'Red' })
                Write-Host "Steps Completed: $successCount/$totalSteps" -ForegroundColor White
                Write-Host "Total Duration: $([math]::Round($initReport.TotalDuration, 2)) ms" -ForegroundColor White
                
                if ($initReport.Errors.Count -gt 0) {
                    Write-Host "`nErrors:" -ForegroundColor Red
                    $initReport.Errors | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
                }
                
                if ($initReport.Recommendations.Count -gt 0) {
                    Write-Host "`nRecommendations:" -ForegroundColor Yellow
                    $initReport.Recommendations | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
                }
            }
        }
    }
    
    return $initReport
}

function Get-AutoCertSystemStatus {
    <#
    .SYNOPSIS
        Get comprehensive status of all AutoCert subsystems
    
    .DESCRIPTION
        Returns detailed status information about all AutoCert subsystems
        including health checks, circuit breakers, error handling, and overall readiness.
    
    .OUTPUTS
        System.Collections.Hashtable
        Comprehensive system status report
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param()
    
    $statusReport = @{
        GeneratedAt = Get-Date
        OverallStatus = 'Unknown'
        Subsystems = @{}
        Summary = @{
            TotalSubsystems = 0
            ReadySubsystems = 0
            ErrorCount = 0
        }
        Recommendations = @()
    }
    
    try {
        # Check Health Checks Status
        try {
            $healthStatus = Get-HealthCheckStatus
            $statusReport.Subsystems['HealthChecks'] = $healthStatus
            if ($healthStatus.Initialized) {
                $statusReport.Summary.ReadySubsystems++
            }
        }
        catch {
            $statusReport.Subsystems['HealthChecks'] = @{ 
                Initialized = $false
                Error = $_.Exception.Message 
            }
            $statusReport.Summary.ErrorCount++
        }
        $statusReport.Summary.TotalSubsystems++
        
        # Check Circuit Breakers Status
        try {
            $circuitStatus = Get-CircuitBreakerStatus
            $statusReport.Subsystems['CircuitBreakers'] = $circuitStatus
            if ($circuitStatus.Initialized) {
                $statusReport.Summary.ReadySubsystems++
            }
        }
        catch {
            $statusReport.Subsystems['CircuitBreakers'] = @{ 
                Initialized = $false
                Error = $_.Exception.Message 
            }
            $statusReport.Summary.ErrorCount++
        }
        $statusReport.Summary.TotalSubsystems++
        
        # Check Core Error Handling
        try {
            $errorHealthReport = Test-CoreModuleHealth
            $statusReport.Subsystems['ErrorHandling'] = @{
                Initialized = $true
                Health = $errorHealthReport.OverallHealth
                TotalErrors = $errorHealthReport.TotalErrors
                CriticalErrors = $errorHealthReport.CriticalErrors
            }
            if ($errorHealthReport.OverallHealth -in @('Good', 'Excellent')) {
                $statusReport.Summary.ReadySubsystems++
            }
        }
        catch {
            $statusReport.Subsystems['ErrorHandling'] = @{ 
                Initialized = $false
                Error = $_.Exception.Message 
            }
            $statusReport.Summary.ErrorCount++
        }
        $statusReport.Summary.TotalSubsystems++
        
        # Determine overall status
        if ($statusReport.Summary.ErrorCount -eq 0 -and 
            $statusReport.Summary.ReadySubsystems -eq $statusReport.Summary.TotalSubsystems) {
            $statusReport.OverallStatus = 'Ready'
        }
        elseif ($statusReport.Summary.ReadySubsystems -gt 0) {
            $statusReport.OverallStatus = 'Partially Ready'
        }
        else {
            $statusReport.OverallStatus = 'Not Ready'
        }
        
        # Generate recommendations
        if ($statusReport.OverallStatus -eq 'Ready') {
            $statusReport.Recommendations += "All subsystems are ready - AutoCert system is fully operational"
        }
        else {
            $statusReport.Recommendations += "Initialize missing subsystems using Initialize-AutoCertSystem"
            
            if (-not $statusReport.Subsystems['HealthChecks'].Initialized) {
                $statusReport.Recommendations += "Initialize health checks: Initialize-HealthChecks"
            }
            
            if (-not $statusReport.Subsystems['CircuitBreakers'].Initialized) {
                $statusReport.Recommendations += "Initialize circuit breakers: Initialize-CircuitBreakers"
            }
        }
        
    }
    catch {
        $statusReport.OverallStatus = 'Error'
        $statusReport.Recommendations += "System status check failed: $($_.Exception.Message)"
    }
    
    return $statusReport
}
