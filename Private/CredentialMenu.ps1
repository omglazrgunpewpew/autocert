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

function Show-CredentialManagementMenu
{
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    CREDENTIAL MANAGEMENT" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    # List stored credentials
    $credentials = Get-StoredCredential
    if ($credentials.Count -eq 0)
    {
        Write-Warning -Message "No credentials found. You can add new ones."
    } else
    {
        Write-Information -MessageData "Stored Credentials:" -InformationAction Continue
        foreach ($cred in $credentials)
        {
            Write-Host -Object "  - $($cred.Name) ($($cred.Type))" -ForegroundColor White
        }
    }

    Write-Host -Object "`nAvailable Actions:" -ForegroundColor White
    Write-Information -MessageData "1. Add new credential" -InformationAction Continue
    Write-Error -Message "2. Remove credential"
    Write-Host -Object "3. Test credential" -ForegroundColor Cyan
    Write-Host -Object "0. Return to Main Menu" -ForegroundColor DarkRed
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan

    $choice = Read-Host "Enter your choice"

    switch ($choice)
    {
        '1'
        {
            # Add new credential
            Invoke-AddCredentialMenu
        }
        '2'
        {
            # Remove credential
            Invoke-RemoveCredentialMenu
        }
        '3'
        {
            # Test credential
            Invoke-TestCredentialMenu
        }
        '0' { return }
        default
        {
            Write-Warning -Message "Invalid option. Please try again."
            Read-Host "Press Enter to continue"
            Show-CredentialManagementMenu
        }
    }
}

function Invoke-AddCredentialMenu
{
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    ADD NEW CREDENTIAL" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    # Get credential type
    Write-Information -MessageData "`nAvailable Credential Types:" -InformationAction Continue
    Write-Host -Object "1. API Key (for services like Cloudflare, DigitalOcean, etc.)" -ForegroundColor White
    Write-Host -Object "2. Username/Password (for services like Namecheap, GoDaddy, etc.)" -ForegroundColor White
    Write-Host -Object "3. OAuth Token (for services like Google Cloud, AWS, etc.)" -ForegroundColor White
    Write-Error -Message "0. Cancel"

    $typeChoice = Read-Host "`nSelect credential type"
    if ($typeChoice -eq "0")
    {
        return
    }

    $credentialType = switch ($typeChoice)
    {
        '1' { "API Key" }
        '2' { "Username/Password" }
        '3' { "OAuth Token" }
        default
        {
            Write-Warning -Message "Invalid choice. Returning to credential menu."
            Read-Host "Press Enter to continue"
            return
        }
    }

    # Get credential name/identifier
    $credName = Read-Host "`nEnter a name for this credential (e.g. 'Cloudflare-Primary')"
    if ([string]::IsNullOrWhiteSpace($credName))
    {
        Write-Warning -Message "Credential name cannot be empty."
        Read-Host "Press Enter to continue"
        return
    }

    # Get service provider
    $provider = Read-Host "Enter the service provider (e.g. 'Cloudflare', 'Route53', etc.)"

    try
    {
        switch ($credentialType)
        {
            "API Key"
            {
                $apiKey = Read-Host "Enter API Key" -AsSecureString
                $apiSecret = Read-Host "Enter API Secret (if applicable, otherwise press Enter)" -AsSecureString

                # Create the credential object
                Add-DNSProviderCredential -Name $credName -Provider $provider -Type "APIKey" -Key $apiKey -Secret $apiSecret
            }
            "Username/Password"
            {
                $username = Read-Host "Enter Username"
                $password = Read-Host "Enter Password" -AsSecureString

                # Create the credential object
                Add-DNSProviderCredential -Name $credName -Provider $provider -Type "UsernamePassword" -Username $username -Password $password
            }
            "OAuth Token"
            {
                $token = Read-Host "Enter OAuth Token" -AsSecureString

                # Create the credential object
                Add-DNSProviderCredential -Name $credName -Provider $provider -Type "OAuth" -Token $token
            }
        }

        Write-Information -MessageData "`nCredential '$credName' added." -InformationAction Continue
    } catch
    {
        Write-Error -Message "Failed to add credential: $($_.Exception.Message)"
    }

    Read-Host "Press Enter to continue"
}

