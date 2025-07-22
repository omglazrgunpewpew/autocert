# Scheduling/Install-ScheduledTasks.ps1
<#
    .SYNOPSIS
        PowerShell script to install AutoCert scheduled tasks for automated certificate management.

    .DESCRIPTION
        This script creates and configures Windows Task Scheduler tasks for:
        - Daily certificate renewal checks
        - Weekly health checks and maintenance
        - Emergency renewal for expiring certificates

        The script validates the environment, configures tasks with appropriate settings,
        and provides options for customization based on system requirements.

    .PARAMETER InstallPath
        The installation path where AutoCert is located. Defaults to C:\AutoCert

    .PARAMETER RenewalTime
        The daily time for renewal checks in 24-hour format (e.g., "02:00"). Defaults to 02:00

    .PARAMETER HealthCheckDay
        Day of the week for health checks (Sunday, Monday, etc.). Defaults to Sunday

    .PARAMETER EnableEmergencyTask
        Whether to enable the emergency renewal task. Defaults to false (disabled)

    .PARAMETER Force
        Force reinstallation of tasks even if they already exist

    .EXAMPLE
        .\Install-ScheduledTasks.ps1
        Install tasks with default settings

    .EXAMPLE
        .\Install-ScheduledTasks.ps1 -InstallPath "D:\AutoCert" -RenewalTime "03:30" -EnableEmergencyTask
        Install tasks with custom path, renewal time, and emergency task enabled
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$InstallPath = "C:\AutoCert",

    [Parameter()]
    [ValidatePattern('^([01]?[0-9]|2[0-3]):[0-5][0-9]$')]
    [string]$RenewalTime = "02:00",

    [Parameter()]
    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
    [string]$HealthCheckDay = "Sunday",

    [Parameter()]
    [switch]$EnableEmergencyTask,

    [Parameter()]
    [switch]$Force
)

# Requires elevation
#Requires -RunAsAdministrator

