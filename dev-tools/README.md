# AutoCert Development Tools

This directory contains development, diagnostic, and maintenance tools that are not part of the core AutoCert functionality. These tools are excluded from GitHub synchronization via .gitignore.

## Directory Structure

### `tools/`
Code quality, refactoring, and style guide validation tools:
- PSScriptAnalyzer configurations and custom rules
- Code quality validation scripts
- Style guide enforcement tools
- Refactoring utilities

### `build/`
Build validation and CI/CD related tools:
- Build validation scripts
- Deployment utilities

### `Tests/`
All test files and testing utilities:
- Unit tests
- Integration tests  
- Resilience tests
- Test runners and reporting

### `backups/`
Backup files from refactoring and development:
- Original file backups
- Refactored file versions
- Development snapshots

### `dev-utilities/`
Development-only utilities (moved from Utilities/):
- Configuration validation tools
- Error handling test utilities
- Module management development tools
- Renewal management diagnostics

### `diagnostics/`
System diagnostic tools for development (separate from user-facing diagnostics):
- Performance profiling tools
- Memory usage analyzers
- Debug utilities

## Usage

These tools are meant for:
- Development workflow automation
- Code quality enforcement
- Testing and validation
- Performance analysis
- Debugging and troubleshooting

## Important Notes

1. **Not Production Code**: These tools are not part of the production AutoCert system
2. **Git Ignored**: This entire directory is excluded from version control
3. **Local Development**: Tools are for local development environment only
4. **Documentation**: Each subdirectory contains its own README with specific tool documentation

## Running Tools

Most tools can be run from the AutoCert root directory:

```powershell
# Run all tests
.\dev-tools\Tests\RunTests.ps1

# Validate code quality
.\dev-tools\build\Build-Validation.ps1

# Check style guide compliance
.\dev-tools\tools\Run-StyleGuideValidation.ps1
```

## Adding New Development Tools

When adding new development tools:
1. Place them in the appropriate subdirectory
2. Update this README if adding new categories
3. Ensure they don't interfere with production functionality
4. Document usage in the tool's header comments
