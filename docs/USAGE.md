# Usage Guide

This guide covers how to use the Enhanced Certificate Management System for various scenarios.

## 🎯 Quick Start

### Interactive Mode
```powershell
# Start the interactive interface
.\Main.ps1
```

### Command Line Mode
```powershell
# Automatic renewal check
.\Main.ps1 -RenewAll

# Force renewal of all certificates
.\Main.ps1 -RenewAll -Force

# Silent mode for scheduled tasks
.\Main.ps1 -RenewAll -NonInteractive

# Configuration validation
.\Main.ps1 -ConfigTest
```

## 📋 Interactive Menu Guide

### Main Menu Options

**1. Register a New Certificate**
- Single domain certificates (e.g., `example.com`)
- Multi-domain certificates with SANs
- Wildcard certificates (e.g., `*.example.com`)
- Automatic DNS validation

**2. Install Existing Certificate**
- Windows Certificate Store deployment
- IIS website binding configuration
- PEM/PFX file export
- Custom installation locations

**3. Configure Automatic Renewal**
- Windows Scheduled Task setup
- Renewal timing configuration
- Email notification setup
- Load balancing with randomization

**4. View and Manage Existing Certificates**
- Certificate inventory and status
- Individual certificate operations
- Bulk renewal operations
- Certificate export and backup

**5. Advanced Options**
- ACME server configuration
- DNS plugin management
- Certificate format options
- System diagnostics

**6. Manage Credentials**
- DNS provider credential storage
- Credential testing and validation
- Multi-provider management
- Secure credential backup

**7. System Health Check**
- Comprehensive diagnostics
- Network connectivity tests
- Certificate validation
- Performance monitoring

## 🔐 Certificate Registration Workflows

### Single Domain Certificate

#### Step-by-Step Process
1. **Start Registration**:
   ```powershell
   .\Main.ps1  # Select option 1
   ```

2. **Enter Domain**:
   - Primary domain: `example.com`
   - System validates domain format

3. **Select DNS Provider**:
   - Choose from detected providers
   - Or select "Manual DNS" mode

4. **Provide Credentials**:
   - Enter DNS provider API credentials
   - Credentials stored securely

5. **Domain Validation**:
   - System creates TXT record automatically
   - Monitors DNS propagation
   - Validates domain ownership

6. **Certificate Generation**:
   - Let's Encrypt generates certificate
   - Private key created securely
   - Certificate chain assembled

7. **Installation Options**:
   - Windows Certificate Store
   - IIS website bindings
   - PEM/PFX file export
   - Custom locations

#### Example Output
```
Domain Validation Progress:
✓ Creating TXT record: _acme-challenge.example.com
✓ DNS propagation detected (45 seconds)
✓ ACME validation successful
✓ Certificate issued
✓ Installing to LocalMachine\My store
✓ Configuring IIS binding for Default Web Site
✓ Certificate registration complete
```

### Multi-Domain Certificate (SAN)

#### Use Cases
- Multiple websites on same server
- Different domains for same service
- Development/staging/production environments

#### Configuration Process
1. **Primary Domain**: `www.example.com`
2. **Additional Domains**:
   - `example.com`
   - `api.example.com`
   - `cdn.example.com`

#### Validation Requirements
- Each domain validated independently
- All domains must resolve to accessible DNS
- DNS provider must manage all domains

### Wildcard Certificate

#### Benefits
- Covers unlimited subdomains
- Single certificate management
- Cost-effective for large infrastructures

#### Requirements
- DNS validation only (HTTP validation not supported)
- Must use DNS provider with API access
- Includes parent domain automatically

#### Example Configuration
```
Wildcard Domain: *.example.com
Covers: api.example.com, www.example.com, mail.example.com, etc.
Also includes: example.com (parent domain)
```

## 🔄 Certificate Management Operations

### Renewal Operations

#### Automatic Renewal
```powershell
# Check which certificates need renewal
.\Main.ps1 -RenewAll

# Force renewal regardless of expiration date
.\Main.ps1 -RenewAll -Force

# Silent renewal for scheduled tasks
.\Main.ps1 -RenewAll -NonInteractive
```

