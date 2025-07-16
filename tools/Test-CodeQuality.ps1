#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Local code quality test script for AutoCert
.DESCRIPTION
    Runs the same PSScriptAnalyzer and Pester tests that the CI/CD pipeline uses
    Use this to validate your code before pushing to GitHub
.PARAMETER Fix
    Attempt to automatically fix formatting issues where possible
.PARAMETER SkipTests
    Skip running Pester tests (for faster linting-only runs)
.EXAMPLE
    .\Test-CodeQuality.ps1
    Run all code quality checks
.EXAMPLE
    .\Test-CodeQuality.ps1 -SkipTests
    Run only PSScriptAnalyzer checks, skip Pester tests
#>

[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$SkipTests
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
    Write-Host $Message -ForegroundColor $color
}

# Change to project root
Set-Location $PSScriptRoot\..

Write-StatusMessage "AutoCert Code Quality Check" -Type Header
Write-StatusMessage "==============================" -Type Header

# Check required modules
Write-StatusMessage "Checking required modules..." -Type Info

try {
    if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
        Write-StatusMessage "Installing PSScriptAnalyzer..." -Type Info
        Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
    }
    
    if (-not $SkipTests -and -not (Get-Module Pester -ListAvailable)) {
        Write-StatusMessage "Installing Pester..." -Type Info
        Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0
    }
}
catch {
    Write-StatusMessage "Failed to install required modules: $($_.Exception.Message)" -Type Error
    exit 1
}

# Run PSScriptAnalyzer
Write-StatusMessage "`nRunning PSScriptAnalyzer..." -Type Info

$allIssues = @()
$pathsToCheck = @()

# Add paths that exist
@('./Core', './Functions', './UI', './Utilities', './Main.ps1', './build/Build-Validation.ps1') | ForEach-Object {
    if (Test-Path $_) {
        $pathsToCheck += $_
    }
    else {
        Write-StatusMessage "⚠️ Skipping non-existent path: $_" -Type Warning
    }
}

foreach ($path in $pathsToCheck) {
    try {
        Write-StatusMessage "🔍 Analyzing: $path" -Type Info
        $issues = Invoke-ScriptAnalyzer -Path $path -Settings ./tools/PSScriptAnalyzerSettings.psd1 -ErrorAction SilentlyContinue
        if ($issues) {
            $allIssues += $issues
        }
    }
    catch {
        Write-StatusMessage "⚠️ Failed to analyze $path : $($_.Exception.Message)" -Type Warning
    }
}

if ($allIssues) {
    Write-StatusMessage "PSScriptAnalyzer found $($allIssues.Count) issues:" -Type Warning
    $allIssues | Format-Table RuleName, Severity, ScriptName, Line, Message -AutoSize
    
    $errors = $allIssues | Where-Object Severity -eq 'Error'
    $criticalWarnings = $allIssues | Where-Object { $_.Severity -eq 'Warning' -and $_.RuleName -in @('PSAvoidUsingPlainTextForPassword', 'PSAvoidUsingConvertToSecureStringWithPlainText') }
    
    if ($errors -or $criticalWarnings) {
        $criticalCount = ($errors + $criticalWarnings).Count
        Write-StatusMessage "❌ Found $criticalCount critical issues" -Type Error
        $exitCode = 1
    }
    else {
        Write-StatusMessage "⚠️ Found warnings but no critical errors" -Type Warning
        $exitCode = 0
    }
}
else {
    Write-StatusMessage "✅ No PSScriptAnalyzer issues found!" -Type Success
    $exitCode = 0
}

# Run security scan
Write-StatusMessage "`nRunning security scan..." -Type Info

$allSecurityIssues = @()
foreach ($path in $pathsToCheck) {
    try {
        Write-StatusMessage "🔒 Security scanning: $path" -Type Info
        $securityIssues = Invoke-ScriptAnalyzer -Path $path -IncludeRule PSAvoidUsingPlainTextForPassword, PSAvoidUsingConvertToSecureStringWithPlainText, PSUseShouldProcessForStateChangingFunctions -ErrorAction SilentlyContinue
        if ($securityIssues) {
            $allSecurityIssues += $securityIssues
        }
    }
    catch {
        Write-StatusMessage "⚠️ Failed to security scan $path : $($_.Exception.Message)" -Type Warning
    }
}

if ($allSecurityIssues) {
    $criticalSecurity = $allSecurityIssues | Where-Object { $_.RuleName -in @('PSAvoidUsingPlainTextForPassword', 'PSAvoidUsingConvertToSecureStringWithPlainText') }
    if ($criticalSecurity) {
        Write-StatusMessage "🔒 Critical security issues found:" -Type Error
        $criticalSecurity | Format-Table RuleName, ScriptName, Line, Message -AutoSize
        $exitCode = 1
    }
    else {
        Write-StatusMessage "🔒 Security recommendations found:" -Type Warning
        $allSecurityIssues | Format-Table RuleName, ScriptName, Line, Message -AutoSize
    }
}
else {
    Write-StatusMessage "✅ No security issues found!" -Type Success
}

# Run tests if not skipped
if (-not $SkipTests) {
    Write-StatusMessage "`nRunning Pester tests..." -Type Info
    
    if (-not (Test-Path './Tests')) {
        Write-StatusMessage "⚠️ Tests directory not found, skipping tests..." -Type Warning
    }
    else {
        try {
            $config = New-PesterConfiguration
            $config.Run.Path = './Tests'
            $config.Output.Verbosity = 'Normal'
            $config.CodeCoverage.Enabled = $false
            
            $results = Invoke-Pester -Configuration $config
            
            if ($results.FailedCount -gt 0) {
                Write-StatusMessage "❌ $($results.FailedCount) tests failed" -Type Error
                $exitCode = 1
            }
            else {
                Write-StatusMessage "✅ All $($results.TotalCount) tests passed!" -Type Success
            }
        }
        catch {
            Write-StatusMessage "❌ Test execution failed: $($_.Exception.Message)" -Type Error
            $exitCode = 1
        }
    }
}

# Summary
Write-StatusMessage "`nCode Quality Check Complete" -Type Header
if ($exitCode -eq 0) {
    Write-StatusMessage "🎉 All checks passed! Your code is ready for commit." -Type Success
}
else {
    Write-StatusMessage "❌ Some checks failed. Please fix the issues before committing." -Type Error
}

exit $exitCode
