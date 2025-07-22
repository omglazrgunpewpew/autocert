# AutoCert PowerShell Project Instructions

## Architecture Overview

AutoCert is a modular PowerShell certificate management system with a **dot-sourcing architecture**. All modules are loaded via `Main.ps1` using dot-sourcing (`. "$PSScriptRoot\path\to\module.ps1"`), not `Import-Module`. This creates a unified execution scope where all functions are available globally.

### Key Architectural Patterns

**Module Loading Strategy**: The system uses a cascading dot-source pattern in `Main.ps1`:

- Core system modules first (`Core/SystemInitialization.ps1`, `Core/Logging.ps1`)
- Then feature modules (`Public/*.ps1`, `Private/*.ps1`)
- Module dependencies resolved through function availability checks

**Function Organization Strategy**: AutoCert uses a **hybrid approach** prioritizing discoverability over deep nesting:

**Public/Private Separation** (Recommended for AutoCert):

- **Public Functions**: User-facing commands in root `Functions/` folder
  - `Register-Certificate`, `Install-Certificate`, `Set-AutomaticRenewal`
  - Direct dot-sourcing: `. "$PSScriptRoot\Functions\*.ps1"`
- **Private Helpers**: Internal utilities in `Core/Helpers.ps1`
  - `Get-ValidatedInput`, `Write-ProgressHelper`, `Invoke-WithRetry`
  - Single file import eliminates path management complexity

**When to Use Feature Folders** (Limited scenarios):

- **Complex Feature Refactoring**: Only when breaking down 1000+ line monoliths
  - Example: `CertificateInstallation/` (successful 1,343 → 200 line refactor)
  - Pattern: `Get-ChildItem "Feature\*.ps1" | ForEach-Object { . $_.FullName }`
- **Plugin Systems**: DNS providers, notification handlers
  - Self-contained modules with clear boundaries

**Path Complexity Guidelines**:

- **Avoid**: Deep feature hierarchies (`Functions/Certificate/Installation/Windows/IIS/`)
- **Prefer**: Flat structure with descriptive names (`Install-CertificateToIIS.ps1`)
- **Maximum Depth**: 2 levels for dot-sourcing reliability (`Functions/FeatureGroup/*.ps1`)

**Decision Framework for Function Organization**:

```powershell
# ✅ GOOD: Public/Private with flat structure
Functions/
  Register-Certificate.ps1      # Public: User command
  Install-Certificate.ps1       # Public: User command
  Update-AllCertificates.ps1    # Public: User command
Core/
  Helpers.ps1                   # Private: All internal helpers in one file

# ❌ AVOID: Deep feature nesting
Functions/
  Certificate/
    Registration/
      ACME/
        LetsEncrypt/
          Register-LetsEncryptCert.ps1  # Path management nightmare

# ✅ ACCEPTABLE: Feature folders for major refactoring only
Functions/
  CertificateInstallation/      # Only because it was 1,343 lines → modular
    Install-Certificate.ps1     # Orchestrator
    Install-ToIIS.ps1          # Focused component
    Install-ToApache.ps1       # Focused component
```

**When to Create New Files vs Expand Existing**:

- **New File**: Function exceeds 200 lines OR serves distinct user scenario
- **Expand Existing**: Helper functions under 50 lines, related utilities
- **Refactor to Folder**: Single file exceeds 500 lines with clear separation points

**Dot-Sourcing Compatibility Rules**:

- **Single Files**: Always use `*` wildcard: `. "$PSScriptRoot\Functions\*.ps1"`
- **Feature Folders**: Use `Get-ChildItem` pattern for reliability:
  ```powershell
  # In Main.ps1
  Get-ChildItem "$PSScriptRoot\Functions\CertificateInstallation\*.ps1" |
    ForEach-Object { . $_.FullName }
  ```
- **Path Validation**: Test dot-sourcing works from different working directories
- **Load Order**: Core modules first, then Functions, then UI (dependencies matter)

