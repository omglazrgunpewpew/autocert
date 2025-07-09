# Credential Management System
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 8, 2025

<#
.SYNOPSIS
    Credential management for AutoCert
.DESCRIPTION
    Provides functionality to manage DNS provider credentials
    for automated certificate validation
.NOTES
    Securely stores credentials for certificate management
#>

function Show-CredentialManagementMenu {
    [CmdletBinding()]
    param()
    
    Clear-Host
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    CREDENTIAL MANAGEMENT" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan

    # List stored credentials
    $credentials = Get-StoredCredential
    if ($credentials.Count -eq 0) {
        Write-Host "No credentials found. You can add new ones." -ForegroundColor Yellow
    } else {
        Write-Host "Stored Credentials:" -ForegroundColor Green
        foreach ($cred in $credentials) {
            Write-Host "  • $($cred.Name) ($($cred.Type))" -ForegroundColor White
        }
    }

    Write-Host "`nAvailable Actions:" -ForegroundColor White
    Write-Host "1. Add new credential" -ForegroundColor Green
    Write-Host "2. Remove credential" -ForegroundColor Red
    Write-Host "3. Test credential" -ForegroundColor Cyan
    Write-Host "0. Return to Main Menu" -ForegroundColor DarkRed
    Write-Host "`n" + "="*60 -ForegroundColor Cyan

    $choice = Read-Host "Enter your choice"

    switch ($choice) {
        '1' {
            # Add new credential
            Invoke-AddCredentialMenu
        }
        '2' {
            # Remove credential
            Invoke-RemoveCredentialMenu
        }
        '3' {
            # Test credential
            Invoke-TestCredentialMenu
        }
        '0' { return }
        default {
            Write-Warning "Invalid option. Please try again."
            Read-Host "Press Enter to continue"
            Show-CredentialManagementMenu
        }
    }
}

function Invoke-AddCredentialMenu {
    [CmdletBinding()]
    param()
    
    Clear-Host
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    ADD NEW CREDENTIAL" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    # Get credential type
    Write-Host "`nAvailable Credential Types:" -ForegroundColor Green
    Write-Host "1. API Key (for services like Cloudflare, DigitalOcean, etc.)" -ForegroundColor White
    Write-Host "2. Username/Password (for services like Namecheap, GoDaddy, etc.)" -ForegroundColor White
    Write-Host "3. OAuth Token (for services like Google Cloud, AWS, etc.)" -ForegroundColor White
    Write-Host "0. Cancel" -ForegroundColor Red
    
    $typeChoice = Read-Host "`nSelect credential type"
    if ($typeChoice -eq "0") {
        return
    }
    
    $credentialType = switch ($typeChoice) {
        '1' { "API Key" }
        '2' { "Username/Password" }
        '3' { "OAuth Token" }
        default { 
            Write-Warning "Invalid choice. Returning to credential menu."
            Read-Host "Press Enter to continue"
            return
        }
    }
    
    # Get credential name/identifier
    $credName = Read-Host "`nEnter a name for this credential (e.g. 'Cloudflare-Primary')"
    if ([string]::IsNullOrWhiteSpace($credName)) {
        Write-Warning "Credential name cannot be empty."
        Read-Host "Press Enter to continue"
        return
    }
    
    # Get service provider
    $provider = Read-Host "Enter the service provider (e.g. 'Cloudflare', 'Route53', etc.)"
    
    try {
        switch ($credentialType) {
            "API Key" {
                $apiKey = Read-Host "Enter API Key" -AsSecureString
                $apiSecret = Read-Host "Enter API Secret (if applicable, otherwise press Enter)" -AsSecureString
                
                # Create the credential object
                Add-DNSProviderCredential -Name $credName -Provider $provider -Type "APIKey" -Key $apiKey -Secret $apiSecret
            }
            "Username/Password" {
                $username = Read-Host "Enter Username"
                $password = Read-Host "Enter Password" -AsSecureString
                
                # Create the credential object
                Add-DNSProviderCredential -Name $credName -Provider $provider -Type "UsernamePassword" -Username $username -Password $password
            }
            "OAuth Token" {
                $token = Read-Host "Enter OAuth Token" -AsSecureString
                
                # Create the credential object
                Add-DNSProviderCredential -Name $credName -Provider $provider -Type "OAuth" -Token $token
            }
        }
        
        Write-Host "`nCredential '$credName' added." -ForegroundColor Green
    } catch {
        Write-Error "Failed to add credential: $($_.Exception.Message)"
    }
    
    Read-Host "Press Enter to continue"
}