function Invoke-RemoveCredentialMenu
{
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    REMOVE CREDENTIAL" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    # List stored credentials
    $credentials = Get-StoredCredential
    if ($credentials.Count -eq 0)
    {
        Write-Warning -Message "No credentials found."
        Read-Host "Press Enter to continue"
        return
    }

    Write-Information -MessageData "Select credential to remove:" -InformationAction Continue
    for ($i = 0; $i -lt $credentials.Count; $i++)
    {
        Write-Host -Object "  $($i + 1). $($credentials[$i].Name) ($($credentials[$i].Type))" -ForegroundColor White
    }
    Write-Error -Message "  0. Cancel"

    $credChoice = Read-Host "`nEnter your choice"
    if ($credChoice -eq "0")
    {
        return
    }

    $credIndex = [int]$credChoice - 1
    if ($credIndex -ge 0 -and $credIndex -lt $credentials.Count)
    {
        $selectedCred = $credentials[$credIndex]

        Write-Warning -Message "`nYou are about to remove credential '$($selectedCred.Name)'."
        Write-Error -Message "This cannot be undone. Are you sure? (yes/no)"

        $confirm = Read-Host
        if ($confirm -eq "yes")
        {
            try
            {
                Remove-DNSProviderCredential -Name $selectedCred.Name
                Write-Information -MessageData "Credential removed." -InformationAction Continue
            } catch
            {
                Write-Error -Message "Failed to remove credential: $($_.Exception.Message)"
            }
        } else
        {
            Write-Warning -Message "Operation cancelled."
        }
    } else
    {
        Write-Warning -Message "Invalid selection."
    }

    Read-Host "Press Enter to continue"
}

function Invoke-TestCredentialMenu
{
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Host -Object "`n" + "="*60 -ForegroundColor Cyan
    Write-Host -Object "    TEST CREDENTIAL" -ForegroundColor Cyan
    Write-Host -Object "="*60 -ForegroundColor Cyan

    # List stored credentials
    $credentials = Get-StoredCredential
    if ($credentials.Count -eq 0)
    {
        Write-Warning -Message "No credentials found."
        Read-Host "Press Enter to continue"
        return
    }

    Write-Information -MessageData "Select credential to test:" -InformationAction Continue
    for ($i = 0; $i -lt $credentials.Count; $i++)
    {
        Write-Host -Object "  $($i + 1). $($credentials[$i].Name) ($($credentials[$i].Type))" -ForegroundColor White
    }
    Write-Error -Message "  0. Cancel"

    $credChoice = Read-Host "`nEnter your choice"
    if ($credChoice -eq "0")
    {
        return
    }

    $credIndex = [int]$credChoice - 1
    if ($credIndex -ge 0 -and $credIndex -lt $credentials.Count)
    {
        $selectedCred = $credentials[$credIndex]

        Write-Host -Object "`nTesting credential '$($selectedCred.Name)'..." -ForegroundColor Cyan

        try
        {
            $testResult = Test-DNSProviderCredential -Name $selectedCred.Name
            if ($testResult)
            {
                Write-Information -MessageData "Credential test successful! Authentication with provider works correctly." -InformationAction Continue
            } else
            {
                Write-Error -Message "Credential test failed! Authentication with provider failed."
            }
        } catch
        {
            Write-Error -Message "Error testing credential: $($_.Exception.Message)"
        }
    } else
    {
        Write-Warning -Message "Invalid selection."
    }

    Read-Host "Press Enter to continue"
}

# Export functions
# Export functions for dot-sourcing (commented out for script execution)
# Export-ModuleMember -Function Show-CredentialManagementMenu



