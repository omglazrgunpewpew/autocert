# Troubleshooting Guide

This guide helps you diagnose and resolve common issues with the Enhanced Certificate Management System.

## 🚨 Common Issues and Solutions

### 1. PowerShell Execution Policy Error

**Error**: `"Execution of scripts is disabled on this system"`

**Cause**: PowerShell execution policy prevents script execution

**Solution**:

```powershell
# Check current execution policy
Get-ExecutionPolicy

# Set execution policy for current user (recommended)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or for all users (requires admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine

# Temporarily bypass for single execution
PowerShell.exe -ExecutionPolicy Bypass -File ".\Main.ps1"
```

### 2. Posh-ACME Module Installation Failure

**Error**: `"Unable to install Posh-ACME module"`

**Cause**: PowerShell Gallery access issues or permission problems

**Solution**:

```powershell
# Check PowerShell Gallery connectivity
Test-NetConnection -ComputerName "www.powershellgallery.com" -Port 443

# Manual installation
Install-Module -Name Posh-ACME -Force -AllowClobber -Scope CurrentUser

# Alternative: Install from specific repository
Install-Module -Name Posh-ACME -Repository PSGallery -Force

# Check if module is available
Get-Module -ListAvailable -Name Posh-ACME

# Import module manually
Import-Module Posh-ACME -Force
```

### 3. DNS Provider Authentication Failure

**Error**: `"DNS provider authentication failed"`

**Diagnostic Steps**:

```powershell
# Check stored credentials
cmdkey /list:AutoCert*

# Test network connectivity to DNS provider
Test-NetConnection -ComputerName "api.cloudflare.com" -Port 443
Test-NetConnection -ComputerName "route53.amazonaws.com" -Port 443
```

**Provider-Specific Solutions**:

#### Cloudflare Issues

```powershell
# Test API token manually
$token = "your_token_here"
$headers = @{ "Authorization" = "Bearer $token" }
$response = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/user/tokens/verify" -Headers $headers

# Check token permissions
if ($response.success) {
    Write-Host "Token valid" -ForegroundColor Green
    $response.result | Format-List
} else {
    Write-Host "Token invalid" -ForegroundColor Red
    $response.errors | Format-List
}
```

#### AWS Route53 Issues

```powershell
# Test AWS credentials
$accessKey = "your_access_key"
$secretKey = "your_secret_key"

# Test using AWS CLI (if installed)
aws route53 list-hosted-zones --region us-east-1

# Test using PowerShell
$credential = New-AWSCredential -AccessKey $accessKey -SecretKey $secretKey
Get-R53HostedZone -Credential $credential -Region us-east-1
```

#### Azure DNS Issues

```powershell
# Test service principal authentication
$tenantId = "your_tenant_id"
$clientId = "your_client_id"
$clientSecret = "your_client_secret"

# Test connection
$secureSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential ($clientId, $secureSecret)

Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId $tenantId
Get-AzDnsZone
```

### 4. Certificate Renewal Failure

**Error**: `"Certificate renewal failed"`

**Diagnostic Steps**:

```powershell
# Check certificate status
Get-PACertificate -MainDomain "example.com"

# Check order status
Get-PAOrder -MainDomain "example.com"

# Test DNS resolution
nslookup -type=TXT _acme-challenge.example.com
nslookup -type=TXT _acme-challenge.example.com 8.8.8.8

# Check ACME server connectivity
Test-NetConnection -ComputerName "acme-v02.api.letsencrypt.org" -Port 443
```

**Common Causes and Solutions**:

#### DNS Propagation Issues

```powershell
# Check DNS propagation globally
# Use online tools: https://whatsmydns.net/
# Or test multiple DNS servers
$dnsServers = @("8.8.8.8", "1.1.1.1", "208.67.222.222")
foreach ($server in $dnsServers) {
    Write-Host "Testing $server"
    nslookup -type=TXT _acme-challenge.example.com $server
}
```

#### Rate Limiting

```powershell
# Check Let's Encrypt rate limits
# https://letsencrypt.org/docs/rate-limits/

# Use staging environment for testing
Set-PAServer -DirectoryUrl "https://acme-staging-v02.api.letsencrypt.org/directory"

# Check current rate limit status
Get-PAOrder | Group-Object Subject | Select-Object Count, Name
```