function Invoke-RemoveCredentialMenu {
    [CmdletBinding()]
    param()
    
    Clear-Host
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    REMOVE CREDENTIAL" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    # List stored credentials
    $credentials = Get-StoredCredential
    if ($credentials.Count -eq 0) {
        Write-Host "No credentials found." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        return
    }
    
    Write-Host "Select credential to remove:" -ForegroundColor Green
    for ($i = 0; $i -lt $credentials.Count; $i++) {
        Write-Host "  $($i + 1). $($credentials[$i].Name) ($($credentials[$i].Type))" -ForegroundColor White
    }
    Write-Host "  0. Cancel" -ForegroundColor Red
    
    $credChoice = Read-Host "`nEnter your choice"
    if ($credChoice -eq "0") {
        return
    }
    
    $credIndex = [int]$credChoice - 1
    if ($credIndex -ge 0 -and $credIndex -lt $credentials.Count) {
        $selectedCred = $credentials[$credIndex]
        
        Write-Host "`nYou are about to remove credential '$($selectedCred.Name)'." -ForegroundColor Yellow
        Write-Host "This cannot be undone. Are you sure? (yes/no)" -ForegroundColor Red
        
        $confirm = Read-Host
        if ($confirm -eq "yes") {
            try {
                Remove-DNSProviderCredential -Name $selectedCred.Name
                Write-Host "Credential removed." -ForegroundColor Green
            } catch {
                Write-Error "Failed to remove credential: $($_.Exception.Message)"
            }
        } else {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
        }
    } else {
        Write-Warning "Invalid selection."
    }
    
    Read-Host "Press Enter to continue"
}

function Invoke-TestCredentialMenu {
    [CmdletBinding()]
    param()
    
    Clear-Host
    Write-Host "`n" + "="*60 -ForegroundColor Cyan
    Write-Host "    TEST CREDENTIAL" -ForegroundColor Cyan
    Write-Host "="*60 -ForegroundColor Cyan
    
    # List stored credentials
    $credentials = Get-StoredCredential
    if ($credentials.Count -eq 0) {
        Write-Host "No credentials found." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        return
    }
    
    Write-Host "Select credential to test:" -ForegroundColor Green
    for ($i = 0; $i -lt $credentials.Count; $i++) {
        Write-Host "  $($i + 1). $($credentials[$i].Name) ($($credentials[$i].Type))" -ForegroundColor White
    }
    Write-Host "  0. Cancel" -ForegroundColor Red
    
    $credChoice = Read-Host "`nEnter your choice"
    if ($credChoice -eq "0") {
        return
    }
    
    $credIndex = [int]$credChoice - 1
    if ($credIndex -ge 0 -and $credIndex -lt $credentials.Count) {
        $selectedCred = $credentials[$credIndex]
        
        Write-Host "`nTesting credential '$($selectedCred.Name)'..." -ForegroundColor Cyan
        
        try {
            $testResult = Test-DNSProviderCredential -Name $selectedCred.Name
            if ($testResult) {
                Write-Host "Credential test successful! Authentication with provider works correctly." -ForegroundColor Green
            } else {
                Write-Host "Credential test failed! Authentication with provider failed." -ForegroundColor Red
            }
        } catch {
            Write-Error "Error testing credential: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "Invalid selection."
    }
    
    Read-Host "Press Enter to continue"
}

# Export functions
Export-ModuleMember -Function Show-CredentialManagementMenu
