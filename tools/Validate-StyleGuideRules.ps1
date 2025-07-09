# Validate-StyleGuideRules.ps1
# Script to test and validate the custom PSScriptAnalyzer rules

<#
.SYNOPSIS
    Validates that the custom AutoCert style guide rules are working correctly.

.DESCRIPTION
    This script runs PSScriptAnalyzer against the test file to verify that
    the custom rules are detecting style guide violations.
#>

param(
    [string]$TestFilePath = ".\Test-StyleGuideRules.ps1"
)

# Import required modules
if (-not (Get-Module -Name PSScriptAnalyzer -ListAvailable)) {
    Write-Host "Installing PSScriptAnalyzer module..." -ForegroundColor Yellow
    Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
}

Import-Module PSScriptAnalyzer

# Run analysis with custom rules
Write-Host "Running PSScriptAnalyzer with custom AutoCert style guide rules..." -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan

try {
    $results = Invoke-ScriptAnalyzer -Path $TestFilePath -Settings "$PSScriptRoot\PSScriptAnalyzerSettings.psd1"
    
    if ($results) {
        Write-Host "Found $($results.Count) style guide violations:" -ForegroundColor Yellow
        Write-Host ""
        
        # Group results by rule name
        $groupedResults = $results | Group-Object RuleName
        
        foreach ($group in $groupedResults) {
            Write-Host "Rule: $($group.Name)" -ForegroundColor Magenta
            Write-Host "-" * 40 -ForegroundColor Gray
            
            foreach ($result in $group.Group) {
                Write-Host "  Line $($result.Line): $($result.Message)" -ForegroundColor Red
                Write-Host "  Severity: $($result.Severity)" -ForegroundColor Yellow
                Write-Host ""
            }
        }
        
        # Check if our custom rules are working
        $customRules = @('AvoidMarketingLanguage', 'AvoidSuccessfullyAdverb', 'AvoidVerboseFunctionNames', 'CommentQuality', 'VariableNamingConvention')
        $detectedCustomRules = $results | Where-Object { $_.RuleName -in $customRules } | Select-Object -ExpandProperty RuleName -Unique
        
        if ($detectedCustomRules) {
            Write-Host "✓ Custom rules are working! Detected rules:" -ForegroundColor Green
            foreach ($rule in $detectedCustomRules) {
                Write-Host "  - $rule" -ForegroundColor Green
            }
        } else {
            Write-Host "⚠ No custom rules detected. Check rule implementation." -ForegroundColor Yellow
        }
        
    } else {
        Write-Host "No violations found." -ForegroundColor Green
    }
    
} catch {
    Write-Host "Error running PSScriptAnalyzer: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure PSScriptAnalyzer is installed and the settings file is correct." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "Style guide rule validation complete." -ForegroundColor Cyan
