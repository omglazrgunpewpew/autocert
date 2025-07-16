<#
    .SYNOPSIS
        Provides functions for securely managing credentials using the SecretManagement module.
    .DESCRIPTION
        This script offers a secure way to store, retrieve, and remove credentials (like API keys)
        for DNS providers, leveraging PowerShell's built-in SecretManagement and SecretStore modules.
        It includes checks to ensure the necessary modules are installed and configured.
    .NOTES
        Requires PowerShell 7+ and the Microsoft.PowerShell.SecretManagement and
        Microsoft.PowerShell.SecretStore modules. The script will guide the user
        through installation if they are missing.
#>
function Test-SecretManagementPrerequisites {
    [CmdletBinding()]
    param()
    Write-Host "Checking for SecretManagement prerequisites..." -ForegroundColor Cyan
    $missingModules = @()
    if (-not (Get-Module -Name Microsoft.PowerShell.SecretManagement -ListAvailable)) {
        $missingModules += "Microsoft.PowerShell.SecretManagement"
    }
    if (-not (Get-Module -Name Microsoft.PowerShell.SecretStore -ListAvailable)) {
        $missingModules += "Microsoft.PowerShell.SecretStore"
    }
    if ($missingModules.Count -gt 0) {
        Write-Warning "The following required modules are not installed: $($missingModules -join ', ')"
        $choice = Read-Host "Do you want to install them now? (y/n)"
        if ($choice -eq 'y') {
            try {
                Install-Module -Name $missingModules -Repository PSGallery -Force -Scope CurrentUser
                Write-Host "Modules installed." -ForegroundColor Green
            } catch {
                Write-Error "Failed to install modules: $($_.Exception.Message)"
                return $false
            }
        } else {
            return $false
        }
    }
    # Check if a vault is registered
    if (-not (Get-SecretVault -ErrorAction SilentlyContinue)) {
        Write-Warning "No secret vault found."
        $choice = Read-Host "Do you want to register the default SecretStore vault now? (y/n)"
        if ($choice -eq 'y') {
            try {
                Register-SecretVault -Name 'PoshACME_SecretStore' -ModuleName 'Microsoft.PowerShell.SecretStore' -DefaultVault
                Write-Host "Default vault registered." -ForegroundColor Green
            } catch {
                Write-Error "Failed to register vault: $($_.Exception.Message)"
                return $false
            }
        } else {
            return $false
        }
    }
    # Check if vault is locked
    try {
        Get-SecretInfo -Vault (Get-SecretVault).Name -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -like '*The vault is locked*') {
            Write-Warning "The secret vault is locked. Please unlock it to continue."
            try {
                Unlock-SecretStore -Vault (Get-SecretVault).Name
                Write-Host "Vault unlocked." -ForegroundColor Green
            } catch {
                Write-Error "Failed to unlock the vault: $($_.Exception.Message)"
                return $false
            }
        }
    }
    return $true
}
function Show-CredentialManagementMenu {
    [CmdletBinding()]
    param()
    if (-not (Test-SecretManagementPrerequisites)) {
        Write-Warning "Credential management prerequisites are not met. Returning to main menu."
        Read-Host "Press Enter to continue"
        return
    }
    while ($true) {
        Clear-Host
        Write-Host "`n" + "="*60 -ForegroundColor Cyan
        Write-Host "    SECURE CREDENTIAL MANAGEMENT" -ForegroundColor Cyan
        Write-Host "="*60 -ForegroundColor Cyan
        Write-Host "1. View stored credentials"
        Write-Host "2. Add or update a credential"
        Write-Host "3. Remove a credential"
        Write-Host "0. Return to main menu"
        Write-Host "`n" + "="*60 -ForegroundColor Cyan
        $choice = Read-Host "Enter your choice"
        switch ($choice) {
            '1' { Get-StoredCredentials }
            '2' { Set-StoredCredential }
            '3' { Remove-StoredCredential }
            '0' { return }
            default { Write-Warning "Invalid option. Please try again." }
        }
        Read-Host "Press Enter to continue"
    }
}
# Wrapper functions for compatibility with main script
function Get-StoredCredential {
    [CmdletBinding()]
    param(
        [string]$Target
    )
    if ($Target) {
        # Get specific credential by name/target
        try {
            $secret = Get-Secret -Name $Target -ErrorAction SilentlyContinue
            if ($secret) {
                return @{
                    Target = $Target
                    UserName = "StoredCredential"
                    Password = $secret
                }
            }
            return $null
        } catch {
            return $null
        }
    } else {
        # Get all credentials
        try {
            $secrets = Get-SecretInfo -ErrorAction SilentlyContinue
            if ($secrets) {
                return $secrets | ForEach-Object {
                    @{
                        Target = $_.Name
                        UserName = "StoredCredential"
                    }
                }
            }
            return @()
        } catch {
            return @()
        }
    }
}
function Remove-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )
    try {
        Remove-Secret -Name $Target -ErrorAction Stop
        Write-Host "Credential '$Target' removed." -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to remove credential '$Target': $($_.Exception.Message)"
        return $false
    }
}
function Set-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credential
    )
    try {
        # Store password as a secret
        Set-Secret -Name $Target -Secret $Credential.Password -ErrorAction Stop
        Write-Host "Credential '$Target' stored." -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to store credential '$Target': $($_.Exception.Message)"
        return $false
    }
}