#### Manual Renewal
1. **Via Interactive Menu**:
   - Select option 4 (Manage Certificates)
   - Choose specific certificate
   - Select "Force Renew"

2. **Check Renewal Status**:
   ```powershell
   # View certificate expiration dates
   Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Issuer -like "*Let's Encrypt*"} | Select-Object Subject, NotAfter
   ```

### Certificate Installation

#### Windows Certificate Store
```powershell
# Install to LocalMachine store (requires admin)
Install-Certificate -Target "LocalMachine" -Certificate $cert

# Install to CurrentUser store
Install-Certificate -Target "CurrentUser" -Certificate $cert
```

#### IIS Website Bindings
```powershell
# Configure HTTPS binding automatically
Install-Certificate -Target "IIS" -Website "Default Web Site" -Certificate $cert

# Multiple websites
Install-Certificate -Target "IIS" -Websites @("Site1", "Site2") -Certificate $cert
```

#### File Export Options
```powershell
# Export as PFX with password
Export-Certificate -Format "PFX" -Password "SecurePassword123!" -Path "C:\Certificates\"

# Export as PEM files
Export-Certificate -Format "PEM" -Path "C:\Certificates\PEM\"

# Export full chain
Export-Certificate -Format "FullChain" -Path "C:\Certificates\"
```

### Certificate Removal

#### Safe Removal Process
1. **Backup First**:
   ```powershell
   # Backup before removal
   Backup-Certificate -Domain "example.com" -Path "C:\CertificateBackups\"
   ```

2. **Remove from Stores**:
   ```powershell
   # Remove from certificate stores
   Remove-Certificate -Domain "example.com" -Stores @("LocalMachine", "CurrentUser")
   ```

3. **Clean IIS Bindings**:
   ```powershell
   # Remove IIS HTTPS bindings
   Remove-Certificate -Domain "example.com" -RemoveIISBindings
   ```

4. **Delete Files**:
   ```powershell
   # Remove certificate files
   Remove-Certificate -Domain "example.com" -RemoveFiles
   ```

## ⚙️ Automatic Renewal Setup

### Scheduled Task Configuration

#### Using AutoCert Setup
1. **Run Setup Wizard**:
   ```powershell
   .\Main.ps1  # Select option 3
   ```

2. **Configure Options**:
   - **Frequency**: Daily (recommended)
   - **Time**: 2:00 AM (low-traffic period)
   - **Randomization**: 30-60 minutes
   - **Retry Logic**: 3 attempts with exponential backoff

#### Manual Task Creation
```powershell
# Create custom scheduled task
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass -File `"C:\Path\To\AutoCert\Main.ps1`" -RenewAll -NonInteractive"

$trigger = New-ScheduledTaskTrigger -Daily -At "2:00AM"

$principal = New-ScheduledTaskPrincipal -UserID "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 10)

Register-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -TaskName "AutoCert Certificate Renewal" -Description "Automatic SSL certificate renewal"
```

### Renewal Configuration

#### Configuration Options
```json
{
  "RenewalThresholdDays": 30,
  "MaxRetries": 3,
  "RetryDelayMinutes": 5,
  "UseRandomization": true,
  "RandomizationWindow": 60,
  "EmailNotifications": true,
  "NotificationEmail": "admin@example.com",
  "BackupBeforeRenewal": true,
  "RollbackOnFailure": true
}
```

#### Testing Renewal
```powershell
# Test renewal process without making changes
.\Main.ps1 -RenewAll -WhatIf

# Test with staging environment
.\Main.ps1 -RenewAll -UseStaging

# Verbose logging for troubleshooting
.\Main.ps1 -RenewAll -LogLevel Debug
```

## 📊 Monitoring and Maintenance

### Health Monitoring

#### System Health Check
```powershell
# Comprehensive health check
.\Main.ps1  # Select option 7

