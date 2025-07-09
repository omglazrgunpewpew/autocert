# AutoCert Build Tools

This directory contains build and CI/CD related tools for the AutoCert project.

## Files

### Build Validation

- **Build-Validation.ps1** - Build validation script that runs PSScriptAnalyzer, Pester tests, and other quality  
  checks to validate the codebase

## Usage

### Running Build Validation

```powershell
# Run full validation (PSScriptAnalyzer and Pester tests)
.\Build-Validation.ps1

# Run with auto-fix for formatting issues
.\Build-Validation.ps1 -Fix

# Skip tests for faster linting-only runs
.\Build-Validation.ps1 -SkipTests

# Show detailed output for all checks
.\Build-Validation.ps1 -Detailed
```

## Notes

- This script is designed to be run from the `build` directory
- Path references have been updated to work with the new directory structure
- Uses PSScriptAnalyzer settings from the `tools` directory
- Validates the entire AutoCert codebase for quality and compliance
- Typically used in CI/CD pipelines and pre-commit hooks
