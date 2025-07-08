# AutoCert PowerShell Style Guide

This document outlines the coding and language standards for the AutoCert certificate management system.

## Language Standards

### Avoid Marketing Language

Remove verbose adjectives and marketing buzzwords that don't add functional value:

**❌ Avoid:**

- Enhanced, Advanced, Improved, Comprehensive
- Sophisticated, Intelligent, Smart, Cutting-edge
- State-of-the-art, Next-generation, World-class
- Industry-leading, Enterprise-grade, Professional
- Premium, Superior, Exceptional, Outstanding
- Revolutionary, Innovative, Breakthrough
- Perfect, Ideal, Ultimate, Maximum, Complete

**✅ Use instead:**

- Direct, functional descriptions
- Simple, clear language
- Focus on what the code does, not how "great" it is

### Status Messages

Keep success messages concise and factual:

**❌ Avoid:**

```powershell
Write-Host "Certificate installed successfully!" -ForegroundColor Green
Write-Host "Module loaded successfully" -ForegroundColor Green
Write-Host "Configuration validated successfully" -ForegroundColor Green
```

**✅ Use instead:**

```powershell
Write-Host "Certificate installed" -ForegroundColor Green
Write-Host "Module loaded" -ForegroundColor Green  
Write-Host "Configuration validated" -ForegroundColor Green
```

### Function and File Naming

Use clear, descriptive names without unnecessary adjectives:

- `Show-AdvancedOptions.ps1` → **✅** `Show-Options.ps1`
- `Enhanced-Certificate.ps1` → **✅** `Certificate.ps1`
- `Comprehensive-Validation.ps1` → **✅** `Validation.ps1`

### Comments and Headers

Keep comments functional and informative:

**❌ Avoid:**

```powershell
# Enhanced Core/Logging.ps1
# Enhanced certificate registration with comprehensive DNS provider support
# Function to securely store credentials with advanced encryption
```

**✅ Use instead:**

```powershell
# Core/Logging.ps1
# Certificate registration with DNS provider support
# Function to store credentials
```

## Code Organization Standards

### File Headers

Use this standard format for PowerShell files:

```powershell
# ModuleName/FileName.ps1
<#
    .SYNOPSIS
        Brief description of what the script does.

    .DESCRIPTION
        Detailed description focusing on functionality, not marketing language.

    .PARAMETER ParameterName
        Description of what the parameter does.

    .EXAMPLE
        .\Script.ps1
        Brief description of what this example demonstrates
#>
```

### Function Documentation

Keep function documentation clear and concise:

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
        [string]$Domain
    )
    
    # Implementation here
}
```

### Progress and Status Reporting

Use consistent patterns for user feedback:

```powershell
# Progress reporting
Write-Host "Processing certificate for $domain..." -ForegroundColor Cyan
Write-Host "✓ Certificate obtained" -ForegroundColor Green
Write-Host "⚠ Certificate expires soon" -ForegroundColor Yellow
Write-Host "✗ Certificate validation failed" -ForegroundColor Red

# Log entries (factual, no "successfully")
Write-Log "Certificate renewed for $domain" -Level 'Success'
Write-Log "Module loaded: $moduleName" -Level 'Info'
Write-Log "Configuration validated" -Level 'Info'
```

## PowerShell Coding Standards

### Error Handling

Use consistent error handling patterns:

```powershell
try {
    # Operation
    Write-Host "Operation completed" -ForegroundColor Green
} catch {
    Write-Error "Operation failed: $($_.Exception.Message)"
    Write-Log "Operation failed: $($_.Exception.Message)" -Level 'Error'
}
```

### Variable Naming

Use clear, descriptive variable names:

```powershell
# Good
$certificateThumbprint = $cert.Thumbprint
$renewalThreshold = (Get-Date).AddDays(30)
$configurationPath = "$env:LOCALAPPDATA\Posh-ACME"