#### Certificate Store Issues

```powershell
# Check certificate store access
$store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
try {
    $store.Open("ReadWrite")
    Write-Host "Certificate store access OK" -ForegroundColor Green
} catch {
    Write-Host "Certificate store access failed: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    $store.Close()
}
```

### 5. Windows Certificate Store Installation Failure

**Error**: `"Cannot install certificate to store"`

**Diagnostic Steps**:

```powershell
# Verify administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Write-Host "Administrator privileges required" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator" -ForegroundColor Yellow
}

# Check certificate store permissions
$stores = @("LocalMachine", "CurrentUser")
foreach ($storeLocation in $stores) {
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", $storeLocation)
    try {
        $store.Open("ReadWrite")
        Write-Host "$storeLocation store: Access OK" -ForegroundColor Green
        $store.Close()
    } catch {
        Write-Host "$storeLocation store: Access failed - $($_.Exception.Message)" -ForegroundColor Red
    }
}
```

### 6. IIS Binding Configuration Issues

**Error**: `"Failed to configure IIS binding"`

**Diagnostic Steps**:

```powershell
# Check if IIS is installed
$iisFeature = Get-WindowsFeature -Name IIS-WebServerRole
if ($iisFeature.InstallState -ne "Installed") {
    Write-Host "IIS is not installed" -ForegroundColor Red
    Write-Host "Install IIS using: Enable-WindowsFeature -Name IIS-WebServerRole" -ForegroundColor Yellow
}

# Check IIS Management module
try {
    Import-Module WebAdministration -ErrorAction Stop
    Write-Host "IIS Management module loaded" -ForegroundColor Green
} catch {
    Write-Host "IIS Management module failed to load: $($_.Exception.Message)" -ForegroundColor Red
}

# Check website existence
$websites = Get-Website
if ($websites.Count -eq 0) {
    Write-Host "No websites found in IIS" -ForegroundColor Yellow
} else {
    Write-Host "Found $($websites.Count) websites:" -ForegroundColor Green
    $websites | Select-Object Name, State, PhysicalPath | Format-Table
}
```

**Solutions**:

```powershell
# Create test website
New-Website -Name "TestSite" -Port 80 -PhysicalPath "C:\inetpub\wwwroot"

# Check existing bindings
Get-WebBinding -Name "Default Web Site"

# Remove problematic bindings
Get-WebBinding -Name "Default Web Site" -Protocol https | Remove-WebBinding

# Create new HTTPS binding
New-WebBinding -Name "Default Web Site" -Protocol https -Port 443 -HostHeader "example.com"
```

### 7. Scheduled Task Not Running

**Error**: `"Automatic renewal task not executing"`

**Diagnostic Steps**:

```powershell
# Check task existence
$taskName = "AutoCert Certificate Renewal"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($task) {
    Write-Host "Task found: $($task.State)" -ForegroundColor Green
    Write-Host "Last Run: $($task.LastRunTime)" -ForegroundColor Gray
    Write-Host "Next Run: $($task.NextRunTime)" -ForegroundColor Gray
    Write-Host "Last Result: $($task.LastTaskResult)" -ForegroundColor Gray
} else {
    Write-Host "Task not found" -ForegroundColor Red
}

# Check task history
$events = Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-TaskScheduler/Operational'
    ID = 201
    StartTime = (Get-Date).AddDays(-7)
} | Where-Object { $_.Message -like "*$taskName*" }

if ($events) {
    Write-Host "Recent task executions:" -ForegroundColor Green
    $events | Select-Object TimeCreated, Id, LevelDisplayName, Message | Format-Table
} else {
    Write-Host "No recent task executions found" -ForegroundColor Yellow
}
```

**Solutions**:

```powershell
# Test task manually
Start-ScheduledTask -TaskName $taskName

# Check task definition
$taskInfo = Get-ScheduledTask -TaskName $taskName
$taskInfo.Actions | Format-List
$taskInfo.Triggers | Format-List
$taskInfo.Settings | Format-List

# Recreate task if needed
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
# Then run the AutoCert setup again
```

## 🔍 Advanced Diagnostics

### System Health Check

**Comprehensive System Diagnostics**:

