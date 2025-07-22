# Functions/CertificateInstallation/Show-InstallationOptionsMenu.ps1
<#
    .SYNOPSIS
        Shows advanced installation options menu
    .DESCRIPTION
        Provides advanced installation options including custom certificate stores,
        custom friendly names, backup creation, IIS binding, and scheduled tasks.
    .PARAMETER PACertificate
        The Posh-ACME certificate object to install
    .PARAMETER Settings
        Script settings object
    .PARAMETER Force
        Forces operations even if they might not be necessary
    .OUTPUTS
        Returns $true if installation completed, $false otherwise
    .EXAMPLE
        Show-InstallationOptionsMenu -PACertificate $cert -Settings $settings
#>
function Show-InstallationOptionsMenu
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate,

        [Parameter(Mandatory = $true)]
        [object]$Settings,

        [Parameter()]
        [switch]$Force
    )

    Write-Host -Object "`nInstallation Options:" -ForegroundColor Cyan
    Write-Host -Object "1) Install to custom certificate store"
    Write-Host -Object "2) Install with custom friendly name"
    Write-Host -Object "3) Install with backup creation"
    Write-Host -Object "4) Configure IIS site binding"
    Write-Host -Object "5) Schedule automatic reinstallation"
    Write-Host -Object "0) Back to main menu"

    $installChoice = Get-ValidatedInput -Prompt "`nSelect installation option (0-5)" -ValidOptions (0..5)

    switch ($installChoice)
    {
        0
        {
            return $false
        }
        1
        {
            # Custom certificate store
            return Install-CertificateToCustomStore -PACertificate $PACertificate
        }
        2
        {
            # Custom friendly name
            return Install-CertificateWithFriendlyName -PACertificate $PACertificate
        }
        3
        {
            # Backup and install
            return Install-CertificateWithBackup -PACertificate $PACertificate
        }
        4
        {
            # IIS site binding
            return Set-IISSiteBinding -PACertificate $PACertificate
        }
        5
        {
            # Schedule automatic reinstallation
            return Set-AutomaticReinstallation -PACertificate $PACertificate
        }
    }

    return $false
}

function Install-CertificateToCustomStore
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    Write-Warning -Message "`nCustom Certificate Store Installation:"
    Write-Host -Object "1) LocalMachine\My (Personal)"
    Write-Host -Object "2) LocalMachine\WebHosting"
    Write-Host -Object "3) CurrentUser\My (Personal)"
    Write-Host -Object "4) LocalMachine\TrustedPeople"
    Write-Host -Object "5) Custom store name"

    $storeChoice = Get-ValidatedInput -Prompt "`nSelect store (1-5)" -ValidOptions (1..5)

    $storeLocation = "LocalMachine"
    $storeName = "My"

    switch ($storeChoice)
    {
        1 { $storeLocation = "LocalMachine"; $storeName = "My" }
        2 { $storeLocation = "LocalMachine"; $storeName = "WebHosting" }
        3 { $storeLocation = "CurrentUser"; $storeName = "My" }
        4 { $storeLocation = "LocalMachine"; $storeName = "TrustedPeople" }
        5
        {
            $customStore = Read-Host "Enter custom store name"
            if ($customStore) { $storeName = $customStore }
        }
    }

    try
    {
        if ($PSCmdlet.ShouldProcess("$($PACertificate.MainDomain)", "Install to $storeLocation\$storeName"))
        {
            Install-PACertificate -PACertificate $PACertificate -StoreLocation $storeLocation -StoreName $storeName -Verbose
            Write-Information -MessageData "OK Certificate installed to $storeLocation\$storeName" -InformationAction Continue
            Write-Log "Certificate installed to custom store $storeLocation\$storeName"
            return $true
        }
    } catch
    {
        Write-Error -Message "Failed to install to custom store: $_"
        Read-Host "`nPress Enter to continue"
        return $false
    }
}

function Install-CertificateWithFriendlyName
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    $friendlyName = Read-Host "`nEnter friendly name for the certificate (or 0 to cancel)"
    if ($friendlyName -eq '0')
    {
        return $false
    }

    if ($friendlyName)
    {
        try
        {
            # Install normally first
            if ($PSCmdlet.ShouldProcess("$($PACertificate.MainDomain)", "Install with friendly name"))
            {
                Install-PACertificate -PACertificate $PACertificate -StoreLocation LocalMachine -Verbose

                # Update friendly name
                $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                $store.Open("ReadWrite")
                $cert = $store.Certificates | Where-Object { $_.Thumbprint -eq $PACertificate.Certificate.Thumbprint }

                if ($cert)
                {
                    $cert.FriendlyName = $friendlyName
                    Write-Information -MessageData "OK Certificate installed with friendly name: $friendlyName" -InformationAction Continue
                    Write-Log "Certificate installed with friendly name: $friendlyName"
                    $store.Close()
                    return $true
                } else
                {
                    throw "Certificate not found after installation"
                }
            }
        } catch
        {
            Write-Error -Message "Failed to set friendly name: $_"
            Read-Host "`nPress Enter to continue"
            return $false
        }
    }

    return $false
}