function Write-Log
{
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level)
    {
        'Info' { 'White' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        'Success' { 'Green' }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-AutoCertInstallation
{
    param([string]$Path)

    $requiredFiles = @(
        'Main.ps1',
        'Core\Logging.ps1',
        'Functions\Register-Certificate.ps1'
    )

    foreach ($file in $requiredFiles)
    {
        $fullPath = Join-Path $Path $file
        if (-not (Test-Path $fullPath))
        {
            return $false
        }
    }

    return $true
}

function Update-TaskXml
{
    param(
        [string]$XmlPath,
        [string]$InstallPath,
        [string]$RenewalTime,
        [string]$HealthCheckDay
    )

    [xml]$xml = Get-Content $XmlPath

    # Update working directory and command path
    $actions = $xml.Task.Actions.Exec
    if ($actions)
    {
        $actions.WorkingDirectory = $InstallPath
        $arguments = $actions.Arguments
        $arguments = $arguments -replace 'C:\\AutoCert\\Main\.ps1', "$InstallPath\Main.ps1"
        $actions.Arguments = $arguments
    }

    # Update start time for renewal tasks
    if ($XmlPath -like "*Daily-Renewal*" -and $RenewalTime)
    {
        $trigger = $xml.Task.Triggers.CalendarTrigger
        if ($trigger)
        {
            $startBoundary = $trigger.StartBoundary
            $date = [DateTime]::Parse($startBoundary).Date
            $newTime = [DateTime]::Parse($RenewalTime).TimeOfDay
            $newStartBoundary = $date.Add($newTime).ToString("yyyy-MM-ddTHH:mm:ss")
            $trigger.StartBoundary = $newStartBoundary
        }
    }

    # Update day for health check
    if ($XmlPath -like "*Weekly-HealthCheck*" -and $HealthCheckDay)
    {
        $trigger = $xml.Task.Triggers.CalendarTrigger
        if ($trigger -and $trigger.ScheduleByWeek)
        {
            # Clear existing days
            $daysOfWeek = $trigger.ScheduleByWeek.DaysOfWeek
            $daysOfWeek.RemoveAll()

            # Add new day
            $dayElement = $xml.CreateElement($HealthCheckDay)
            $daysOfWeek.AppendChild($dayElement) | Out-Null
        }
    }

    return $xml
}

function Install-AutoCertTask
{
    param(
        [string]$TaskName,
        [string]$XmlPath,
        [string]$InstallPath,
        [string]$RenewalTime,
        [string]$HealthCheckDay,
        [bool]$Force
    )

    try
    {
        # Check if task already exists
        $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

        if ($existingTask -and -not $Force)
        {
            Write-Log "Task '$TaskName' already exists. Use -Force to reinstall." -Level 'Warning'
            return $false
        }

        if ($existingTask -and $Force)
        {
            Write-Log "Removing existing task '$TaskName'..." -Level 'Info'
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }

        # Update XML with current settings
        $updatedXml = Update-TaskXml -XmlPath $XmlPath -InstallPath $InstallPath -RenewalTime $RenewalTime -HealthCheckDay $HealthCheckDay

        # Save updated XML to temp file
        $tempXmlPath = Join-Path $env:TEMP "$TaskName.xml"
        $updatedXml.Save($tempXmlPath)

        # Register the task
        Write-Log "Installing task '$TaskName'..." -Level 'Info'
        Register-ScheduledTask -TaskName $TaskName -Xml (Get-Content $tempXmlPath | Out-String) -Force | Out-Null

        # Clean up temp file
        Remove-Item $tempXmlPath -Force -ErrorAction SilentlyContinue

        # Verify installation
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task)
        {
            Write-Log "Successfully installed task '$TaskName'" -Level 'Success'
            return $true
        } else
        {
            Write-Log "Failed to verify installation of task '$TaskName'" -Level 'Error'
            return $false
        }

    } catch
    {
        Write-Log "Error installing task '$TaskName': $($_.Exception.Message)" -Level 'Error'
        return $false
    }
}

# Main script execution
Write-Log "Starting AutoCert Scheduled Tasks Installation" -Level 'Info'
Write-Log "Installation Path: $InstallPath" -Level 'Info'
Write-Log "Renewal Time: $RenewalTime" -Level 'Info'
Write-Log "Health Check Day: $HealthCheckDay" -Level 'Info'

# Validate AutoCert installation
if (-not (Test-AutoCertInstallation -Path $InstallPath))
{
    Write-Log "AutoCert installation not found or incomplete at: $InstallPath" -Level 'Error'
    Write-Log "Please ensure AutoCert is properly installed before creating scheduled tasks." -Level 'Error'
    exit 1
}

Write-Log "AutoCert installation validated successfully" -Level 'Success'

# Get script directory for XML templates
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$xmlTemplates = @{
    'AutoCert-Daily-Renewal'      = Join-Path $scriptDir 'AutoCert-Daily-Renewal.xml'
    'AutoCert-Weekly-HealthCheck' = Join-Path $scriptDir 'AutoCert-Weekly-HealthCheck.xml'
    'AutoCert-Emergency-Renewal'  = Join-Path $scriptDir 'AutoCert-Emergency-Renewal.xml'
}

# Validate XML templates exist
foreach ($template in $xmlTemplates.GetEnumerator())
{
    if (-not (Test-Path $template.Value))
    {
        Write-Log "Template not found: $($template.Value)" -Level 'Error'
        exit 1
    }
}

# Install tasks
$results = @{}
$totalTasks = if ($EnableEmergencyTask) { 3 } else { 2 }
$completedTasks = 0

# Install daily renewal task
$taskName = 'AutoCert-Daily-Renewal'
$results[$taskName] = Install-AutoCertTask -TaskName $taskName -XmlPath $xmlTemplates[$taskName] -InstallPath $InstallPath -RenewalTime $RenewalTime -HealthCheckDay $HealthCheckDay -Force $Force
if ($results[$taskName]) { $completedTasks++ }

# Install weekly health check task
$taskName = 'AutoCert-Weekly-HealthCheck'
$results[$taskName] = Install-AutoCertTask -TaskName $taskName -XmlPath $xmlTemplates[$taskName] -InstallPath $InstallPath -RenewalTime $RenewalTime -HealthCheckDay $HealthCheckDay -Force $Force
if ($results[$taskName]) { $completedTasks++ }

# Install emergency renewal task if requested
if ($EnableEmergencyTask)
{
    $taskName = 'AutoCert-Emergency-Renewal'
    $results[$taskName] = Install-AutoCertTask -TaskName $taskName -XmlPath $xmlTemplates[$taskName] -InstallPath $InstallPath -RenewalTime $RenewalTime -HealthCheckDay $HealthCheckDay -Force $Force
    if ($results[$taskName]) { $completedTasks++ }

    # Enable the emergency task if installation was successful
    if ($results[$taskName])
    {
        try
        {
            $task = Get-ScheduledTask -TaskName $taskName
            $task.Settings.Enabled = $true
            Set-ScheduledTask -InputObject $task | Out-Null
            Write-Log "Emergency renewal task enabled" -Level 'Success'
        } catch
        {
            Write-Log "Warning: Could not enable emergency renewal task: $($_.Exception.Message)" -Level 'Warning'
        }
    }
}

# Summary
Write-Log "Installation Summary:" -Level 'Info'
Write-Log "Completed: $completedTasks/$totalTasks tasks" -Level 'Info'

foreach ($result in $results.GetEnumerator())
{
    $status = if ($result.Value) { "SUCCESS" } else { "FAILED" }
    $level = if ($result.Value) { "Success" } else { "Error" }
    Write-Log "  $($result.Key): $status" -Level $level
}

if ($completedTasks -eq $totalTasks)
{
    Write-Log "All scheduled tasks installed successfully!" -Level 'Success'
    Write-Log "AutoCert will now automatically check for certificate renewals daily at $RenewalTime" -Level 'Info'
    Write-Log "Weekly health checks will run on $HealthCheckDay at 03:00" -Level 'Info'

    if ($EnableEmergencyTask)
    {
        Write-Log "Emergency renewal task is enabled and will run every 4 hours when certificates are near expiration" -Level 'Info'
    }

    Write-Log "You can manage these tasks using Task Scheduler or the schtasks command" -Level 'Info'
    exit 0
} else
{
    Write-Log "Some tasks failed to install. Please check the errors above and try again." -Level 'Error'
    exit 1
}
