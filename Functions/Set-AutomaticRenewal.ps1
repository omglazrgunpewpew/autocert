<#
    .SYNOPSIS
        Configures a Scheduled Task to automatically renew all Posh-ACME certificates.
#>

function Set-AutomaticRenewal {
    $taskName   = "Posh-ACME Certificate Renewal"
    $scriptPath = $MyInvocation.MyCommand.Path
    # We want to call Main.ps1 with -RenewAll parameter.
    # Adjust the path if your scheduling path differs.
    $mainScript = Join-Path (Split-Path $scriptPath -Parent) "..\Main.ps1"
    $action     = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -File `"$mainScript`" -RenewAll"
    $trigger    = New-ScheduledTaskTrigger -Daily -At 2am
    $principal  = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings   = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $task       = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

    try {
        Register-ScheduledTask -TaskName $taskName -InputObject $task -Force
        $registered = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($registered) {
            Write-Host "`nAutomatic renewal configured via scheduled task '$taskName'." -ForegroundColor Green
            Write-Log "Automatic renewal configured via scheduled task '$taskName'."
        }
        else {
            throw "Scheduled task was not created"
        }
    }
    catch {
        Write-Host "Failed to configure automatic renewal: $($_)" -ForegroundColor Red
        Write-Log "Failed to configure automatic renewal: $($_)" -Level 'Error'
    }
}