function Install-CertificateWithBackup
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    Write-Warning -Message "`nCreating backup before installation..."
    $backupDir = Read-Host "Enter backup directory (default: Desktop\CertBackup, or 0 to cancel)"
    if ($backupDir -eq '0')
    {
        return $false
    }
    if (-not $backupDir)
    {
        $backupDir = Join-Path ([Environment]::GetFolderPath("Desktop")) "CertBackup"
    }

    if (-not (Test-Path $backupDir))
    {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    try
    {
        # Create backup
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupPath = Join-Path $backupDir "backup_${timestamp}.pfx"
        $backupPassword = Read-Host "Enter backup password" -AsSecureString

        if ($PSCmdlet.ShouldProcess("$backupPath", "Create backup"))
        {
            Export-PACertificate -MainDomain $PACertificate.MainDomain -Type PFX -Path $backupPath -Password $backupPassword
            Write-Information -MessageData "OK Backup created: $backupPath" -InformationAction Continue
        }

        # Install certificate
        if ($PSCmdlet.ShouldProcess("$($PACertificate.MainDomain)", "Install certificate"))
        {
            Install-PACertificate -PACertificate $PACertificate -StoreLocation LocalMachine -Verbose
            Write-Information -MessageData "OK Certificate installed" -InformationAction Continue
            Write-Log "Certificate installed with backup created"
            return $true
        }
    } catch
    {
        Write-Error -Message "Backup and install failed: $_"
        Read-Host "`nPress Enter to continue"
        return $false
    }

    return $false
}

function Set-IISSiteBinding
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    if (-not (Get-Module -ListAvailable -Name WebAdministration))
    {
        Write-Warning -Message "IIS WebAdministration module not available."
        Read-Host "`nPress Enter to continue"
        return $false
    }

    Import-Module WebAdministration
    $sites = Get-Website

    if (-not $sites)
    {
        Write-Warning -Message "No IIS sites found."
        Read-Host "`nPress Enter to continue"
        return $false
    }

    Write-Warning -Message "`nAvailable IIS Sites:"
    for ($i = 0; $i -lt $sites.Count; $i++)
    {
        Write-Host -Object "$($i + 1)) $($sites[$i].Name) - $($sites[$i].State)"
    }

    $siteChoice = Get-ValidatedInput -Prompt "`nSelect site (1-$($sites.Count))" -ValidOptions (1..$sites.Count)
    $selectedSite = $sites[$siteChoice - 1]

    try
    {
        # Install certificate first
        if ($PSCmdlet.ShouldProcess("$($PACertificate.MainDomain)", "Install and bind to IIS"))
        {
            Install-PACertificate -PACertificate $PACertificate -StoreLocation LocalMachine -Verbose

            # Remove existing HTTPS binding if it exists
            $existingBinding = Get-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -ErrorAction SilentlyContinue
            if ($existingBinding)
            {
                Remove-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -Confirm:$false
                Write-Warning -Message "Removed existing HTTPS binding"
            }

            # Create new HTTPS binding
            New-WebBinding -Name $selectedSite.Name -Protocol https -Port 443 -SslFlags 1

            # Bind certificate
            $binding = Get-WebBinding -Name $selectedSite.Name -Protocol https -Port 443
            $binding.AddSslCertificate($PACertificate.Certificate.Thumbprint, "my")

            Write-Information -MessageData "OK Certificate bound to IIS site: $($selectedSite.Name)" -InformationAction Continue
            Write-Log "Certificate bound to IIS site: $($selectedSite.Name)"
            return $true
        }
    } catch
    {
        Write-Error -Message "Failed to configure IIS binding: $_"
        Read-Host "`nPress Enter to continue"
        return $false
    }

    return $false
}

function Set-AutomaticReinstallation
{
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    Write-Warning -Message "`nScheduling automatic certificate reinstallation..."
    $taskName = "Certificate Auto-Reinstall - $($PACertificate.MainDomain)"

    $scriptContent = @"
# Auto-reinstall script for $($PACertificate.MainDomain)
Import-Module Posh-ACME -Force
try {
    `$cert = Get-PACertificate -MainDomain "$($PACertificate.MainDomain)"
    if (`$cert) {
        Install-PACertificate -PACertificate `$cert -StoreLocation LocalMachine
        Write-EventLog -LogName Application -Source "Certificate Management" -EventId 1001 -Message "Certificate auto-reinstalled for $($PACertificate.MainDomain)"
    }
} catch {
    Write-EventLog -LogName Application -Source "Certificate Management" -EventId 1002 -EntryType Error -Message "Certificate auto-reinstall failed for $($PACertificate.MainDomain): `$_"
}
"@

    $scriptPath = Join-Path $env:TEMP "reinstall_$($PACertificate.MainDomain.Replace('*','wildcard').Replace('.','_')).ps1"

    try
    {
        if ($PSCmdlet.ShouldProcess("$taskName", "Create scheduled task"))
        {
            $scriptContent | Set-Content -Path $scriptPath

            $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -File `"$scriptPath`""
            $trigger = New-ScheduledTaskTrigger -Weekly -At 3am -DaysOfWeek Sunday
            $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
            $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force

            Write-Information -MessageData "OK Automatic reinstallation scheduled for $($PACertificate.MainDomain)" -InformationAction Continue
            Write-Host -Object "  Task: $taskName" -ForegroundColor Cyan
            Write-Host -Object "  Schedule: Weekly on Sundays at 3:00 AM" -ForegroundColor Cyan
            Write-Log "Automatic reinstallation scheduled for $($PACertificate.MainDomain)"
            return $true
        }
    } catch
    {
        Write-Error -Message "Failed to create scheduled task: $_"
        Read-Host "`nPress Enter to continue"
        return $false
    }

    return $false
}