```powershell
# Run built-in health check
.\Main.ps1 -ConfigTest

# Manual system checks
function Test-AutoCertSystem {
    Write-Host "AutoCert System Diagnostics" -ForegroundColor Cyan
    Write-Host "=" * 50
    
    # PowerShell version
    Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Green
    
    # Administrator check
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    Write-Host "Administrator: $isAdmin" -ForegroundColor $(if ($isAdmin) { "Green" } else { "Red" })
    
    # Module availability
    $module = Get-Module -ListAvailable -Name Posh-ACME
    Write-Host "Posh-ACME Module: $($module.Version)" -ForegroundColor Green
    
    # Network connectivity
    $connectivity = Test-NetConnection -ComputerName "acme-v02.api.letsencrypt.org" -Port 443 -InformationLevel Quiet
    Write-Host "ACME Server Connectivity: $connectivity" -ForegroundColor $(if ($connectivity) { "Green" } else { "Red" })
    
    # Certificate store access
    try {
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
        $store.Open("ReadWrite")
        $store.Close()
        Write-Host "Certificate Store Access: OK" -ForegroundColor Green
    } catch {
        Write-Host "Certificate Store Access: Failed" -ForegroundColor Red
    }
    
    # Disk space
    $drive = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='C:'"
    $freeSpaceGB = [math]::Round($drive.FreeSpace / 1GB, 2)
    Write-Host "Free Disk Space: $freeSpaceGB GB" -ForegroundColor $(if ($freeSpaceGB -gt 1) { "Green" } else { "Yellow" })
}

Test-AutoCertSystem
```

### Performance Diagnostics

**Monitor Certificate Operations**:

```powershell
# Monitor renewal performance
function Measure-CertificateRenewal {
    param([string]$Domain)
    
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    try {
        # Attempt renewal
        $result = New-PACertificate -MainDomain $Domain -Force
        $stopwatch.Stop()
        
        Write-Host "Renewal completed in $($stopwatch.Elapsed.TotalMinutes.ToString('F1')) minutes" -ForegroundColor Green
        return $result
    } catch {
        $stopwatch.Stop()
        Write-Host "Renewal failed after $($stopwatch.Elapsed.TotalMinutes.ToString('F1')) minutes" -ForegroundColor Red
        throw
    }
}

# System resource monitoring
function Monitor-SystemResources {
    $process = Get-Process -Name "powershell" | Where-Object { $_.MainWindowTitle -like "*AutoCert*" }
    
    if ($process) {
        Write-Host "CPU Usage: $($process.CPU)" -ForegroundColor Green
        Write-Host "Memory Usage: $([math]::Round($process.WorkingSet / 1MB, 2)) MB" -ForegroundColor Green
    }
    
    $memory = Get-Counter "\Memory\Available MBytes"
    Write-Host "Available Memory: $($memory.CounterSamples.CookedValue) MB" -ForegroundColor Green
}
```

### Network Connectivity Testing

**Test ACME Server Connectivity**:

```powershell
function Test-ACMEConnectivity {
    $acmeServers = @(
        "acme-v02.api.letsencrypt.org",
        "acme-staging-v02.api.letsencrypt.org"
    )
    
    foreach ($server in $acmeServers) {
        Write-Host "Testing $server..." -ForegroundColor Cyan
        
        try {
            # Test basic connectivity
            $tcpTest = Test-NetConnection -ComputerName $server -Port 443 -InformationLevel Detailed
            Write-Host "  TCP Connection: $($tcpTest.TcpTestSucceeded)" -ForegroundColor $(if ($tcpTest.TcpTestSucceeded) { "Green" } else { "Red" })
            
            # Test HTTPS response
            $response = Invoke-WebRequest -Uri "https://$server/directory" -UseBasicParsing -TimeoutSec 10
            Write-Host "  HTTPS Response: $($response.StatusCode)" -ForegroundColor Green
            
            # Test response time
            $responseTime = Measure-Command { Invoke-WebRequest -Uri "https://$server/directory" -UseBasicParsing -TimeoutSec 10 }
            Write-Host "  Response Time: $($responseTime.TotalMilliseconds.ToString('F0')) ms" -ForegroundColor Green
            
        } catch {
            Write-Host "  Connection Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
        
        Write-Host ""
    }
}

Test-ACMEConnectivity
```

### DNS Diagnostics

**Test DNS Resolution**:

