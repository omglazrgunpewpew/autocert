# AutoCert Root Directory Cleanup Summary

## Changes Made

### Directory Structure Reorganization

#### New Directories Created:
- `build/` - Build and CI/CD related tools
- `tools/` - Development and testing tools

#### Files Moved:

**From root to `tools/`:**
- `Apply-Refactoring.ps1` → `tools/Apply-Refactoring.ps1`
- `Test-Refactoring.ps1` → `tools/Test-Refactoring.ps1`
- `Test-StyleGuideRules.ps1` → `tools/Test-StyleGuideRules.ps1`
- `Validate-StyleGuideRules.ps1` → `tools/Validate-StyleGuideRules.ps1`
- `PSScriptAnalyzerSettings.psd1` → `tools/PSScriptAnalyzerSettings.psd1`
- `Main.ps1.new` → `tools/Main.ps1.new`
- `CustomRules/` → `tools/CustomRules/`

**From `Scripts/` to `build/`:**
- `Scripts/Build-Validation.ps1` → `build/Build-Validation.ps1`

**From `Scripts/` to `tools/`:**
- `Scripts/Test-AutoCert.ps1` → `tools/Test-AutoCert.ps1`

#### Files Removed:
- `markdown_issues.json` (empty file)
- `Scripts/` directory (after moving contents)

### Reference Updates

#### Updated file references in:
- `tools/Validate-StyleGuideRules.ps1` - Updated PSScriptAnalyzerSettings.psd1 path
- `build/Build-Validation.ps1` - Updated to reference tools directory for settings
- `.github/workflows/ci-cd.yml` - Updated paths for build validation and analysis
- `README.md` - Updated development documentation references
- `tools/Apply-Refactoring.ps1` - Updated to work with Main.ps1 in parent directory
- `tools/Test-Refactoring.ps1` - Updated all module paths to reference parent directory

### Documentation Added

#### New README files:
- `tools/README.md` - Documents development and testing tools
- `build/README.md` - Documents build and CI/CD tools

#### Updated documentation:
- Main `README.md` - Updated build script reference and removed non-existent dev dependency script

## Final Directory Structure

```
autocert/
├── build/                          # Build and CI/CD tools
│   ├── Build-Validation.ps1
│   └── README.md
├── tools/                          # Development and testing tools
│   ├── Apply-Refactoring.ps1
│   ├── Test-Refactoring.ps1
│   ├── Test-StyleGuideRules.ps1
│   ├── Validate-StyleGuideRules.ps1
│   ├── Test-AutoCert.ps1
│   ├── PSScriptAnalyzerSettings.psd1
│   ├── Main.ps1.new
│   ├── CustomRules/
│   │   └── AutoCertStyleRules.psm1
│   └── README.md
├── Core/                           # Core functionality modules
├── Functions/                      # Main certificate functions
├── UI/                            # User interface components
├── Utilities/                     # Utility functions
├── Tests/                         # Test suites
├── docs/                          # Documentation
├── Modules/                       # External modules
├── Main.ps1                       # Main entry point
└── README.md                      # Project documentation
```

## Benefits of Reorganization

1. **Cleaner Root Directory**: Removed development/testing clutter from the main directory
2. **Logical Grouping**: Related tools are now grouped together in appropriate directories
3. **Better Separation of Concerns**: 
   - `build/` for CI/CD and build processes
   - `tools/` for development and testing utilities
4. **Improved Maintainability**: Easier to find and manage development tools
5. **Better Documentation**: Each tools directory has its own README explaining contents
6. **Updated References**: All file references have been updated to work with the new structure

## Migration Notes

- All path references have been updated to maintain functionality
- CI/CD workflows have been updated to use the new structure
- Development documentation has been updated to reflect new paths
- No functional changes to the main AutoCert application
