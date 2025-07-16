#!/usr/bin/env pwsh
<#
    .SYNOPSIS
        Build validation script for AutoCert PowerShell project

    .DESCRIPTION
        Runs PSScriptAnalyzer, Pester tests, and other quality checks to validate the codebase

    .PARAMETER Fix
        Attempt to automatically fix formatting issues where possible

    .PARAMETER SkipTests
        Skip running Pester tests (for faster linting-only runs)

    .PARAMETER Detailed
        Show detailed output for all checks
#>

[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$SkipTests,
    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'

# Colors for output
$Colors = @{
    Success = 'Green'
    Warning = 'Yellow'
    Error   = 'Red'
    Info    = 'Cyan'
    Header  = 'Magenta'
}

function Write-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet('Success', 'Warning', 'Error', 'Info', 'Header')]
        [string]$Type = 'Info'
    )

    $color = $Colors[$Type]
    Write-Host -Object $Message -ForegroundColor $color
}

function Test-ModuleAvailability {
    param([string]$ModuleName)

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-StatusMessage "Installing required module: $ModuleName" -Type Warning
        try {
            Install-Module $ModuleName -Force -Scope CurrentUser -AllowClobber
            return $true
        }
        catch {
            Write-StatusMessage "Failed to install $ModuleName`: $($_.Exception.Message)" -Type Error
            return $false
        }
    }
    return $true
}

