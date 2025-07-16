# AutoCert Development Tools

This directory contains various tools and scripts to help maintain code quality and ensure the AutoCert project meets PowerShell best practices.

## Quick Start - Fix CI/CD Issues

If you're experiencing CI/CD pipeline failures, run these commands in order:

```powershell
# 1. Auto-fix common formatting issues
.\tools\Fix-CommonIssues.ps1

# 2. Test your code locally (same as CI/CD pipeline)
.\tools\Test-CodeQuality.ps1

# 3. If tests pass, commit your changes
git add .
git commit -m "Fix code quality issues"
git push
```

## Available Tools

### Code Quality Scripts

- **`Test-CodeQuality.ps1`** - Local test runner that mirrors the CI/CD pipeline
  - Runs PSScriptAnalyzer with the same settings as GitHub Actions
  - Runs Pester tests
  - Use `-SkipTests` to run only PSScriptAnalyzer checks
  
- **`Fix-CommonIssues.ps1`** - Auto-fixes common formatting issues
  - Removes trailing whitespace
  - Fixes multiple blank lines
  - Ensures files end with newline

### Legacy Tools (for reference)

- `Add-ShouldProcessSupport.ps1` - Adds ShouldProcess support to functions
- `Advanced-CodeQuality.ps1` - Advanced code analysis
- `Apply-Refactoring.ps1` - Apply refactoring suggestions
- `Fix-*.ps1` - Various specific fix scripts
- `Test-*.ps1` - Various test scripts
- `Validate-StyleGuideRules.ps1` - Style guide validation

### Configuration Files

- **`PSScriptAnalyzerSettings.psd1`** - PSScriptAnalyzer configuration
  - Defines coding standards for the project
  - Excludes `Write-Host` usage for UI components
  - Enforces PowerShell best practices

## Understanding CI/CD Pipeline Failures

The AutoCert CI/CD pipeline runs several checks:

1. **Code Quality & Security Checks**
   - PSScriptAnalyzer with custom rules
   - Security vulnerability scanning
   - Build validation

2. **Unit & Integration Tests**
   - Pester test execution
   - Code coverage analysis

3. **Security Vulnerability Scan**
   - DevSkim security scanner

4. **Documentation & Help Generation**
   - PlatyPS help generation

5. **Release Creation** (main branch only)
   - Package creation
   - GitHub release generation

## Common Issues and Solutions

### PSScriptAnalyzer Failures

**Problem**: PSScriptAnalyzer finds formatting or style issues
**Solution**: Run `.\tools\Fix-CommonIssues.ps1` then `.\tools\Test-CodeQuality.ps1`

### Write-Host Usage

**Problem**: PSScriptAnalyzer complains about Write-Host usage
**Solution**: Write-Host is allowed for UI components. The rule is excluded in the settings.

### Missing Dependencies

**Problem**: Pipeline fails because modules aren't available

**Solution**: Dependencies are automatically installed in the pipeline. If you see this locally, run:

```powershell
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0
```

### Test Failures

**Problem**: Pester tests fail

**Solution**:

1. Run tests locally: `.\tools\Test-CodeQuality.ps1`
2. Check the test output for specific failures
3. Fix the underlying code issues
4. Ensure all required functions are properly dot-sourced

## Best Practices

1. **Before pushing code**:
   - Run `.\tools\Test-CodeQuality.ps1`
   - Fix any issues found
   - Commit only when all tests pass

2. **PowerShell style guidelines**:
   - Use approved verbs for function names
   - Include help documentation for all functions
   - Use proper error handling with try/catch blocks
   - Avoid hardcoded paths or credentials

3. **Security considerations**:
   - Never store passwords or secrets in plain text
   - Use SecureString for sensitive data
   - Implement proper credential management

## Troubleshooting

If you continue to have CI/CD issues after running the tools:

1. Check the GitHub Actions log for specific error messages
2. Verify all paths referenced in the CI/CD pipeline exist
3. Ensure PSScriptAnalyzer settings are properly configured
4. Run the exact same commands locally that the CI/CD pipeline runs

For help, check the project's main README.md or create an issue in the repository.
