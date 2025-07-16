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
    Write-Warning -Message "Installing PSScriptAnalyzer module..."
    Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
}

Import-Module PSScriptAnalyzer

# Run analysis with custom rules
Write-Host -Object "Running PSScriptAnalyzer with custom AutoCert style guide rules..." -ForegroundColor Cyan
Write-Host -Object "=" * 70 -ForegroundColor Cyan

try {
    $results = Invoke-ScriptAnalyzer -Path $TestFilePath -Settings "$PSScriptRoot\PSScriptAnalyzerSettings.psd1"

    if ($results) {
        Write-Warning -Message "Found $($results.Count) style guide violations:"
        Write-Information -MessageData "" -InformationAction Continue

        # Group results by rule name
        $groupedResults = $results | Group-Object RuleName

        foreach ($group in $groupedResults) {
            Write-Host -Object "Rule: $($group.Name)" -ForegroundColor Magenta
            Write-Host -Object "-" * 40 -ForegroundColor Gray

            foreach ($result in $group.Group) {
                Write-Error -Message "  Line $($result.Line): $($result.Message)"
                Write-Warning -Message "  Severity: $($result.Severity)"
                Write-Information -MessageData "" -InformationAction Continue
            }
        }

        # Check if our custom rules are working
        $customRules = @('AvoidMarketingLanguage', 'AvoidSuccessfullyAdverb', 'AvoidVerboseFunctionNames', 'CommentQuality', 'VariableNamingConvention')
        $detectedCustomRules = $results | Where-Object { $_.RuleName -in $customRules } | Select-Object -ExpandProperty RuleName -Unique

        if ($detectedCustomRules) {
            Write-Information -MessageData "✓ Custom rules are working! Detected rules:" -InformationAction Continue
            foreach ($rule in $detectedCustomRules) {
                Write-Host -Object "  - $rule" -ForegroundColor Green
            }
        } else {
            Write-Warning -Message "⚠ No custom rules detected. Check rule implementation."
        }

    } else {
        Write-Information -MessageData "No violations found." -InformationAction Continue
    }

} catch {
    Write-Error -Message "Error running PSScriptAnalyzer: $($_.Exception.Message)"
    Write-Warning -Message "Make sure PSScriptAnalyzer is installed and the settings file is correct."
}

Write-Information -MessageData "" -InformationAction Continue
Write-Host -Object "=" * 70 -ForegroundColor Cyan
Write-Host -Object "Style guide rule validation complete." -ForegroundColor Cyan




