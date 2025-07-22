# AutoCert Directory Structure

This document describes the reorganized directory structure of the AutoCert project.

## Core Script Functionality

### Public Functions (`Public/`)

User-facing command functions that provide the main certificate management functionality:

- `Get-ExistingCertificates.ps1` - List and display existing certificates
- `Install-Certificate.ps1` - Install certificates to various stores and services
- `Register-Certificate.ps1` - Register new certificates with Let's Encrypt
- `Remove-Certificate.ps1` - Remove certificates from stores
- `Revoke-Certificate.ps1` - Revoke certificates with Let's Encrypt
- `Set-AutomaticRenewal.ps1` - Configure automatic certificate renewal
- `Show-Options.ps1` - Display available configuration options
- `Update-AllCertificates.ps1` - Update and renew all certificates
- `Show-Menu.ps1` - Main application menu system (formerly UI/MainMenu.ps1)
- `Show-Help.ps1` - Help and documentation system (formerly UI/HelpSystem.ps1)
- `BackupManager.ps1` - Certificate backup functionality (moved from Core)
- `NotificationManager.ps1` - Notification system (moved from Core)

### Private Functions (`Private/`)

Internal helper functions and UI components:

#### User Interface Components

- `CertificateMenu.ps1` - Certificate management menu (formerly UI/CertificateMenu.ps1)
- `CredentialMenu.ps1` - DNS provider credential management menu (formerly UI/CredentialMenu.ps1)

#### Internal Functions

- `Manage-Credentials.ps1` - DNS provider credential management
- **Certificate Installation Functions** (formerly CertificateInstallation module):
  - `Export-CertificateMultipleFormats.ps1` - Export certificates in multiple formats
  - `Export-CertificateToPFX.ps1` - Export certificates to PFX format
  - `Install-CertificateToPEM.ps1` - Install certificates as PEM files
  - `Install-CertificateToStore.ps1` - Install certificates to Windows certificate store
  - `Select-CertificateForInstallation.ps1` - Certificate selection interface
  - `Show-CertificateInformation.ps1` - Display certificate details
  - `Show-DetailedCertificateInformation.ps1` - Show detailed certificate information
  - `Show-InstallationOptionsMenu.ps1` - Installation options menu
  - `Show-PostInstallationMenu.ps1` - Post-installation menu
- `Test-CertificateInstallation.ps1` - Test certificate installation
- `Test-RefactoredComponents.ps1` - Test refactored components
- `CertificateInstallation.psd1` / `CertificateInstallation.psm1` - Module definition files
- `CertificateCache.ps1` - Certificate caching system (moved from Core)
- `EnhancedErrorRecovery.ps1` - Error recovery mechanisms (moved from Core)
- `CircuitBreaker.ps1` - Circuit breaker pattern implementation (moved from Core)
- `HealthMonitor.ps1` - System health monitoring (moved from Core)### Core System (`Core/`)

Core system modules providing foundational functionality:

- `SystemInitialization.ps1` - Module loading and system setup
- `Logging.ps1` - Logging system
- `Helpers.ps1` - Common utility functions
- `ConfigurationManager.ps1` - Configuration management
- `RenewalConfig.ps1` - Renewal configuration
- `RenewalOperations.ps1` - Certificate renewal operations
- `SystemDiagnostics.ps1` - System health and diagnostics
- `Initialize-PoshAcme.ps1` - Posh-ACME module initialization
- `ErrorHandlingHelpers.ps1` - Error handling utilities
- `DNSProvider/` - DNS provider detection and management

### Supporting Directories

#### Documentation (`docs/`)

User and developer documentation

#### Modules (`Modules/`)

External module dependencies (Posh-ACME)

#### Scheduling (`Scheduling/`)

Windows Task Scheduler configuration files

#### Development Tools (`dev-tools/`)

##### Note: This directory is excluded from Git (.gitignore)

Contains development, diagnostic, and maintenance tools:

- `tools/` - Code quality, refactoring, and style guide tools
- `build/` - Build validation tools
- `Tests/` - All test files and test utilities
- `backups/` - Backup files from refactoring
- `diagnostics/` - System diagnostic utilities
- `dev-utilities/` - Development-only utilities

## Module Loading Architecture

AutoCert uses a dot-sourcing architecture where all modules are loaded via `Main.ps1` and `Core/SystemInitialization.ps1`. The loading order is:

1. **Core System Modules** - Logging, helpers, configuration
2. **Public Functions** - User-facing commands (loaded individually)
3. **Private Functions** - Internal helpers and UI (loaded as a batch from Private directory)

This creates a unified execution scope where all functions are available globally while maintaining clear separation between public APIs and private implementation details. All Private functions, including the former CertificateInstallation module components, are now loaded automatically from the Private directory.

## Git Configuration

The `.gitignore` file excludes:

- `dev-tools/` - All development and diagnostic tools
- Temporary files, logs, and build artifacts
- Sensitive data (certificates, keys, credentials)
- Test results and reports

This ensures that only production-ready code and documentation are tracked in the repository.
