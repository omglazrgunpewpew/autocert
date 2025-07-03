# Enhanced Certificate Management System

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)](https://github.com/microsoft/windows)

A comprehensive enterprise-grade PowerShell-based certificate management system for Let's Encrypt certificates on Windows environments. This tool provides robust automation for certificate acquisition, renewal, deployment, and monitoring with advanced error handling, comprehensive logging, and flexible deployment options.

## 📚 Documentation

- **[Installation Guide](docs/INSTALLATION.md)** - Complete setup instructions and system requirements
- **[DNS Provider Setup](docs/DNS-PROVIDERS.md)** - Detailed configuration for 15+ DNS providers
- **[Usage Guide](docs/USAGE.md)** - Comprehensive usage instructions and workflows
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and diagnostic procedures

## 🚀 Key Features

### Certificate Management
- **Fully Automated Certificate Lifecycle**: From acquisition to renewal to deployment
- **Multi-Domain Support**: Single certificates with multiple SANs (Subject Alternative Names)
- **Wildcard Certificate Support**: Secure entire domains with wildcard certificates
- **Certificate Validation**: Built-in certificate integrity checks and validation

### DNS Provider Integration
- **15+ DNS Providers Supported**: Including Cloudflare, AWS Route53, Azure DNS, Google Cloud DNS
- **Automatic DNS Provider Detection**: Intelligent detection of your DNS provider
- **Manual DNS Mode**: Compatible with any DNS provider through manual TXT record validation
- **Secure Credential Management**: Windows Credential Manager integration

### Enterprise Features
- **Windows Certificate Store Integration**: Automatic deployment to certificate stores
- **IIS Website Integration**: Automatic SSL binding configuration and management
- **Advanced Renewal Scheduling**: Flexible scheduling with randomization and load distribution
- **Comprehensive Logging**: Multi-level logging with Windows Event Log integration
- **Email Notifications**: Detailed notifications for renewals, failures, and warnings

### Security & Reliability
- **Robust Error Handling**: Exponential backoff retry logic with intelligent failure recovery
- **Certificate Backup**: Automatic backup of certificates before renewal
- **Secure Credential Storage**: Windows Credential Manager integration
- **Audit Trail**: Complete audit trail of all certificate operations

## ⚡ Quick Start

### Interactive Mode
```powershell
# Clone and run
git clone https://github.com/yourusername/autocert.git
cd autocert
.\Main.ps1
```

### Automated Renewal
```powershell
# Set up automatic renewal (run as Administrator)
.\Main.ps1 -RenewAll -NonInteractive
```

### System Validation
```powershell
# Test configuration
.\Main.ps1 -ConfigTest
```

## 📋 System Requirements

- **Operating System**: Windows 10 (1809+) or Windows Server 2016+
- **PowerShell**: Version 5.1 or later (7.3+ recommended)
- **Administrator Privileges**: Required for certificate store operations
- **Internet Connectivity**: Required for Let's Encrypt ACME API and DNS provider APIs

## 🌐 Supported DNS Providers

| Provider | Setup Difficulty | Wildcard Support | Notes |
|----------|-----------------|------------------|-------|
| **Cloudflare** | Easy | ✅ | Recommended for beginners |
| **AWS Route53** | Medium | ✅ | Enterprise-grade DNS |
| **Azure DNS** | Medium | ✅ | Microsoft cloud integration |
| **Google Cloud DNS** | Medium | ✅ | Google cloud platform |
| **DigitalOcean** | Easy | ✅ | Simple API setup |
| **Manual DNS** | Easy | ✅ | Works with any provider |

[View all 15+ supported providers →](docs/DNS-PROVIDERS.md)

## 🔧 Installation

### Method 1: Git Clone (Recommended)
```powershell
git clone https://github.com/yourusername/autocert.git
cd autocert
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\Main.ps1
```

### Method 2: Download Release
1. Download from [GitHub Releases](https://github.com/yourusername/autocert/releases)
2. Extract to `C:\Tools\AutoCert`
3. Run PowerShell as Administrator
4. Execute `.\Main.ps1`

**[Complete Installation Guide →](docs/INSTALLATION.md)**

## 📖 Usage Examples

### Register a New Certificate
```powershell
# Interactive mode with guided setup
.\Main.ps1
# Select option 1: Register a new certificate

# For domain: example.com
# Choose DNS provider: Cloudflare
# Enter API token: your_cloudflare_token
```

### Automatic Renewal Setup
```powershell
# Set up scheduled renewal
.\Main.ps1
# Select option 3: Configure automatic renewal
```

### Certificate Management
```powershell
# View all certificates
.\Main.ps1
# Select option 4: View and manage existing certificates

# Command line renewal check
.\Main.ps1 -RenewAll

# Force renewal of all certificates
.\Main.ps1 -RenewAll -Force
```

**[Complete Usage Guide →](docs/USAGE.md)**

## 🛡️ Security Features

- **Secure Credential Storage**: DNS provider credentials stored in Windows Credential Manager
- **Certificate Backup**: Automatic backup before renewal operations
- **Audit Logging**: Complete audit trail in Windows Event Log
- **Minimal Permissions**: Follows principle of least privilege
- **TLS 1.2+**: Modern encryption for all communications

## 📊 Monitoring & Logging

### Built-in Monitoring
- **System Health Checks**: Comprehensive diagnostic capabilities
- **Certificate Expiration Monitoring**: Proactive expiration warnings
- **Renewal Success Tracking**: Success/failure statistics
- **Performance Metrics**: Operation timing and system resource usage

### Log Locations
- **Application Logs**: `%LOCALAPPDATA%\Posh-ACME\logs\`
- **Windows Event Log**: Application log, source "AutoCert Certificate Management"
- **Performance Data**: Built-in metrics collection

## 🚨 Troubleshooting

### Common Issues
- **PowerShell Execution Policy**: `Set-ExecutionPolicy RemoteSigned`
- **Module Installation**: Automatic Posh-ACME installation
- **DNS Authentication**: Provider-specific credential setup
- **Certificate Store Access**: Administrator privileges required

**[Complete Troubleshooting Guide →](docs/TROUBLESHOOTING.md)**

### Quick Diagnostics
```powershell
# Run system health check
.\Main.ps1 -ConfigTest

# Check certificate status
Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Issuer -like "*Let's Encrypt*"}

# View recent logs
Get-Content "$env:LOCALAPPDATA\Posh-ACME\logs\autocert-application.log" -Tail 20
```

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. **Fork the Repository**: Create your own fork on GitHub
2. **Create Feature Branch**: `git checkout -b feature/your-feature-name`
3. **Follow Standards**: Use PowerShell best practices and include tests
4. **Submit Pull Request**: Detailed description of changes

### Development Setup
```powershell
# Clone your fork
git clone https://github.com/yourusername/autocert.git
cd autocert

# Install development dependencies
.\Tests\Install-DevDependencies.ps1

# Run tests
.\Tests\RunTests.ps1
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Components
- **Posh-ACME**: Apache 2.0 License
- **PowerShell**: MIT License
- **Windows Management Framework**: Microsoft Software License

## 🙏 Acknowledgments

- **Posh-ACME Team**: For the excellent ACME protocol implementation
- **Let's Encrypt**: For providing free SSL certificates
- **PowerShell Community**: For ongoing support and contributions
- **DNS Provider APIs**: For enabling automated certificate validation

## 📞 Support

### Getting Help
- **📖 Documentation**: Start with the comprehensive guides above
- **🐛 Issues**: [GitHub Issues](https://github.com/yourusername/autocert/issues) for bugs and features
- **💬 Discussions**: [GitHub Discussions](https://github.com/yourusername/autocert/discussions) for questions
- **📚 Resources**: [PowerShell Gallery](https://www.powershellgallery.com/packages/Posh-ACME) | [Let's Encrypt Community](https://community.letsencrypt.org/)

### Enterprise Support
For enterprise deployments requiring professional support:
- **Professional Services**: Custom implementation and integration
- **Training**: On-site training for IT teams
- **Priority Support**: Dedicated support channels

---

**Made with ❤️ for the PowerShell and Let's Encrypt communities**

*Enhanced Certificate Management System v2.0.0 | Last Updated: July 2025*

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Third-Party Components
- **Posh-ACME**: Licensed under Apache 2.0 License
- **PowerShell**: Licensed under MIT License
- **Windows Management Framework**: Microsoft Software License

## 🙏 Acknowledgments

- **Posh-ACME Team**: For the excellent ACME protocol implementation
- **Let's Encrypt**: For providing free SSL certificates
- **PowerShell Community**: For ongoing support and contributions
- **DNS Provider APIs**: For enabling automated certificate validation

## 📞 Support and Community

### Getting Help
- **Documentation**: Start with this comprehensive README
- **GitHub Issues**: For bug reports and feature requests
- **GitHub Discussions**: For questions and community support
- **Stack Overflow**: Tag questions with `powershell` and `lets-encrypt`

### Community Resources
- **PowerShell Gallery**: [Posh-ACME Module](https://www.powershellgallery.com/packages/Posh-ACME)
- **Let's Encrypt Community**: [Community Forum](https://community.letsencrypt.org/)
- **PowerShell Community**: [PowerShell.org](https://powershell.org/)

### Enterprise Support
For enterprise deployments requiring professional support:
- **Professional Services**: Custom implementation and integration
- **Training**: On-site training for IT teams
- **Priority Support**: Dedicated support channels
- **Custom Development**: Feature development for specific requirements

---

**Made with ❤️ for the PowerShell and Let's Encrypt communities**

*Last Updated: July 2025 | Version 2.0.0*

