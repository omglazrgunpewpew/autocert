# SystemInitialization.ps1
# Module initialization and system setup functions

function Initialize-ScriptModule
{
    <#
    .SYNOPSIS
        Loads all required script modules in the correct order

    .DESCRIPTION
        Initializes the AutoCert system by loading all required modules,
        verifying critical functions, and setting up the environment.

    .PARAMETER NonInteractive
        Suppresses progress indicators when running in non-interactive mode

    .OUTPUTS
        Boolean indicating successful initialization
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$NonInteractive
    )

    try
    {
        if (-not $NonInteractive)
        {
            Write-Information -MessageData "Loading certificate management system..." -InformationAction Continue
            # Write-ProgressHelper may not be loaded yet, so use conditional call
            if (Get-Command Write-ProgressHelper -ErrorAction SilentlyContinue)
            {
                Write-ProgressHelper -Activity "System Initialization" -Status "Loading core modules..." -PercentComplete 10
            }
        }

        # Define module loading order with dependencies
        $moduleLoadOrder = @(
            # Critical Core Infrastructure
            @{ Path = "$PSScriptRoot\..\Core\Logging.ps1"; Name = "Logging"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\Helpers.ps1"; Name = "Helpers"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\ErrorHandlingHelpers.ps1"; Name = "ErrorHandlingHelpers"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\ConfigurationManager.ps1"; Name = "Configuration"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\RenewalConfig.ps1"; Name = "RenewalConfig"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\Initialize-PoshAcme.ps1"; Name = "PoshAcmeInit"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\SystemDiagnostics.ps1"; Name = "SystemDiagnostics"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Core\DNSProvider\DNSProviderDetection.ps1"; Name = "DNSProvider"; Critical = $false },

            # Public Functions
            @{ Path = "$PSScriptRoot\..\Public\BackupManager.ps1"; Name = "BackupManager"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Public\NotificationManager.ps1"; Name = "Notifications"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Public\Get-ExistingCertificates.ps1"; Name = "GetCertificates"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Register-Certificate.ps1"; Name = "RegisterCertificate"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Install-Certificate.ps1"; Name = "InstallCertificate"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Update-AllCertificates.ps1"; Name = "UpdateCertificates"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Remove-Certificate.ps1"; Name = "RemoveCertificate"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Revoke-Certificate.ps1"; Name = "RevokeCertificate"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Set-AutomaticRenewal.ps1"; Name = "AutoRenewal"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Show-Options.ps1"; Name = "ShowOptions"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Show-Menu.ps1"; Name = "MainMenu"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Show-Help.ps1"; Name = "HelpSystem"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Public\Initialize-HealthChecks.ps1"; Name = "HealthChecksInit"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Public\Initialize-CircuitBreakers.ps1"; Name = "CircuitBreakersInit"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Public\Initialize-AutoCertSystem.ps1"; Name = "SystemInit"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Private\Invoke-MenuOperation.ps1"; Name = "MenuOperation"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Private\CertificateMenu.ps1"; Name = "CertificateMenu"; Critical = $true },
            @{ Path = "$PSScriptRoot\..\Private\CredentialMenu.ps1"; Name = "CredentialMenu"; Critical = $true },

            # Private Functions
            @{ Path = "$PSScriptRoot\..\Private\CertificateCache.ps1"; Name = "CertificateCache"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Private\EnhancedErrorRecovery.ps1"; Name = "ErrorRecovery"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Private\CircuitBreaker.ps1"; Name = "CircuitBreaker"; Critical = $false },
            @{ Path = "$PSScriptRoot\..\Private\HealthMonitor.ps1"; Name = "HealthMonitor"; Critical = $false }
        )

        $totalModules = $moduleLoadOrder.Count
        $loadedCount = 0

        foreach ($module in $moduleLoadOrder)
        {
            try
            {
                if (Test-Path $module.Path)
                {
                    . $module.Path
                    $script:LoadedModules += $module.Name
                    $loadedCount++

                    if (-not $NonInteractive)
                    {
                        $progress = [math]::Round(($loadedCount / $totalModules) * 80) + 10
                        if (Get-Command Write-ProgressHelper -ErrorAction SilentlyContinue)
                        {
                            Write-ProgressHelper -Activity "System Initialization" -Status "Loaded $($module.Name)..." -PercentComplete $progress
                        }
                    }
                } else
                {
                    $errorMsg = "Module file not found: $($module.Path)"
                    if ($module.Critical)
                    {
                        throw $errorMsg
                    } else
                    {
                        $script:InitializationErrors += $errorMsg
                        Write-Warning -Message $errorMsg
                    }
                }
            } catch
            {
                $errorMsg = "Failed to load $($module.Name): $($_.Exception.Message)"
                if ($module.Critical)
                {
                    throw $errorMsg
                } else
                {
                    $script:InitializationErrors += $errorMsg
                    Write-Warning -Message $errorMsg
                }
            }
        }

        # Load all Private functions
        try
        {
            $privatePath = "$PSScriptRoot\..\Private"
            if (Test-Path $privatePath)
            {
                $successCount = 0
                $errorCount = 0
                Get-ChildItem "$privatePath\*.ps1" | ForEach-Object {
                    try
                    {
                        # Test if file can be parsed before loading
                        $content = Get-Content $_.FullName -Raw
                        $null = [System.Management.Automation.Language.Parser]::ParseInput($content, [ref]$null, [ref]$null)

                        # If parsing succeeds, load the file
                        . $_.FullName
                        $script:LoadedModules += "Private.$($_.BaseName)"
                        $loadedCount++
                        $successCount++
                    } catch
                    {
                        $errorCount++
                        Write-Warning "Skipping $($_.Name) due to parsing errors - file needs encoding fix"
                    }
                }
                Write-Log "Loaded $successCount Private functions successfully, skipped $errorCount files with errors" -Level 'Info'
            } else
            {
                Write-Warning "Private directory not found: $privatePath"
            }
        } catch
        {
            Write-Warning "Failed to load Private functions: $($_.Exception.Message)"
        }

        if (-not $NonInteractive)
        {
            if (Get-Command Write-ProgressHelper -ErrorAction SilentlyContinue)
            {
                Write-ProgressHelper -Activity "System Initialization" -Status "Verifying functions..." -PercentComplete 95
            }
        }

        # Verify critical functions are available
        $criticalFunctions = @('Register-Certificate', 'Install-Certificate', 'Write-AutoCertLog', 'Show-Menu', 'Show-CertificateManagementMenu', 'Show-CredentialManagementMenu', 'Show-Help', 'Test-SystemHealth', 'Invoke-MenuOperation')
        $missingFunctions = @()

        foreach ($func in $criticalFunctions)
        {
            if (-not (Get-Command $func -ErrorAction SilentlyContinue))
            {
                $missingFunctions += $func
            }
        }

        if ($missingFunctions.Count -gt 0)
        {
            $missingList = $missingFunctions -join ', '
            Write-Warning "Some critical functions are not available: $missingList"
            Write-Warning "This may indicate incomplete module loading. Attempting to continue..."

            # Log the issue but don't throw an exception - let the caller handle it
            $script:InitializationErrors += "Missing critical functions: $missingList"

            # Return false to indicate partial failure, but don't throw
            if (-not $NonInteractive)
            {
                if (Get-Command Write-ProgressHelper -ErrorAction SilentlyContinue)
                {
                    Write-ProgressHelper -Activity "System Initialization" -Status "Partial initialization" -PercentComplete 100
                }
                Write-Progress -Activity "System Initialization" -Completed
            }
            return $false
        }

        if (-not $NonInteractive)
        {
            if (Get-Command Write-ProgressHelper -ErrorAction SilentlyContinue)
            {
                Write-ProgressHelper -Activity "System Initialization" -Status "Initialization complete" -PercentComplete 100
            }
            Write-Progress -Activity "System Initialization" -Completed
        }

        Write-Log "Certificate management system loaded (Version: $script:ScriptVersion)" -Level 'Info'
        Write-Log "Loaded modules: $($script:LoadedModules -join ', ')" -Level 'Debug'

        if ($script:InitializationErrors.Count -gt 0)
        {
            Write-Warning -Message "Some non-critical modules failed to load. System functionality may be limited."
            Write-Log "Module loading completed with $($script:InitializationErrors.Count) non-critical errors" -Level 'Warning'
        }

        return $true

    } catch
    {
        $criticalError = "Failed to load required modules: $($_.Exception.Message)"
        Write-Error -Message $criticalError

        if (Get-Command Write-Log -ErrorAction SilentlyContinue)
        {
            Write-Log $criticalError -Level 'Error'
        }

        Write-Error -Message "Please ensure all script files are present and accessible."
        Write-Error -Message "Missing modules will prevent the system from functioning correctly."

        if (-not $NonInteractive)
        {
            Read-Host "Press Enter to exit"
        }

        return $false
    }
}


