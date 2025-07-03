# Enhanced Certificate Management System

A comprehensive PowerShell-based certificate management system for Let's Encrypt certificates on Windows environments. This tool provides enterprise-grade automation for certificate acquisition, renewal, and deployment with robust error handling and monitoring capabilities.

## Features

- **Automatic Certificate Management**: Seamless Let's Encrypt certificate acquisition and renewal
- **DNS Provider Auto-Detection**: Support for 10+ DNS providers including Cloudflare, AWS Route53, Azure DNS
- **Enterprise Integration**: IIS website integration and Windows Certificate Store management
- **Robust Error Handling**: Exponential backoff retry logic and comprehensive logging
- **Advanced Scheduling**: Flexible renewal scheduling with randomization for load distribution
- **Multiple Installation Targets**: Certificate stores, IIS bindings, PEM/PFX file exports
- **System Health Monitoring**: Built-in diagnostics and configuration validation
- **Email Notifications**: Automated alerts for renewal events and failures
- **Interactive & Automated Modes**: GUI for manual management, silent mode for scheduled tasks

## Requirements

- **PowerShell**: Version 5.1 or later (PowerShell 7+ recommended)
- **Administrator Privileges**: Required for certificate store operations
- **Posh-ACME Module**: Automatically installed if not present
- **Windows**: Compatible with Windows 10, Windows Server 2016+

## Quick Start

### Interactive Mode
```powershell
# Run the main script for interactive certificate management
.\Main.ps1
```

### Automated Renewal (Scheduled Tasks)
```powershell
# Check and renew certificates automatically
.\Main.ps1 -RenewAll -NonInteractive

# Force renewal of all certificates
.\Main.ps1 -RenewAll -Force -NonInteractive
```

### Configuration Testing
```powershell
# Validate system configuration
.\Main.ps1 -ConfigTest
```

## Installation

1. **Clone the repository**:
   ```powershell
   git clone https://github.com/yourusername/autocert.git
   cd autocert
   ```

2. **Run as Administrator** (required for certificate operations)

3. **First-time setup**:
   ```powershell
   .\Main.ps1
   ```
   The system will automatically install required modules and guide you through initial configuration.

## Supported DNS Providers

- Cloudflare
- AWS Route53
- Azure DNS
- Google Cloud DNS
- DigitalOcean
- DNS Made Easy
- Namecheap
- GoDaddy
- Linode
- Vultr
- Hetzner
- OVH
- Manual DNS (universal compatibility)

## Certificate Installation Targets

- **Windows Certificate Store** (LocalMachine/CurrentUser)
- **IIS Websites** with automatic binding configuration
- **PEM Files** for Linux/Apache/Nginx servers
- **PFX Files** with custom password protection
- **Multi-format export** for maximum compatibility

