# Installation Guide

## 🔧 System Requirements

### Minimum Requirements

- **Operating System**: Windows 10 (1809+) or Windows Server 2016+
- **PowerShell**: Version 5.1 or later
- **Administrator Privileges**: Required for certificate store operations and IIS management
- **Internet Connectivity**: Required for Let's Encrypt ACME API and DNS provider APIs
- **.NET Framework**: 4.7.2 or later (usually pre-installed)

### Recommended Requirements

- **Operating System**: Windows 11 or Windows Server 2019+
- **PowerShell**: Version 7.3+ for optimal performance and compatibility
- **Memory**: 4GB RAM minimum, 8GB+ recommended for multiple certificates
- **Storage**: 1GB free space for certificate storage and logs
- **Network**: Stable internet connection with minimal latency

### Dependencies

- **Posh-ACME Module**: Automatically installed if not present (requires PowerShell Gallery access)
- **Windows Management Framework**: 5.1+ (included in modern Windows versions)
- **TLS 1.2**: Required for secure ACME communications (enabled by default in modern Windows)

## 📦 Installation Methods

### Method 1: Git Clone (Recommended for Development)

```powershell
# Clone the repository
git clone https://github.com/yourusername/autocert.git
cd autocert

# Set execution policy (if needed)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run initial setup
.\Main.ps1
```

### Method 2: Download ZIP

1. Download the latest release from [GitHub Releases](https://github.com/yourusername/autocert/releases)
2. Extract to a folder (e.g., `C:\Tools\AutoCert`)
3. Open PowerShell as Administrator
4. Navigate to the extracted folder
5. Run `.\Main.ps1`

### Method 3: PowerShell Gallery (Coming Soon)

```powershell
# Install from PowerShell Gallery
Install-Module -Name AutoCert -Scope AllUsers

# Import and run
Import-Module AutoCert
Start-AutoCert
```

## 🚀 First-Time Setup

When you run `.\Main.ps1` for the first time, the system will:

1. **Check Prerequisites**: Verify PowerShell version, administrator privileges, and system compatibility
2. **Install Dependencies**: Automatically install Posh-ACME module from PowerShell Gallery
3. **Configure ACME Server**: Set up Let's Encrypt production or staging environment
4. **System Health Check**: Validate configuration and network connectivity
5. **Create Directories**: Set up necessary folders for certificates and logs
6. **Initialize Logging**: Configure Windows Event Log source registration

## ⚙️ Configuration Files

After installation, you can customize the system by creating configuration files in the main directory:

### Main Configuration (config.json)

```json
{
  "ACMEServer": "https://acme-v02.api.letsencrypt.org/directory",
  "RenewalThresholdDays": 30,
  "MaxRetries": 3,
  "RetryDelayMinutes": 5,
  "UseRandomization": true,
  "RandomizationWindow": 120,
  "DefaultInstallTarget": "WindowsStore",
  "BackupCertificates": true,
  "BackupRetentionDays": 90,
  "LogLevel": "Info",
  "LogRetentionDays": 30
}
```

### DNS Provider Configuration (dns-config.json)

```json
{
  "DefaultProvider": "Cloudflare",
  "Providers": {
    "Cloudflare": {
      "PluginName": "Cloudflare",
      "AuthParameters": ["CFToken"],
      "ZoneSelectionMode": "Automatic"
    },
    "Route53": {
      "PluginName": "Route53",
      "AuthParameters": ["R53AccessKey", "R53SecretKey"],
      "RegionOverride": "us-east-1"
    }
  }
}
```

### Email Notification Configuration (email-config.json)

```json
{
  "Enabled": true,
  "SMTPServer": "smtp.gmail.com",
  "SMTPPort": 587,
  "UseSSL": true,
  "FromAddress": "certificates@yourcompany.com",
  "ToAddresses": ["admin@yourcompany.com", "security@yourcompany.com"],
  "NotificationTypes": {
    "RenewalSuccess": true,
    "RenewalFailure": true,
    "ExpirationWarning": true,
    "SystemHealth": false
  }
}
```

## 🔍 Verification

After installation, verify the system is working correctly:

```powershell
# Run configuration test
.\Main.ps1 -ConfigTest

# Check system health
.\Main.ps1 # Select option 7 for System Health Check
```

## 🔄 Updating

To update the system:

```powershell
# If installed via Git
git pull origin main

# If installed via ZIP, download and extract the latest version
# Configuration files will be preserved
```

## 🗑️ Uninstallation

To remove the system:

1. Remove any scheduled tasks: `Get-ScheduledTask -TaskName "*AutoCert*" | Unregister-ScheduledTask`
2. Remove certificates if desired: Check certificates in `Cert:\LocalMachine\My`
3. Delete the installation folder
4. Clean up Posh-ACME data: `Remove-Item "$env:LOCALAPPDATA\Posh-ACME" -Recurse -Force`