```powershell
function Test-DNSResolution {
    param([string]$Domain)
    
    $dnsServers = @(
        @{ Name = "Google"; IP = "8.8.8.8" },
        @{ Name = "Cloudflare"; IP = "1.1.1.1" },
        @{ Name = "Quad9"; IP = "9.9.9.9" },
        @{ Name = "OpenDNS"; IP = "208.67.222.222" }
    )
    
    Write-Host "Testing DNS resolution for $Domain" -ForegroundColor Cyan
    
    foreach ($server in $dnsServers) {
        try {
            $result = Resolve-DnsName -Name $Domain -Server $server.IP -Type A -ErrorAction Stop
            Write-Host "  $($server.Name) ($($server.IP)): $($result.IPAddress -join ', ')" -ForegroundColor Green
        } catch {
            Write-Host "  $($server.Name) ($($server.IP)): Failed" -ForegroundColor Red
        }
    }
    
    # Test ACME challenge record
    $challengeRecord = "_acme-challenge.$Domain"
    Write-Host "`nTesting ACME challenge record: $challengeRecord" -ForegroundColor Cyan
    
    foreach ($server in $dnsServers) {
        try {
            $result = Resolve-DnsName -Name $challengeRecord -Server $server.IP -Type TXT -ErrorAction Stop
            Write-Host "  $($server.Name): $($result.Strings -join ', ')" -ForegroundColor Green
        } catch {
            Write-Host "  $($server.Name): No TXT record found" -ForegroundColor Yellow
        }
    }
}

# Example usage
Test-DNSResolution -Domain "example.com"
```

## 📊 Log Analysis

### PowerShell Log Analysis

**Analyze Renewal Success Rate**:

```powershell
function Get-RenewalStatistics {
    $logPath = "$env:LOCALAPPDATA\Posh-ACME\logs\autocert-renewal.log"
    
    if (Test-Path $logPath) {
        $logs = Get-Content $logPath
        
        $successes = ($logs | Select-String "renewal successful").Count
        $failures = ($logs | Select-String "renewal failed").Count
        $total = $successes + $failures
        
        if ($total -gt 0) {
            $successRate = ($successes / $total) * 100
            
            Write-Host "Renewal Statistics:" -ForegroundColor Cyan
            Write-Host "  Total Attempts: $total" -ForegroundColor White
            Write-Host "  Successful: $successes" -ForegroundColor Green
            Write-Host "  Failed: $failures" -ForegroundColor Red
            Write-Host "  Success Rate: $($successRate.ToString('F1'))%" -ForegroundColor $(if ($successRate -gt 80) { "Green" } else { "Yellow" })
        } else {
            Write-Host "No renewal attempts found in logs" -ForegroundColor Yellow
        }
        
        # Show recent errors
        $errors = $logs | Select-String "error|failed|exception" | Select-Object -Last 5
        if ($errors) {
            Write-Host "`nRecent Errors:" -ForegroundColor Red
            $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
    } else {
        Write-Host "Renewal log file not found: $logPath" -ForegroundColor Yellow
    }
}

Get-RenewalStatistics
```

### Windows Event Log Analysis

**Analyze Certificate Management Events**:

```powershell
function Get-CertificateEvents {
    try {
        $events = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            ProviderName = 'AutoCert Certificate Management'
            StartTime = (Get-Date).AddDays(-30)
        } -ErrorAction Stop
        
        Write-Host "Certificate Management Events (Last 30 Days):" -ForegroundColor Cyan
        
        $eventSummary = $events | Group-Object Id | Select-Object Count, Name, @{
            Name = 'EventType'
            Expression = { 
                switch ($_.Name) {
                    1001 { "Certificate Renewal Success" }
                    1002 { "Certificate Renewal Failure" }
                    1003 { "Certificate Installation Success" }
                    1004 { "Certificate Installation Failure" }
                    1005 { "System Health Check" }
                    default { "Unknown Event" }
                }
            }
        }
        
        $eventSummary | Format-Table -AutoSize
        
        # Show recent failures
        $failures = $events | Where-Object { $_.Id -in @(1002, 1004) } | Select-Object -First 5
        if ($failures) {
            Write-Host "`nRecent Failures:" -ForegroundColor Red
            $failures | ForEach-Object {
                Write-Host "  $($_.TimeCreated): $($_.Message)" -ForegroundColor Red
            }
        }
        
    } catch {
        Write-Host "No certificate management events found or event log not accessible" -ForegroundColor Yellow
    }
}

