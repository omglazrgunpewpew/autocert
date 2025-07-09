# AutoCert Development Tools

This directory contains development and testing tools for the AutoCert project.

## Files

### Testing and Validation

- **Test-AutoCert.ps1** - Test runner for AutoCert robustness and resilience features
- **Test-Refactoring.ps1** - Validates that all refactored modules are working correctly
- **Test-StyleGuideRules.ps1** - Test script to verify custom PSScriptAnalyzer rules are working
- **Validate-StyleGuideRules.ps1** - Validates that the custom AutoCert style guide rules are working correctly

### Code Analysis

- **PSScriptAnalyzerSettings.psd1** - PowerShell Script Analyzer configuration for the AutoCert project
- **CustomRules/** - Directory containing custom PSScriptAnalyzer rules for style guide compliance
  - **AutoCertStyleRules.psm1** - Custom rules to enforce AutoCert style guide standards

### Refactoring

- **Apply-Refactoring.ps1** - Applies refactoring changes to the Main.ps1 file
- **Main.ps1.new** - Refactored version of Main.ps1 (if present)

## Usage

### Running Tests

```powershell
# Run all AutoCert tests
.\Test-AutoCert.ps1

# Test specific category
.\Test-AutoCert.ps1 -TestCategory "Configuration Management"

# Test refactored modules
.\Test-Refactoring.ps1
```

### Style Guide Validation

```powershell
# Validate style guide rules
.\Validate-StyleGuideRules.ps1

# Test against specific file
.\Validate-StyleGuideRules.ps1 -TestFilePath ".\Test-StyleGuideRules.ps1"
```

### Code Analysis

```powershell
# Run PSScriptAnalyzer with custom rules
Invoke-ScriptAnalyzer -Path ..\Main.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
```

### Refactoring

```powershell
# Apply refactoring changes
.\Apply-Refactoring.ps1 -Apply

# Revert refactoring changes
.\Apply-Refactoring.ps1 -Revert
```

## Notes

- All tools are designed to be run from the `tools` directory
- Path references have been updated to work with the new directory structure
- Custom style guide rules are enforced through PSScriptAnalyzer
- Test files validate both functionality and code quality
