# ModuleManager.ps1
# Handles module loading and initialization for the AutoCert system

<#
.SYNOPSIS
    Manages module loading and initialization for the AutoCert certificate management system.

.DESCRIPTION
    Provides centralized module loading with dependency tracking, error handling,
    and progress reporting for all AutoCert components.
#>

function Initialize-AutoCertModule {
    [CmdletBinding()]
    param(
        [switch]$NonInteractive
    )

    try {
        # Initialize script-wide variables if not already done
        if (-not (Get-Variable -Name "LoadedModules" -Scope Script -ErrorAction SilentlyContinue)) {
            $script:LoadedModules = @()
        }
        if (-not (Get-Variable -Name "InitializationErrors" -Scope Script -ErrorAction SilentlyContinue)) {
            $script:InitializationErrors = @()
        }

        if (-not $NonInteractive) {
            Write-Information -MessageData "Loading certificate management system..." -InformationAction Continue
            Write-ProgressHelper -Activity "System Initialization" -Status "Loading core modules..." -PercentComplete 10
        }

        # Define module loading order with dependencies
        $moduleLoadOrder = @(
            # Core system modules (critical)
            @{ Path = "$PSScriptRoot\..\Core\Logging.ps1"; Name = "Logging"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\Helpers.ps1"; Name = "Helpers"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\Initialize-PoshAcme.ps1"; Name = "PoshACME Initialization"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\ConfigurationManager.ps1"; Name = "Configuration Manager"; Critical = $true },

            # Additional core modules (non-critical)
            @{ Path = "$PSScriptRoot\..\Core\CircuitBreaker.ps1"; Name = "Circuit Breaker"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Core\HealthMonitor.ps1"; Name = "Health Monitor"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Core\BackupManager.ps1"; Name = "Backup Manager"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Core\NotificationManager.ps1"; Name = "Notification Manager"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Core\CertificateCache.ps1"; Name = "Certificate Cache"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Core\DNSProviderDetection.ps1"; Name = "DNS Provider Detection"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Core\RenewalConfig.ps1"; Name = "Renewal Configuration"; Critical = $false },

            # Utility modules
            @{ Path = "$PSScriptRoot\ErrorHandling.ps1"; Name = "Error Handling"; Critical = $true },
            @{ Path = "$PSScriptRoot\HealthCheck.ps1"; Name = "Health Check"; Critical = $false },
            @{ Path = "$PSScriptRoot\Configuration.ps1"; Name = "Configuration Validation"; Critical = $true },
            @{ Path = "$PSScriptRoot\RenewalManager.ps1"; Name = "Renewal Manager"; Critical = $false },

            # UI modules
            @{ Path = "$PSScriptRoot\..\UI\MainMenu.ps1"; Name = "Main Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\UI\CertificateMenu.ps1"; Name = "Certificate Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\UI\CredentialMenu.ps1"; Name = "Credential Menu"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\UI\HelpSystem.ps1"; Name = "Help System"; Critical = $false },

            # Function modules
            @{ Path = "$PSScriptRoot\..\Functions\Register-Certificate.ps1"; Name = "Certificate Registration"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Functions\Install-Certificate.ps1"; Name = "Certificate Installation"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Functions\Revoke-Certificate.ps1"; Name = "Certificate Revocation"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Functions\Remove-Certificate.ps1"; Name = "Certificate Removal"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Functions\Get-ExistingCertificates.ps1"; Name = "Certificate Listing"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Functions\Set-AutomaticRenewal.ps1"; Name = "Automatic Renewal"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Functions\Show-Options.ps1"; Name = "Options"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Functions\Update-AllCertificates.ps1"; Name = "Certificate Updates"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Functions\Manage-Credentials.ps1"; Name = "Credential Management"; Critical = $false }
        )

        $totalModules = $moduleLoadOrder.Count
        $loadedCount = 0

        foreach ($module in $moduleLoadOrder) {
            try {
                if (Test-Path $module.Path) {
                    # Dot-source the module
                    . $module.Path
                    $script:LoadedModules += $module.Name
                    $loadedCount++

                    if (-not $NonInteractive) {
                        $percentComplete = [math]::Round(($loadedCount / $totalModules) * 80) + 10
                        Write-ProgressHelper -Activity "System Initialization" -Status "Loaded: $($module.Name)" -PercentComplete $percentComplete
                    }

                    Write-Verbose "Loaded module: $($module.Name)"
                }
                else {
                    $errorMsg = "Module file not found: $($module.Path)"
                    $script:InitializationErrors += $errorMsg

                    if ($module.Critical) {
                        throw $errorMsg
                    }
                    else {
                        Write-Warning -Message $errorMsg
                    }
                }
            }
            catch {
                $errorMsg = "Failed to load module '$($module.Name)': $($_.Exception.Message)"
                $script:InitializationErrors += $errorMsg

                if ($module.Critical) {
                    throw $errorMsg
                }
                else {
                    Write-Warning -Message $errorMsg
                }
            }
        }

        if (-not $NonInteractive) {
            Write-ProgressHelper -Activity "System Initialization" -Status "Finalizing..." -PercentComplete 95
        }

        # Verify critical functions are available
        $criticalFunctions = @(
            'Register-Certificate',
            'Install-Certificate',
            'Write-Log',
            'Show-Menu',
            'Show-CertificateManagementMenu',
            'Test-SystemConfiguration',
            'Invoke-MenuOperation'
        )

        $missingFunctions = @()
        foreach ($func in $criticalFunctions) {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
                $missingFunctions += $func
            }
        }

        if ($missingFunctions.Count -gt 0) {
            throw "Critical functions not available: $($missingFunctions -join ', ')"
        }

        if (-not $NonInteractive) {
            Write-ProgressHelper -Activity "System Initialization" -Status "Complete" -PercentComplete 100
            Write-Progress -Activity "System Initialization" -Completed
        }

        # Log successful initialization
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "AutoCert system loaded (Modules: $($script:LoadedModules.Count))" -Level 'Info'
            Write-Log "Loaded modules: $($script:LoadedModules -join ', ')" -Level 'Debug'

            if ($script:InitializationErrors.Count -gt 0) {
                Write-Log "Initialization warnings: $($script:InitializationErrors.Count)" -Level 'Warning'
            }
        }

        return @{
            Success       = $true
            LoadedModules = $script:LoadedModules
            Errors        = $script:InitializationErrors
            ModuleCount   = $script:LoadedModules.Count
        }

    }
    catch {
        $criticalError = "Failed to load required modules: $($_.Exception.Message)"
        Write-Error -Message $criticalError

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log $criticalError -Level 'Error'
        }

        Write-Error -Message "Please ensure all script files are present and accessible."
        Write-Error -Message "Missing modules will prevent the system from functioning correctly."

        if (-not $NonInteractive) {
            Write-Progress -Activity "System Initialization" -Completed
        }

        return @{
            Success       = $false
            LoadedModules = $script:LoadedModules
            Errors        = $script:InitializationErrors + @($_.Exception.Message)
            ModuleCount   = $script:LoadedModules.Count
        }
    }
}

