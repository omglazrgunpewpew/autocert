# Testing Environment Fixes for AutoCert

## Problem
The Posh-ACME module was attempting to update during testing, which failed because the module was actively in use. This prevented proper testing and development workflows.

## Solution

### 1. Auto-Detection of Development Environment
Modified `Main.ps1` to automatically detect when running from a development repository and set testing environment variables:

- Checks for existence of `Modules\Posh-ACME` directory
- Automatically sets `AUTOCERT_TESTING_MODE=true` and `POSHACME_SKIP_UPGRADE_CHECK=true`
- Prevents module updates without manual intervention

### 2. Manual Testing Environment Setup
Created `Set-TestingEnvironment.ps1` script for explicit testing mode setup:

- Sets required environment variables
- Provides clear feedback about testing mode status
- Can be forced to override existing settings

### 3. Test Suite Path Corrections
Fixed all test files to use correct paths:

- **Fixed Files:**
  - `dev-tools\Tests\Autocert.Tests.ps1`
  - `dev-tools\Tests\Autocert.Integration.Tests.ps1`
  - `dev-tools\Tests\Autocert.Resilience.Tests.ps1`
  - `dev-tools\Tests\Autocert.Complete.Tests.ps1`

- **Changes Made:**
  - Calculate repository root: `Split-Path (Split-Path $PSScriptRoot -Parent) -Parent`
  - Use `$repoRoot` prefix for all module paths
  - Corrected `Functions` → `Public` directory references
  - Set testing environment variables in each test

### 4. Enhanced Module Loading Feedback
Improved `Core\Initialize-PoshAcme.ps1`:

- Better logging when update checks are skipped
- Clear indication of testing/development mode usage

### 5. Module Loading Test Updates
Updated `Test-LoadModules.ps1`:

- Sets testing environment variables before loading
- Prevents accidental module updates during development

## Environment Variables

### AUTOCERT_TESTING_MODE
- **Purpose**: Indicates the system should use bundled Posh-ACME module
- **Effect**: Forces use of repository's `Modules\Posh-ACME` instead of system-installed version

### POSHACME_SKIP_UPGRADE_CHECK
- **Purpose**: Prevents automatic module update checks
- **Effect**: Skips all update attempts, avoiding conflicts with active modules

## Usage

### For Development
The system now automatically detects development environments. No manual setup required.

### For Manual Testing
```powershell
# Set testing environment
.\Set-TestingEnvironment.ps1

# Run tests
.\dev-tools\Tests\RunTests.ps1 -TestType Unit

# Load modules for testing
.\Test-LoadModules.ps1
```

### For Clearing Testing Mode
```powershell
Remove-Item Env:AUTOCERT_TESTING_MODE
Remove-Item Env:POSHACME_SKIP_UPGRADE_CHECK
```

## Verification

All fixes have been tested and verified:

1. ✅ Unit tests pass without module update attempts
2. ✅ Module loading works correctly in testing mode
3. ✅ Auto-detection works when repository structure is present
4. ✅ Manual testing environment setup functions properly
5. ✅ Test suite paths are corrected and functional

## Future Considerations

- The auto-detection ensures developers don't need to remember to set testing variables
- All test files now use consistent path resolution
- Testing environment is isolated from system-wide PowerShell modules
- Posh-ACME updates only occur in production/non-testing scenarios

This solution maintains the dot-sourcing architecture while providing robust testing capabilities and preventing module update conflicts during development.