# Avoid overly verbose names
$advancedConfigurationManagementSystemPath = "..." # Too verbose
```

### Function Parameters

Use clear parameter validation:

```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Domain,
    
    [Parameter()]
    [ValidateSet('Production', 'Staging')]
    [string]$Environment = 'Production',
    
    [Parameter()]
    [switch]$Force
)
```

## Menu and UI Standards

### Menu Text

Keep menu options concise:

**❌ Avoid:**

```text
1) Register: Obtain new certificates with automated DNS validation
2) Install: Deploy certificates to various targets with verification  
3) Renewal: Set up automated renewal with advanced scheduling
```

**✅ Use instead:**

```text
1) Register: Obtain certificates with DNS validation
2) Install: Deploy certificates to targets
3) Renewal: Set up renewal scheduling
```

### Help Text

Focus on functionality over features:

**❌ Avoid:**

```text
"This advanced tool provides comprehensive certificate management with intelligent DNS provider detection"
```

**✅ Use instead:**

```text
"Certificate management tool with DNS provider detection"
```

## Logging Standards

### Log Levels

Use appropriate log levels:

- **Debug**: Detailed diagnostic information
- **Info**: General information about program execution
- **Warning**: Something unexpected happened but operation can continue
- **Error**: An error occurred that prevented operation completion
- **Success**: Operation completed as expected

### Log Message Format

Keep log messages factual and informative:

```powershell
# Good log messages
Write-Log "Certificate renewal started for $domain" -Level 'Info'
Write-Log "Certificate renewed, expires $expiryDate" -Level 'Success'
Write-Log "DNS validation timeout after 300 seconds" -Level 'Warning'
Write-Log "Certificate installation failed: $error" -Level 'Error'

# Avoid verbose log messages
Write-Log "Successfully completed advanced certificate renewal process" # Too verbose
```

## Testing Standards

### Test Naming

Use descriptive test names:

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

## Documentation Standards

### README Files

Structure documentation clearly:

1. **Purpose** - What the module/script does
2. **Requirements** - Prerequisites and dependencies
3. **Installation** - How to set up
4. **Usage** - How to use with examples
5. **Configuration** - Available options
6. **Troubleshooting** - Common issues

### Inline Comments

Use comments to explain "why" not "what":

```powershell
# Good - explains why
$delay = $attempt * 2  # Exponential backoff for retry logic

# Avoid - explains what (code already shows this)
$delay = $attempt * 2  # Set delay to attempt times 2
```

## Consistency Rules

1. **File Naming**: Use PascalCase for PowerShell files: `Get-Certificate.ps1`
2. **Function Naming**: Use Verb-Noun pattern: `Get-Certificate`, `Set-Configuration`
3. **Variable Naming**: Use camelCase: `$certificateStore`, `$renewalDate`
4. **Constants**: Use UPPER_CASE: `$RENEWAL_THRESHOLD_DAYS`
5. **Indentation**: Use 4 spaces (not tabs)
6. **Line Length**: Aim for 120 characters maximum
7. **Braces**: Use Allman style (opening brace on new line)

## Review Checklist

Before committing code, verify:

- [ ] No marketing buzzwords in comments or messages
- [ ] Success messages don't use "successfully"
- [ ] Function names are clear and not overly verbose
- [ ] Comments explain "why" not "what"
- [ ] Error messages are helpful and specific
- [ ] Variable names are descriptive but not excessive
- [ ] Code follows PowerShell best practices
- [ ] Documentation focuses on functionality

## Examples of Good vs. Bad

### Good Example

```powershell
# Core/CertificateManager.ps1
function Get-CertificateInfo {
    <#
    .SYNOPSIS
        Retrieves certificate information from the store.
    #>
    param([string]$Thumbprint)
    
    try {
        $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $Thumbprint }
        Write-Log "Certificate retrieved: $Thumbprint" -Level 'Info'
        return $cert
    } catch {
        Write-Error "Failed to retrieve certificate: $($_.Exception.Message)"
        return $null
    }
}
```

### Bad Example (Avoid)

```powershell
# Enhanced-Core/Advanced-Certificate-Manager.ps1
function Get-ComprehensiveCertificateInformationWithAdvancedFeatures {
    <#
    .SYNOPSIS
        Intelligently retrieves comprehensive certificate information using advanced algorithms.
    #>
    param([string]$Thumbprint)
    
    try {
        $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $Thumbprint }
        Write-Log "Certificate retrieved successfully with advanced processing" -Level 'Info'
        Write-Host "Certificate information obtained successfully!" -ForegroundColor Green
        return $cert
    } catch {
        Write-Error "Failed to successfully retrieve certificate information"
        return $null
    }
}
```

---

*This style guide should be reviewed and updated as the project evolves to maintain consistency and clarity across all code.*
