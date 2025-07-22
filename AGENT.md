# AutoCert Agent Guide

This guide helps AI agents understand the AutoCert PowerShell project structure, common tasks, and coding standards.

## Quick Start Commands

- **Test**: `.\dev-tools\Tests\RunTests.ps1` (run all tests via Pester)
- **Test single**: `Invoke-Pester -Path "dev-tools\Tests\Autocert.Tests.ps1"` (run specific test file)
- **Lint**: `.\build\Build-Validation.ps1` (PSScriptAnalyzer + tests)
- **Lint only**: `.\build\Build-Validation.ps1 -SkipTests` (PSScriptAnalyzer only)
- **Main script**: `.\Main.ps1` (interactive mode) or `.\Main.ps1 -RenewAll -NonInteractive` (scheduled mode)

## Architecture

- **Core/**: System modules (Logging, Helpers, ConfigurationManager, ErrorHandlingHelpers, etc.)
- **Public/**: Main certificate operations (Register-Certificate, Install-Certificate, etc.)
- **Private/**: Internal functions and menu systems (CertificateMenu, CredentialMenu, etc.)
- **dev-tools/Tests/**: Pester test suites (Unit, Integration, Resilience tests)
- **Main.ps1**: Entry point with parameter handling and module loading
- **Modules/Posh-ACME/**: ACME protocol implementation with DNS plugins
- **Scheduling/**: Windows Task Scheduler integration for automated renewals

## Key Dependencies

- **Posh-ACME**: ACME protocol client (included in Modules/)
- **PowerShell 5.1+**: Required runtime
- **Pester**: Testing framework (install via `Install-Module Pester`)
- **PSScriptAnalyzer**: Code quality tool (install via `Install-Module PSScriptAnalyzer`)

## Common Patterns

### Function Structure

```powershell
function Verb-Noun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RequiredParam,
        
        [Parameter()]
        [switch]$OptionalSwitch
    )
    
    Write-Log "Starting operation..." -Level Info
    
    try {
        # Implementation
        Write-ProgressHelper -Activity "Processing" -Status "Working"
        
        Write-Log "Operation completed successfully" -Level Success
        return $result
    }
    catch {
        Write-Log "Operation failed: $($_.Exception.Message)" -Level Error
        throw
    }
}
```

### Error Handling

```powershell
$ErrorActionPreference = 'Stop'
try {
    # Risky operation
}
catch {
    Write-Log "Error occurred: $($_.Exception.Message)" -Level Error
    # Handle or re-throw
}
```

## Code Style

- **Parameters**: Use `[CmdletBinding()]` with proper parameter validation
- **Error handling**: `$ErrorActionPreference = 'Stop'` with try/catch blocks
- **Logging**: Use `Write-Log` function with levels (Info, Warning, Error, Success, Debug)
- **Progress**: Use `Write-ProgressHelper` for long operations
- **User input**: Use `Read-Host` with validation, `Get-ValidatedInput` for choices
- **Comments**: Use `<# .SYNOPSIS #>` documentation blocks
- **Naming**: PascalCase for functions, camelCase for variables, descriptive names
- **Constants**: Use `$script:` for module-level variables

## Language Standards

- **Avoid marketing language**: No "enhanced", "advanced", "comprehensive", "sophisticated", etc.
- **Status messages**: Use factual language - "Certificate installed" not "Certificate installed successfully!"
- **Function names**: Clear and direct - `Show-Options.ps1` not `Show-AdvancedOptions.ps1`
- **Comments**: Explain "why" not "what" - focus on functionality over features
- **Log messages**: Keep factual - "Certificate renewed for $domain" not "Successfully completed renewal"

## File Structure Standards

### File Headers

```powershell
# ModuleName/FileName.ps1
<#
    .SYNOPSIS
        Brief description of what the script does.

    .DESCRIPTION
        Detailed description focusing on functionality.

    .PARAMETER ParameterName
        Description of what the parameter does.

    .EXAMPLE
        .\Script.ps1
        Brief description of what this example demonstrates
#>
```

### Function Documentation

```powershell
function Get-Certificate {
    <#
    .SYNOPSIS
        Retrieves certificate information.
    
    .DESCRIPTION
        Gets certificate details from the specified store location.
    
    .PARAMETER Domain
        The domain name to search for.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Domain
    )
    
    # Implementation here
}
```

### Error Handling Pattern

```powershell
try {
    # Operation
    Write-Host "Operation completed" -ForegroundColor Green
} catch {
    Write-Error "Operation failed: $($_.Exception.Message)"
    Write-Log "Operation failed: $($_.Exception.Message)" -Level 'Error'
}
```

### Progress and Status Reporting

```powershell
# Progress indicators
Write-Host "Processing certificate for $domain..." -ForegroundColor Cyan
Write-Host "✓ Certificate obtained" -ForegroundColor Green
Write-Host "⚠ Certificate expires soon" -ForegroundColor Yellow
Write-Host "✗ Certificate validation failed" -ForegroundColor Red

# Log entries (factual, no "successfully")
Write-Log "Certificate renewed for $domain" -Level 'Success'
Write-Log "Module loaded: $moduleName" -Level 'Info'
Write-Log "Configuration validated" -Level 'Info'
```

## Consistency Rules

1. **File Naming**: PascalCase for PowerShell files: `Get-Certificate.ps1`
2. **Function Naming**: Verb-Noun pattern: `Get-Certificate`, `Set-Configuration`
3. **Variable Naming**: camelCase: `$certificateStore`, `$renewalDate`
4. **Constants**: UPPER_CASE: `$RENEWAL_THRESHOLD_DAYS`
5. **Indentation**: 4 spaces (not tabs)
6. **Line Length**: 120 characters maximum
7. **Braces**: Allman style (opening brace on new line)

## Testing Guidelines

- Place tests in `dev-tools/Tests/` directory  
- Use descriptive test names: `It "Should return certificate when valid domain provided"`
- Mock external dependencies: `Mock Get-PAAccount { return @{} }`
- Test both success and failure scenarios
- Use `BeforeEach` for test setup, `AfterEach` for cleanup

### Test Structure

```powershell
Describe "Certificate Registration" {
    It "Should register single domain certificate" {
        # Test implementation
    }
    
    It "Should register wildcard certificate" {
        # Test implementation
    }
    
    It "Should handle DNS validation timeout" {
        # Test implementation
    }
}
```

### Test File Naming

- Unit tests: `ModuleName.Tests.ps1`
- Integration tests: `ModuleName.Integration.Tests.ps1`
- Use descriptive names that clearly indicate what is being tested

## Configuration

- Main config stored in `config.json`
- Sensitive data handled via `Private/Manage-Credentials.ps1`
- Environment-specific settings in `Core/ConfigurationManager.ps1`
- DNS provider configs in `Core/DNSProviderDetection.ps1`

## AutoCert-Specific Patterns

### Module Loading

- Uses dot-sourcing architecture, not Import-Module
- All modules loaded via `Main.ps1` using `. "$PSScriptRoot\path\to\module.ps1"`
- Load order: Core modules first, then Public, then Private functions

### Helper Functions

- Core utilities in `Core/Helpers.ps1`: `Invoke-WithRetry`, `Get-ValidatedInput`, `Write-ProgressHelper`
- Validation functions: `Test-ValidDomain`, `Test-ValidEmail`
- Circuit breaker pattern for external service resilience

### State Management

- Script-scoped variables: `$script:LoadedModules`, `$script:InitializationErrors`
- Environment-based configuration: `$env:LOCALAPPDATA\Posh-ACME\`
- Testing mode: `$env:AUTOCERT_TESTING_MODE = $true`

### DNS Provider Integration

- Auto-detection from available credentials
- Plugin system leveraging Posh-ACME architecture
- Manual mode always available as fallback

## Debugging Tips

- Enable verbose logging: `$VerbosePreference = 'Continue'`
- Check logs in application data directory
- Use `Get-PAAccount` to verify ACME account status
- Test DNS challenges with `Test-DnsChallenge`
- Validate certificates with `Get-ExistingCertificates`

## File Modification Guidelines

- Always run tests after changes: `.\dev-tools\Tests\RunTests.ps1`
- Check code quality: `.\build\Build-Validation.ps1`
- Follow existing patterns in similar functions
- Update help documentation when adding parameters
- Consider backward compatibility for breaking changes

## Available Commands

- `.\build\Build-Validation.ps1`: PSScriptAnalyzer validation and testing
- `.\dev-tools\Tests\RunTests.ps1`: Comprehensive test runner

## Code Review Checklist

Before implementing or modifying code, verify:

- [ ] No marketing buzzwords in comments or messages ("enhanced", "advanced", "comprehensive")
- [ ] Success messages don't use "successfully" - use factual language
- [ ] Function names are clear and not overly verbose
- [ ] Comments explain "why" not "what"
- [ ] Error messages are helpful and specific
- [ ] Variable names are descriptive but not excessive
- [ ] Code follows PowerShell best practices
- [ ] Documentation focuses on functionality
- [ ] Parameter validation is comprehensive
- [ ] Error handling follows try/catch pattern
- [ ] Logging uses appropriate levels (Debug, Info, Warning, Error, Success)
- [ ] Tests cover both success and failure scenarios

## Main Script Parameters

```powershell
.\Main.ps1 [-RenewAll] [-NonInteractive] [-Force] [-ConfigTest] [-LogLevel <level>]
```

- `-RenewAll`: Automatic renewal mode (for scheduled tasks)
- `-NonInteractive`: No user prompts
- `-Force`: Override safety checks
- `-ConfigTest`: Validate configuration only
- `-LogLevel`: Debug, Info, Warning, Error

## Important Notes

- **Admin Required**: Certificate store operations need elevated privileges
- **PowerShell Version**: Compatible with 5.1+ and 7+
- **DNS Providers**: Auto-detected from available credentials
- **Certificates**: Stored in Windows certificate store
- **Logs**: Written to application data directory
- **Config**: JSON-based configuration with credential separation