# Main validation function
function Invoke-BuildValidation {
    Write-StatusMessage "🔍 AutoCert Build Validation Starting..." -Type Header
    Write-StatusMessage "Time: $(Get-Date)" -Type Info

    $validationResults = @{
        PSScriptAnalyzer = @{ Passed = $false; Issues = 0; Details = @() }
        Tests            = @{ Passed = $false; TestCount = 0; FailedCount = 0 }
        OverallSuccess   = $false
    }

    # Check required modules
    Write-StatusMessage "`n📦 Checking required modules..." -Type Header
    $requiredModules = @('PSScriptAnalyzer', 'Pester')

    foreach ($module in $requiredModules) {
        if (-not (Test-ModuleAvailability $module)) {
            Write-StatusMessage "❌ Build validation cannot continue without $module" -Type Error
            return $false
        }
        Write-StatusMessage "✅ $module is available" -Type Success
    }

    # PSScriptAnalyzer validation
    Write-StatusMessage "`n🔍 Running PSScriptAnalyzer..." -Type Header

    try {
        $settingsPath = Join-Path $PSScriptRoot '..\tools\PSScriptAnalyzerSettings.psd1'
        $analyzerParams = @{
            Path     = Join-Path $PSScriptRoot '..'
            Recurse  = $true
            Settings = $settingsPath
        }

        if ($Fix) {
            $analyzerParams.Fix = $true
            Write-StatusMessage "Auto-fix mode enabled" -Type Warning
        }

        $issues = Invoke-ScriptAnalyzer @analyzerParams
        $validationResults.PSScriptAnalyzer.Issues = $issues.Count
        $validationResults.PSScriptAnalyzer.Details = $issues

        if ($issues.Count -eq 0) {
            Write-StatusMessage "✅ No PSScriptAnalyzer issues found!" -Type Success
            $validationResults.PSScriptAnalyzer.Passed = $true
        }
        else {
            Write-StatusMessage "⚠️  Found $($issues.Count) PSScriptAnalyzer issues" -Type Warning

            # Group issues by severity
            $critical = $issues | Where-Object Severity -eq 'Error'
            $warnings = $issues | Where-Object Severity -eq 'Warning'
            $info = $issues | Where-Object Severity -eq 'Information'

            if ($critical.Count -gt 0) {
                Write-StatusMessage "❌ Critical errors: $($critical.Count)" -Type Error
                if ($Detailed) {
                    $critical | ForEach-Object {
                        Write-StatusMessage "  - $($_.RuleName) in $($_.ScriptName):$($_.Line)" -Type Error
                    }
                }
            }

            if ($warnings.Count -gt 0) {
                Write-StatusMessage "⚠️  Warnings: $($warnings.Count)" -Type Warning
            }

            if ($info.Count -gt 0) {
                Write-StatusMessage "ℹ️  Info: $($info.Count)" -Type Info
            }

            # Fail build only on critical errors
            $validationResults.PSScriptAnalyzer.Passed = ($critical.Count -eq 0)
        }

    }
    catch {
        Write-StatusMessage "❌ PSScriptAnalyzer failed: $($_.Exception.Message)" -Type Error
        $validationResults.PSScriptAnalyzer.Passed = $false
    }

    # Pester tests
    if (-not $SkipTests) {
        Write-StatusMessage "`n🧪 Running Pester tests..." -Type Header

        try {
            # Look for tests in the parent directory (project root)
            $testPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tests'
            if (Test-Path $testPath) {
                # Check Pester version and use appropriate configuration
                $pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

                if ($pesterModule.Version -ge [version]'5.0.0') {
                    # Pester v5+ configuration
                    $pesterConfig = New-PesterConfiguration
                    $pesterConfig.Run.Path = $testPath
                    $pesterConfig.Output.Verbosity = if ($Detailed) { 'Detailed' } else { 'Normal' }
                    $pesterConfig.CodeCoverage.Enabled = $true
                    $pesterConfig.CodeCoverage.Path = @(
                        Join-Path $PSScriptRoot 'Core\*.ps1'
                        Join-Path $PSScriptRoot 'Functions\*.ps1'
                    )

                    $testResults = Invoke-Pester -Configuration $pesterConfig
                }
                else {
                    # Pester v4 configuration
                    $invokeParams = @{
                        Path         = $testPath
                        PassThru     = $true
                        CodeCoverage = @(
                            Join-Path $PSScriptRoot 'Core\*.ps1'
                            Join-Path $PSScriptRoot 'Functions\*.ps1'
                        )
                    }

                    if ($Detailed) {
                        $invokeParams.Verbose = $true
                    }

                    $testResults = Invoke-Pester @invokeParams
                }

                $validationResults.Tests.TestCount = $testResults.TotalCount
                $validationResults.Tests.FailedCount = $testResults.FailedCount
                $validationResults.Tests.Passed = ($testResults.FailedCount -eq 0)

                if ($testResults.FailedCount -eq 0) {
                    Write-StatusMessage "✅ All $($testResults.TotalCount) tests passed!" -Type Success

                    if ($testResults.CodeCoverage) {
                        if ($pesterModule.Version -ge [version]'5.0.0') {
                            $coverage = [math]::Round($testResults.CodeCoverage.CoveragePercent, 2)
                        }
                        else {
                            $totalLines = ($testResults.CodeCoverage.NumberOfCommandsAnalyzed)
                            $missedLines = ($testResults.CodeCoverage.NumberOfCommandsMissed)
                            $coverage = if ($totalLines -gt 0) { [math]::Round((($totalLines - $missedLines) / $totalLines) * 100, 2) } else { 0 }
                        }
                        Write-StatusMessage "📊 Code coverage: $coverage%" -Type Info
                    }
                }
                else {
                    Write-StatusMessage "❌ $($testResults.FailedCount) of $($testResults.TotalCount) tests failed" -Type Error
                }
            }
            else {
                Write-StatusMessage "⚠️  No test directory found at $testPath" -Type Warning
                $validationResults.Tests.Passed = $true  # Don't fail build if no tests exist yet
            }
        }
        catch {
            Write-StatusMessage "❌ Pester tests failed: $($_.Exception.Message)" -Type Error
            $validationResults.Tests.Passed = $false
        }
    }
    else {
        Write-StatusMessage "`n⏭️  Skipping tests as requested" -Type Info
        $validationResults.Tests.Passed = $true
    }

    # Overall validation result
    $validationResults.OverallSuccess = $validationResults.PSScriptAnalyzer.Passed -and $validationResults.Tests.Passed

    Write-StatusMessage "`n📋 Validation Summary:" -Type Header
    Write-StatusMessage "PSScriptAnalyzer: $(if ($validationResults.PSScriptAnalyzer.Passed) { '✅ PASS' } else { '❌ FAIL' }) ($($validationResults.PSScriptAnalyzer.Issues) issues)" -Type $(if ($validationResults.PSScriptAnalyzer.Passed) { 'Success' } else { 'Error' })

    if (-not $SkipTests) {
        Write-StatusMessage "Tests: $(if ($validationResults.Tests.Passed) { '✅ PASS' } else { '❌ FAIL' }) ($($validationResults.Tests.FailedCount)/$($validationResults.Tests.TestCount) failed)" -Type $(if ($validationResults.Tests.Passed) { 'Success' } else { 'Error' })
    }

    if ($validationResults.OverallSuccess) {
        Write-StatusMessage "`n🎉 Build validation PASSED!" -Type Success
        exit 0
    }
    else {
        Write-StatusMessage "`n💥 Build validation FAILED!" -Type Error
        exit 1
    }
}

# Run validation
Invoke-BuildValidation