Get-CertificateEvents
```

## 🔧 Recovery Procedures

### Certificate Recovery

**Recover from Backup**:

```powershell
function Restore-CertificateFromBackup {
    param(
        [string]$BackupPath,
        [string]$Domain,
        [string]$Password = "BackupPassword123!"
    )
    
    $backupFile = Join-Path $BackupPath "$Domain.pfx"
    
    if (Test-Path $backupFile) {
        try {
            $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
            $cert = Import-PfxCertificate -FilePath $backupFile -CertStoreLocation Cert:\LocalMachine\My -Password $securePassword
            
            Write-Host "Certificate restored successfully" -ForegroundColor Green
            Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
            Write-Host "Subject: $($cert.Subject)" -ForegroundColor Gray
            Write-Host "Expires: $($cert.NotAfter)" -ForegroundColor Gray
            
            return $cert
        } catch {
            Write-Host "Failed to restore certificate: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Backup file not found: $backupFile" -ForegroundColor Red
    }
}
```

### System Recovery

**Reset AutoCert Configuration**:

```powershell
function Reset-AutoCertConfiguration {
    param([switch]$KeepCertificates)
    
    Write-Host "Resetting AutoCert configuration..." -ForegroundColor Yellow
    
    # Remove scheduled tasks
    $tasks = Get-ScheduledTask -TaskName "*AutoCert*" -ErrorAction SilentlyContinue
    foreach ($task in $tasks) {
        Write-Host "Removing scheduled task: $($task.TaskName)" -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $task.TaskName -Confirm:$false
    }
    
    # Clean configuration files
    $configFiles = @("config.json", "dns-config.json", "email-config.json")
    foreach ($file in $configFiles) {
        if (Test-Path $file) {
            Write-Host "Removing configuration file: $file" -ForegroundColor Yellow
            Remove-Item $file -Force
        }
    }
    
    # Clean credentials
    $credentials = cmdkey /list | Select-String "AutoCert"
    foreach ($cred in $credentials) {
        $credName = ($cred -split " ")[1]
        Write-Host "Removing credential: $credName" -ForegroundColor Yellow
        cmdkey /delete:$credName
    }
    
    # Optionally remove certificates
    if (-not $KeepCertificates) {
        $certs = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Issuer -like "*Let's Encrypt*" }
        foreach ($cert in $certs) {
            Write-Host "Removing certificate: $($cert.Subject)" -ForegroundColor Yellow
            Remove-Item $cert.PSPath -Force
        }
    }
    
    Write-Host "AutoCert configuration reset complete" -ForegroundColor Green
    Write-Host "Run .\Main.ps1 to reconfigure the system" -ForegroundColor Cyan
}
```

## 📞 Getting Additional Help

### Support Resources

1. **GitHub Issues**: Report bugs and request features
2. **Documentation**: Check all documentation files
3. **Community**: Join discussions on GitHub
4. **Logs**: Always include relevant log files when asking for help

### Information to Include When Seeking Help

```powershell
# Gather system information for support requests
function Get-AutoCertSupportInfo {
    $info = @{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        OperatingSystem = (Get-CimInstance Win32_OperatingSystem).Caption
        AutoCertVersion = "2.0.0"  # Update as needed
        PoshACMEVersion = (Get-Module Posh-ACME -ListAvailable).Version.ToString()
        IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        LastError = $Error[0].Exception.Message
        ConfigFiles = @()
    }
    
    # Check for configuration files
    $configFiles = @("config.json", "dns-config.json", "email-config.json")
    foreach ($file in $configFiles) {
        if (Test-Path $file) {
            $info.ConfigFiles += $file
        }
    }
    
    return $info | ConvertTo-Json -Depth 2
}

# Usage: Copy this output when requesting support
Get-AutoCertSupportInfo | Out-File "AutoCert-SupportInfo.json"
```

### Emergency Contact

For critical certificate issues:

1. **Immediate**: Use manual DNS mode for urgent certificates
2. **Recovery**: Restore from backups if available
3. **Escalation**: Contact your DNS provider support
4. **Documentation**: Document the issue for future prevention