# Command line health check
.\Main.ps1 -ConfigTest
```

#### Certificate Status Monitoring
```powershell
# Check expiration dates
Get-CertificateStatus | Where-Object {$_.DaysUntilExpiry -lt 30}

# Generate status report
Export-CertificateReport -Format HTML -Path "C:\Reports\CertificateStatus.html"
```

### Log Management

#### Log Locations
- **Application Log**: `%LOCALAPPDATA%\Posh-ACME\logs\autocert-application.log`
- **Renewal Log**: `%LOCALAPPDATA%\Posh-ACME\logs\autocert-renewal.log`
- **Error Log**: `%LOCALAPPDATA%\Posh-ACME\logs\autocert-errors.log`
- **Windows Event Log**: Application log, source "AutoCert Certificate Management"

#### Log Analysis
```powershell
# Analyze renewal success rate
$logs = Get-Content "$env:LOCALAPPDATA\Posh-ACME\logs\autocert-renewal.log"
$successes = ($logs | Select-String "renewal successful").Count
$failures = ($logs | Select-String "renewal failed").Count
$successRate = ($successes / ($successes + $failures)) * 100

Write-Host "Renewal Success Rate: $($successRate.ToString('F1'))%"
```

### Performance Optimization

#### Best Practices
1. **Schedule Renewals**: Run during low-traffic periods
2. **Randomize Timing**: Avoid API rate limits
3. **Monitor Resources**: Check system resource usage
4. **Regular Cleanup**: Remove old certificates and logs

#### Performance Tuning
```powershell
# Optimize for multiple certificates
$config = @{
    ParallelRenewals = $true
    MaxConcurrentRenewals = 3
    DNSPropagationTimeout = 300
    RetryDelayMultiplier = 1.5
}
```

## 🔧 Advanced Usage Scenarios

### Enterprise Deployment

#### Multi-Server Management
```powershell
# Deploy certificates to multiple servers
$servers = @("web01", "web02", "web03")
foreach ($server in $servers) {
    Copy-CertificateToServer -Server $server -Certificate $cert
    Invoke-Command -ComputerName $server -ScriptBlock {
        Import-Certificate -CertStoreLocation Cert:\LocalMachine\My -FilePath $certPath
    }
}
```

#### Load Balancer Integration
```powershell
# F5 BIG-IP example
Deploy-CertificateToF5 -F5Host "lb01.example.com" -Certificate $cert -VirtualServers @("vs_web", "vs_api")

# HAProxy example
Export-Certificate -Format PEM -Path "/etc/haproxy/certs/"
Invoke-SSHCommand -Server "lb01" -Command "systemctl reload haproxy"
```

### Development/Testing

#### Staging Environment
```powershell
# Use Let's Encrypt staging for testing
.\Main.ps1 -UseStaging

# Switch back to production
.\Main.ps1 -UseProduction
```

#### Certificate Validation
```powershell
# Validate certificate before deployment
Test-Certificate -Domain "example.com" -CheckRevocation -CheckChain

# Performance testing
Measure-Command { Test-SSLConnection -Domain "example.com" -Port 443 }
```

## 🆘 Emergency Procedures

### Certificate Revocation
```powershell
# Emergency certificate revocation
.\Main.ps1  # Select option 4, then individual certificate, then option 3

# Immediate revocation with reason
Revoke-Certificate -Domain "example.com" -Reason "keyCompromise" -Force
```

### Rollback Procedures
```powershell
# Rollback to previous certificate
Restore-Certificate -Domain "example.com" -BackupDate "2025-07-01"

# Emergency certificate from backup
Import-CertificateFromBackup -Path "C:\CertificateBackups\2025-07-01\example.com.pfx"
```

### Disaster Recovery
```powershell
# Complete system restoration
.\Scripts\Restore-AutoCertSystem.ps1 -BackupPath "C:\AutoCertBackup\2025-07-01"

# Certificate migration to new server
.\Scripts\Migrate-Certificates.ps1 -SourceServer "old-server" -DestinationServer "new-server"
```
