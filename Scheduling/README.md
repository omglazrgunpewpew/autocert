# Scheduling/README.md

# AutoCert Scheduling Templates

This directory contains Windows Task Scheduler XML templates and installation scripts for automated certificate management.

## Overview

The AutoCert scheduling system provides three types of automated tasks:

1. **Daily Renewal Check** - Runs daily to check for certificates that need renewal
2. **Weekly Health Check** - Performs comprehensive system health checks and maintenance
3. **Emergency Renewal** - High-frequency checks when certificates are near expiration (optional)

## Files

### XML Templates

- `AutoCert-Daily-Renewal.xml` - Daily certificate renewal task template
- `AutoCert-Weekly-HealthCheck.xml` - Weekly health check and maintenance task template  
- `AutoCert-Emergency-Renewal.xml` - Emergency renewal task for critical situations

### Installation Script

- `Install-ScheduledTasks.ps1` - PowerShell script to create and configure the scheduled tasks

## Quick Start

### Basic Installation

Run as Administrator:

```powershell
# Install with default settings
.\Install-ScheduledTasks.ps1

# Install with custom settings
.\Install-ScheduledTasks.ps1 -InstallPath "D:\AutoCert" -RenewalTime "03:30" -HealthCheckDay "Saturday"

# Install with emergency task enabled
.\Install-ScheduledTasks.ps1 -EnableEmergencyTask
```

### Manual Installation

If you prefer to install tasks manually:

1. Open Task Scheduler (`taskschd.msc`)
2. Right-click "Task Scheduler Library" → "Import Task..."
3. Select the XML file for the task you want to install
4. Modify the paths and settings as needed
5. Save the task

## Task Details

### Daily Renewal Task (`AutoCert-Daily-Renewal.xml`)

**Purpose**: Checks for certificates that need renewal and renews them automatically

**Schedule**: Daily at 02:00 (customizable)

**Key Features**:
- Runs with highest privileges (SYSTEM account)
- 2-hour execution time limit
- Automatic restart on failure (3 attempts, 10-minute intervals)
- Only runs if network is available
- Ignores multiple instances

**Command**: 
```
powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "C:\AutoCert\Main.ps1" -RenewAll -NonInteractive -LogLevel Info
```

### Weekly Health Check Task (`AutoCert-Weekly-HealthCheck.xml`)

**Purpose**: Performs comprehensive health checks and system maintenance

**Schedule**: Weekly on Sunday at 03:00 (customizable)

**Key Features**:
- 1-hour execution time limit  
- Configuration validation
- System health monitoring
- Cleanup of expired certificates
- Performance analysis

**Command**:
```
powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "C:\AutoCert\Main.ps1" -ConfigTest -LogLevel Info
```

### Emergency Renewal Task (`AutoCert-Emergency-Renewal.xml`)

**Purpose**: High-frequency renewal attempts for certificates near expiration

**Schedule**: Every 4 hours (disabled by default)

**Key Features**:
- Higher priority execution
- Forced renewal attempts
- Wake computer to run
- 5 restart attempts on failure
- Debug-level logging

**Command**:
```
powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "C:\AutoCert\Main.ps1" -RenewAll -Force -NonInteractive -LogLevel Debug
```

## Customization

### Modifying Schedule Times

Edit the `StartBoundary` element in the XML:

```xml
<StartBoundary>2025-07-17T02:00:00</StartBoundary>
```

### Changing Installation Path

Update the `WorkingDirectory` and `Arguments` in the XML:

```xml
<WorkingDirectory>D:\AutoCert</WorkingDirectory>
<Arguments>-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File "D:\AutoCert\Main.ps1" -RenewAll -NonInteractive</Arguments>
```

### Adjusting Execution Limits

Modify the `ExecutionTimeLimit` setting:

```xml
<ExecutionTimeLimit>PT2H</ExecutionTimeLimit>  <!-- 2 hours -->
<ExecutionTimeLimit>PT30M</ExecutionTimeLimit>  <!-- 30 minutes -->
```

### Retry Configuration

Adjust the restart policy:

```xml
<RestartPolicy>
  <Interval>PT10M</Interval>  <!-- Wait 10 minutes between retries -->
  <Count>3</Count>            <!-- Maximum 3 retries -->
</RestartPolicy>
```

## Security Considerations

### Execution Context

All tasks run as SYSTEM with highest privileges to ensure:
- Access to certificate stores
- Network connectivity
- File system permissions
- Service management capabilities

### Network Requirements

Tasks are configured to:
- Only run when network is available
- Wait for network connectivity if needed
- Handle network timeouts gracefully

### Logging and Monitoring

All task execution is logged to:
- Windows Event Log (Application log, source: "Certificate Management")
- AutoCert log files (`$env:LOCALAPPDATA\Posh-ACME\certificate_script.log`)
- Task Scheduler History

## Troubleshooting

### Common Issues

1. **Task Not Running**
   - Verify AutoCert installation path
   - Check task is enabled in Task Scheduler
   - Ensure network connectivity

2. **Permission Errors**
   - Confirm script execution policy allows unsigned scripts
   - Verify SYSTEM account has required permissions
   - Check certificate store access rights

3. **Network Timeouts**
   - Increase execution time limit
   - Check DNS resolution
   - Verify firewall settings

### Verification Commands

```powershell
# Check task status
Get-ScheduledTask -TaskName "AutoCert-*"

# View task history
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; ID=200,201}

# Test manual execution
schtasks /run /tn "AutoCert-Daily-Renewal"

# View task details
Export-ScheduledTask -TaskName "AutoCert-Daily-Renewal"
```

### Log Analysis

Monitor these log sources:
- Task Scheduler operational log
- AutoCert application logs
- Windows Event Log (Application)
- PowerShell transcripts (if enabled)

## Advanced Configuration

### Environment Variables

Set these environment variables for customization:

```powershell
# Custom log location
$env:AUTOCERT_LOG_PATH = "D:\Logs\AutoCert"

# Testing mode
$env:AUTOCERT_TESTING_MODE = $true

# Skip module updates
$env:POSHACME_SKIP_UPGRADE_CHECK = $true
```

### Multiple Environments

For staging/production separation:

1. Create separate task names with environment suffix
2. Use different installation paths
3. Configure separate log locations
4. Adjust scheduling to avoid conflicts

### Load Balancing

For multiple servers:

1. Use randomization in renewal timing
2. Stagger health check schedules
3. Implement jitter in retry logic
4. Monitor resource usage

## Integration

### Monitoring Systems

Tasks can be integrated with:
- SCOM (System Center Operations Manager)
- Nagios/Icinga
- Zabbix
- Custom PowerShell monitoring

### Notification Systems

Configure email alerts for:
- Renewal failures
- Health check issues
- Certificate expiration warnings
- System errors

### Backup Integration

Coordinate with backup systems:
- Schedule before backup windows
- Export certificates after renewal
- Maintain backup retention policies
- Verify backup integrity

## Best Practices

1. **Testing**: Always test in non-production environment first
2. **Monitoring**: Set up alerting for task failures
3. **Documentation**: Maintain task configuration documentation
4. **Updates**: Review and update schedules regularly
5. **Security**: Regular security audits of task configurations
6. **Performance**: Monitor resource usage and adjust as needed

## Support

For issues with scheduled tasks:

1. Check AutoCert logs for detailed error information
2. Review Task Scheduler event logs
3. Verify system prerequisites are met
4. Test manual execution before scheduling
5. Consult troubleshooting documentation