**State Management**: Uses script-scoped variables (`$script:LoadedModules`, `$script:InitializationErrors`) and environment-based configuration (`$env:LOCALAPPDATA\Posh-ACME\`).

## Critical Development Workflows

### Testing Strategy

```powershell
# Run all tests (essential before commits)
.\Tests\RunTests.ps1

# Code quality validation (catches PSScriptAnalyzer issues)
.\build\Build-Validation.ps1

# Individual test debugging
Invoke-Pester -Path "Tests\Autocert.Tests.ps1" -Verbose
```

### Module Refactoring Pattern

Following the successful `CertificateInstallation/` refactoring:

- Break monolithic functions into focused components (50-200 lines each)
- Maintain dot-sourcing compatibility: `Get-ChildItem "Module\*.ps1" | ForEach-Object { . $_.FullName }`
- Use feature folders but avoid deep nesting for path management simplicity

### Error Handling Convention

```powershell
# Standard pattern used throughout
$ErrorActionPreference = 'Stop'
try {
    $result = Invoke-WithRetry -ScriptBlock { /* operation */ } -MaxAttempts 3
    Write-Log "Operation succeeded" -Level 'Info'
} catch {
    Write-Log "Operation failed: $($_.Exception.Message)" -Level 'Error'
    throw  # Re-throw for upstream handling
}
```

## Project-Specific Conventions

### Function Structure Standard

```powershell
function Verb-Noun {
    [CmdletBinding(SupportsShouldProcess = $true)]  # Always include for consistency
    param(
        [Parameter(Mandatory)]
        [ValidateScript({Test-ValidDomain $_})]     # Use custom validators from Helpers.ps1
        [string]$Domain
    )

    Write-ProgressHelper -Activity "Action" -Status "Starting" -PercentComplete 10
    # Implementation with logging at key points
}
```

### Configuration Management

- **Settings**: `Get-ScriptSettings` / `Save-ScriptSettings` for user preferences
- **Renewal Config**: `Get-RenewalConfig` / `Save-RenewalConfig` for automation settings
- **Path Convention**: `$env:LOCALAPPDATA\Posh-ACME\` for all data storage

### Credential Management Pattern

```powershell
# Always use secure credential storage
$cred = Get-SecureCredential -ProviderName 'Cloudflare'
if (-not $cred) {
    $cred = Get-Credential -Message "Enter Cloudflare credentials"
    Set-SecureCredential -ProviderName 'Cloudflare' -Credential $cred
}
```

## Integration Points & Dependencies

### Posh-ACME Module Integration

- **Location**: `Modules/Posh-ACME/` (bundled, not PowerShell Gallery)
- **Initialization**: Always call `Initialize-ACMEServer` before ACME operations
- **Testing Mode**: `$env:AUTOCERT_TESTING_MODE = $true` prevents module updates

### Circuit Breaker Pattern

```powershell
# Used for external service resilience
$script:CircuitBreakers = @{
    'DNSValidation' = [CircuitBreaker]::new(3, 2, 300)
    'CertificateRenewal' = [CircuitBreaker]::new(2, 1, 600)
}
```

### DNS Provider Plugin System

- **Auto-detection**: `Core/DNSProviderDetection.ps1` detects available providers
- **Plugin Loading**: Leverages Posh-ACME's plugin architecture
- **Manual Mode**: Always available as fallback for any DNS provider

## Essential Helper Functions

**Core Utilities** (from `Core/Helpers.ps1`):

- `Invoke-WithRetry`: Exponential backoff for external calls
- `Get-ValidatedInput`: Menu choice validation
- `Write-ProgressHelper`: Consistent progress reporting
- `Test-ValidDomain`, `Test-ValidEmail`: Input validation

**Menu System** (from `Public/` and `Private/`):

- `Show-Menu`: Main application entry point
- `Invoke-MenuOperation`: Error handling wrapper for menu actions
- Follow the pattern: Clear-Host, display options, Get-ValidatedInput

## Development Guidelines

### When Adding New Functions

1. Check if helpers exist in `Core/Helpers.ps1` before creating new ones
2. Use `[CmdletBinding(SupportsShouldProcess)]` for any state-changing operations
3. Add to appropriate feature folder but ensure dot-sourcing in `Main.ps1`
4. Include comprehensive error handling with `Write-Log` calls

### Module Loading Debug

```powershell
# Check loaded module state
Get-LoadedModuleInfo
Test-ModuleDependency  # Validates all required functions are available
```

### Testing Environment Setup

```powershell
# Prevents Posh-ACME updates during testing
$env:AUTOCERT_TESTING_MODE = $true
$env:POSHACME_SKIP_UPGRADE_CHECK = $true
```

This architecture prioritizes **maintainability through modularity** while avoiding the complexity of formal PowerShell modules. The dot-sourcing approach enables the refactoring benefits (like the `CertificateInstallation/` success) without path management overhead.