function Get-LoadedModuleInfo {
    <#
    .SYNOPSIS
        Returns information about currently loaded AutoCert modules.
    #>
    [CmdletBinding()]
    param()

    return @{
        LoadedModules        = if (Get-Variable -Name "LoadedModules" -Scope Script -ErrorAction SilentlyContinue) { $script:LoadedModules } else { @() }
        InitializationErrors = if (Get-Variable -Name "InitializationErrors" -Scope Script -ErrorAction SilentlyContinue) { $script:InitializationErrors } else { @() }
        ModuleCount          = if (Get-Variable -Name "LoadedModules" -Scope Script -ErrorAction SilentlyContinue) { $script:LoadedModules.Count } else { 0 }
        ErrorCount           = if (Get-Variable -Name "InitializationErrors" -Scope Script -ErrorAction SilentlyContinue) { $script:InitializationErrors.Count } else { 0 }
    }
}

function Test-ModuleDependency {
    <#
    .SYNOPSIS
        Tests if all module dependencies are satisfied.
    #>
    [CmdletBinding()]
    param()

    $dependencies = @(
        @{ Function = "Write-Log"; Module = "Logging" },
        @{ Function = "Invoke-WithRetry"; Module = "Error Handling" },
        @{ Function = "Show-Menu"; Module = "Main Menu" },
        @{ Function = "Show-CertificateManagementMenu"; Module = "Certificate Menu" },
        @{ Function = "Test-SystemHealth"; Module = "Health Check" },
        @{ Function = "Register-Certificate"; Module = "Certificate Registration" },
        @{ Function = "Install-Certificate"; Module = "Certificate Installation" }
    )

    $missingDependencies = @()

    foreach ($dep in $dependencies) {
        if (-not (Get-Command $dep.Function -ErrorAction SilentlyContinue)) {
            $missingDependencies += $dep
        }
    }

    return @{
        AllDependenciesSatisfied = ($missingDependencies.Count -eq 0)
        MissingDependencies      = $missingDependencies
        TestedDependencies       = $dependencies.Count
    }
}

function Reset-ModuleState {
    <#
    .SYNOPSIS
        Resets the module loading state (useful for testing).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ($PSCmdlet.ShouldProcess("Module State", "Reset")) {
        if (Get-Variable -Name "LoadedModules" -Scope Script -ErrorAction SilentlyContinue) {
            $script:LoadedModules = @()
        }
        if (Get-Variable -Name "InitializationErrors" -Scope Script -ErrorAction SilentlyContinue) {
            $script:InitializationErrors = @()
        }

        Write-Verbose "Module state has been reset"
    }
}

# Export functions for module use
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Initialize-AutoCertModule, Get-LoadedModuleInfo, Test-ModuleDependency, Reset-ModuleState



