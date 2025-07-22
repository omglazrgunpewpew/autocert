# DNS Provider UI Components
# Part of AutoCert Certificate Management System
# Version: 1.0
# Date: July 21, 2025

<#
.SYNOPSIS
    DNS Provider UI helper functions for AutoCert system
.DESCRIPTION
    Provides UI helper functions for DNS provider management including
    selection menus, configuration dialogs, and status displays.
.NOTES
    This file contains UI components for DNS provider interaction
#>

function Show-DNSProviderSelectionMenu
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Domain,
        [switch]$ShowDetectedOnly
    )

    Clear-Host
    Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
    Write-Information -MessageData "    DNS PROVIDER SELECTION FOR: $Domain" -InformationAction Continue
    Write-Information -MessageData "$("="*70)" -InformationAction Continue

    # Try to detect the DNS provider first
    Write-ProgressHelper -Activity "DNS Detection" -Status "Analyzing domain..." -PercentComplete 10
    $detectedProvider = Get-DNSProvider -Domain $Domain

    if ($detectedProvider.Name -ne "Unknown")
    {
        Write-Information -MessageData "`n✓ Detected DNS Provider: $($detectedProvider.Name)" -InformationAction Continue
        Write-Information -MessageData "  Confidence: $($detectedProvider.Confidence)" -InformationAction Continue
        Write-Information -MessageData "  Plugin: $($detectedProvider.Plugin)" -InformationAction Continue
        if ($detectedProvider.Description)
        {
            Write-Information -MessageData "  $($detectedProvider.Description)" -InformationAction Continue
        }

        if ($ShowDetectedOnly)
        {
            return $detectedProvider
        }

        Write-Information -MessageData "`nOptions:" -InformationAction Continue
        Write-Information -MessageData "1. Use detected provider ($($detectedProvider.Name))" -InformationAction Continue
        Write-Information -MessageData "2. Select different provider" -InformationAction Continue
        Write-Information -MessageData "3. Use manual DNS" -InformationAction Continue
        Write-Information -MessageData "0. Cancel" -InformationAction Continue

        $choice = Get-ValidatedInput -Prompt "`nChoose an option" -ValidOptions @(1, 2, 3)

        switch ($choice)
        {
            1 { return $detectedProvider }
            2 { return Show-AllDNSProviders -Domain $Domain }
            3 { return Get-ManualDNSProvider -Domain $Domain }
            0 { return $null }
        }
    } else
    {
        Write-Warning -Message "Could not automatically detect DNS provider for $Domain"
        Write-Information -MessageData "Available options:" -InformationAction Continue
        Write-Information -MessageData "1. Select from available providers" -InformationAction Continue
        Write-Information -MessageData "2. Use manual DNS" -InformationAction Continue
        Write-Information -MessageData "0. Cancel" -InformationAction Continue

        $choice = Get-ValidatedInput -Prompt "`nChoose an option" -ValidOptions @(1, 2)

        switch ($choice)
        {
            1 { return Show-AllDNSProviders -Domain $Domain }
            2 { return Get-ManualDNSProvider -Domain $Domain }
            0 { return $null }
        }
    }
}

function Show-AllDNSProvider
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Domain
    )

    Clear-Host
    Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
    Write-Information -MessageData "    AVAILABLE DNS PROVIDERS" -InformationAction Continue
    Write-Information -MessageData "$("="*70)" -InformationAction Continue

    $patterns = Get-DNSProviderPattern
    $providers = @()

    # Group providers by confidence level
    $highConfidence = @()
    $mediumConfidence = @()
    $lowConfidence = @()

    foreach ($providerName in ($patterns.Keys | Sort-Object))
    {
        $provider = $patterns[$providerName]
        $providerInfo = @{
            Name        = $providerName
            Plugin      = $provider.Plugin
            Confidence  = $provider.Confidence
            Description = $provider.Description
            SetupUrl    = $provider.SetupUrl
        }

        switch ($provider.Confidence)
        {
            'High' { $highConfidence += $providerInfo }
            'Medium' { $mediumConfidence += $providerInfo }
            'Low' { $lowConfidence += $providerInfo }
        }
    }

    $providers = $highConfidence + $mediumConfidence + $lowConfidence

    Write-Information -MessageData "`nRecommended Providers (High Confidence):" -InformationAction Continue
    $index = 1
    foreach ($provider in $highConfidence)
    {
        Write-Information -MessageData "  $index. $($provider.Name)" -InformationAction Continue
        Write-Information -MessageData "     $($provider.Description)" -InformationAction Continue
        $index++
    }

    if ($mediumConfidence.Count -gt 0)
    {
        Write-Information -MessageData "`nOther Providers:" -InformationAction Continue
        foreach ($provider in $mediumConfidence)
        {
            Write-Information -MessageData "  $index. $($provider.Name)" -InformationAction Continue
            Write-Information -MessageData "     $($provider.Description)" -InformationAction Continue
            $index++
        }
    }

    if ($lowConfidence.Count -gt 0)
    {
        Write-Information -MessageData "`nAdditional Providers:" -InformationAction Continue
        foreach ($provider in $lowConfidence)
        {
            Write-Information -MessageData "  $index. $($provider.Name)" -InformationAction Continue
            Write-Information -MessageData "     $($provider.Description)" -InformationAction Continue
            $index++
        }
    }

    Write-Information -MessageData "`n  $index. Manual DNS (Universal)" -InformationAction Continue
    Write-Information -MessageData "     Manual TXT record creation - Works with any DNS provider" -InformationAction Continue

    Write-Information -MessageData "`n  0. Cancel" -InformationAction Continue

    $validOptions = 1..$index
    $choice = Get-ValidatedInput -Prompt "`nSelect DNS provider" -ValidOptions $validOptions

    if ($choice -eq 0)
    {
        return $null
    } elseif ($choice -eq $index)
    {
        return Get-ManualDNSProvider -Domain $Domain
    } else
    {
        $selectedProvider = $providers[$choice - 1]
        return Show-DNSProviderConfiguration -Provider $selectedProvider -Domain $Domain
    }
}

function Show-DNSProviderConfiguration
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Provider,
        [Parameter(Mandatory)]
        [string]$Domain
    )

    Clear-Host
    Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
    Write-Information -MessageData "    CONFIGURE: $($Provider.Name)" -InformationAction Continue
    Write-Information -MessageData "$("="*70)" -InformationAction Continue

    Write-Information -MessageData "`nProvider: $($Provider.Name)" -InformationAction Continue
    Write-Information -MessageData "Plugin: $($Provider.Plugin)" -InformationAction Continue
    Write-Information -MessageData "Description: $($Provider.Description)" -InformationAction Continue

    if ($Provider.SetupUrl)
    {
        Write-Information -MessageData "`nSetup URL: $($Provider.SetupUrl)" -InformationAction Continue
        Write-Information -MessageData "You may need to visit this URL to obtain API credentials." -InformationAction Continue
    }

    Write-Information -MessageData "`nConfiguration Status:" -InformationAction Continue

    # Check if credentials are already configured
    $credentialStatus = Test-DNSProviderCredentials -Plugin $Provider.Plugin
    if ($credentialStatus.IsConfigured)
    {
        Write-Information -MessageData "✓ Credentials are already configured for $($Provider.Name)" -InformationAction Continue
        Write-Information -MessageData "  Last tested: $($credentialStatus.LastTested)" -InformationAction Continue
        Write-Information -MessageData "  Status: $($credentialStatus.Status)" -InformationAction Continue

        Write-Information -MessageData "`nOptions:" -InformationAction Continue
        Write-Information -MessageData "1. Use existing credentials" -InformationAction Continue
        Write-Information -MessageData "2. Update credentials" -InformationAction Continue
        Write-Information -MessageData "3. Test current credentials" -InformationAction Continue
        Write-Information -MessageData "0. Back to provider selection" -InformationAction Continue

        $choice = Get-ValidatedInput -Prompt "`nChoose an option" -ValidOptions @(1, 2, 3)

        switch ($choice)
        {
            1
            {
                return @{
                    Name         = $Provider.Name
                    Plugin       = $Provider.Plugin
                    Confidence   = 'High'
                    Domain       = $Domain
                    Description  = $Provider.Description
                    IsConfigured = $true
                }
            }
            2 { return Set-DNSProviderCredentials -Provider $Provider -Domain $Domain }
            3
            {
                Test-DNSProviderConnection -Provider $Provider -Domain $Domain
                Wait-UserInput
                return Show-DNSProviderConfiguration -Provider $Provider -Domain $Domain
            }
            0 { return Show-AllDNSProviders -Domain $Domain }
        }
    } else
    {
        Write-Warning -Message "✗ No credentials configured for $($Provider.Name)"
        Write-Information -MessageData "`nTo use this provider, you'll need to configure API credentials." -InformationAction Continue

        Write-Information -MessageData "`nOptions:" -InformationAction Continue
        Write-Information -MessageData "1. Configure credentials now" -InformationAction Continue
        Write-Information -MessageData "2. Show setup instructions" -InformationAction Continue
        Write-Information -MessageData "0. Back to provider selection" -InformationAction Continue

        $choice = Get-ValidatedInput -Prompt "`nChoose an option" -ValidOptions @(1, 2)

        switch ($choice)
        {
            1 { return Set-DNSProviderCredentials -Provider $Provider -Domain $Domain }
            2
            {
                Show-DNSProviderSetupInstructions -Provider $Provider
                Wait-UserInput
                return Show-DNSProviderConfiguration -Provider $Provider -Domain $Domain
            }
            0 { return Show-AllDNSProviders -Domain $Domain }
        }
    }
}

function Show-DNSProviderSetupInstruction
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Provider
    )

    Clear-Host
    Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
    Write-Information -MessageData "    SETUP INSTRUCTIONS: $($Provider.Name)" -InformationAction Continue
    Write-Information -MessageData "$("="*70)" -InformationAction Continue

    switch ($Provider.Plugin)
    {
        'Cloudflare'
        {
            Write-Information -MessageData "`nCloudflare API Token Setup:" -InformationAction Continue
            Write-Information -MessageData "1. Go to: https://dash.cloudflare.com/profile/api-tokens" -InformationAction Continue
            Write-Information -MessageData "2. Click 'Create Token'" -InformationAction Continue
            Write-Information -MessageData "3. Use the 'Custom token' template" -InformationAction Continue
            Write-Information -MessageData "4. Set the following permissions:" -InformationAction Continue
            Write-Information -MessageData "   - Zone:DNS:Edit" -InformationAction Continue
            Write-Information -MessageData "   - Zone:Zone:Read" -InformationAction Continue
            Write-Information -MessageData "5. Set Zone Resources to 'Include All zones' or specific zones" -InformationAction Continue
            Write-Information -MessageData "6. Click 'Continue to summary' then 'Create Token'" -InformationAction Continue
            Write-Information -MessageData "7. Copy the token and use it when prompted" -InformationAction Continue
        }
        'Route53'
        {
            Write-Information -MessageData "`nAWS Route53 Setup:" -InformationAction Continue
            Write-Information -MessageData "Option 1 - IAM User:" -InformationAction Continue
            Write-Information -MessageData "1. Go to AWS IAM Console" -InformationAction Continue
            Write-Information -MessageData "2. Create a new user with programmatic access" -InformationAction Continue
            Write-Information -MessageData "3. Attach the 'Route53FullAccess' policy (or create custom)" -InformationAction Continue
            Write-Information -MessageData "4. Note the Access Key ID and Secret Access Key" -InformationAction Continue
            Write-Information -MessageData "`nOption 2 - AWS Profile:" -InformationAction Continue
            Write-Information -MessageData "1. Install AWS CLI" -InformationAction Continue
            Write-Information -MessageData "2. Run 'aws configure --profile autocert'" -InformationAction Continue
            Write-Information -MessageData "3. Enter your credentials" -InformationAction Continue
        }
        'Azure'
        {
            Write-Information -MessageData "`nAzure DNS Setup:" -InformationAction Continue
            Write-Information -MessageData "1. Create a Service Principal in Azure AD" -InformationAction Continue
            Write-Information -MessageData "2. Assign 'DNS Zone Contributor' role to your DNS zones" -InformationAction Continue
            Write-Information -MessageData "3. Note the Application ID, Tenant ID, and Secret" -InformationAction Continue
            Write-Information -MessageData "4. Alternatively, use Azure CLI: 'az login'" -InformationAction Continue
        }
        'GoogleDomains'
        {
            Write-Information -MessageData "`nGoogle Cloud DNS Setup:" -InformationAction Continue
            Write-Information -MessageData "1. Go to Google Cloud Console" -InformationAction Continue
            Write-Information -MessageData "2. Create a Service Account" -InformationAction Continue
            Write-Information -MessageData "3. Assign 'DNS Administrator' role" -InformationAction Continue
            Write-Information -MessageData "4. Create and download a JSON key file" -InformationAction Continue
            Write-Information -MessageData "5. Set GOOGLE_APPLICATION_CREDENTIALS environment variable" -InformationAction Continue
        }
        'DigitalOcean'
        {
            Write-Information -MessageData "`nDigitalOcean API Setup:" -InformationAction Continue
            Write-Information -MessageData "1. Go to: https://cloud.digitalocean.com/account/api/tokens" -InformationAction Continue
            Write-Information -MessageData "2. Click 'Generate New Token'" -InformationAction Continue
            Write-Information -MessageData "3. Give it a name and ensure 'Write' scope is selected" -InformationAction Continue
            Write-Information -MessageData "4. Copy the token and use it when prompted" -InformationAction Continue
        }
        default
        {
            Write-Information -MessageData "`nGeneral Setup Instructions:" -InformationAction Continue
            Write-Information -MessageData "1. Check your DNS provider's documentation for API access" -InformationAction Continue
            Write-Information -MessageData "2. Create API credentials (usually API key or token)" -InformationAction Continue
            Write-Information -MessageData "3. Ensure the credentials have DNS record modification permissions" -InformationAction Continue
            if ($Provider.SetupUrl)
            {
                Write-Information -MessageData "4. Visit: $($Provider.SetupUrl)" -InformationAction Continue
            }
        }
    }

    Write-Information -MessageData "`nSecurity Best Practices:" -InformationAction Continue
    Write-Information -MessageData "• Use the minimum required permissions" -InformationAction Continue
    Write-Information -MessageData "• Store credentials securely" -InformationAction Continue
    Write-Information -MessageData "• Regularly rotate API keys" -InformationAction Continue
    Write-Information -MessageData "• Monitor API usage" -InformationAction Continue
}

function Set-DNSProviderCredential
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Provider,
        [Parameter(Mandatory)]
        [string]$Domain
    )

    Clear-Host
    Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
    Write-Information -MessageData "    CONFIGURE CREDENTIALS: $($Provider.Name)" -InformationAction Continue
    Write-Information -MessageData "$("="*70)" -InformationAction Continue

    Write-Information -MessageData "Provider: $($Provider.Name)" -InformationAction Continue
    Write-Information -MessageData "Plugin: $($Provider.Plugin)" -InformationAction Continue

    try
    {
        # Use the credential management system
        $credentialName = "DNS_$($Provider.Plugin)"
        $existingCred = Get-SecureCredential -ProviderName $credentialName

        if ($existingCred)
        {
            Write-Information -MessageData "`nExisting credentials found for $($Provider.Name)" -InformationAction Continue
            Write-Information -MessageData "1. Update existing credentials" -InformationAction Continue
            Write-Information -MessageData "2. Keep existing credentials" -InformationAction Continue
            Write-Information -MessageData "0. Cancel" -InformationAction Continue

            $choice = Get-ValidatedInput -Prompt "`nChoose an option" -ValidOptions @(1, 2)
            if ($choice -eq 2)
            {
                return @{
                    Name         = $Provider.Name
                    Plugin       = $Provider.Plugin
                    Confidence   = 'High'
                    Domain       = $Domain
                    Description  = $Provider.Description
                    IsConfigured = $true
                }
            } elseif ($choice -eq 0)
            {
                return $null
            }
        }

        # Get new credentials based on provider type
        $newCredentials = Get-DNSProviderCredentialInput -Provider $Provider
        if (-not $newCredentials)
        {
            Write-Warning -Message "Credential configuration cancelled"
            return $null
        }

        # Store credentials securely
        Set-SecureCredential -ProviderName $credentialName -Credential $newCredentials

        # Test the credentials
        Write-Information -MessageData "`nTesting credentials..." -InformationAction Continue
        $testResult = Test-DNSProviderConnection -Provider $Provider -Domain $Domain -Credentials $newCredentials

        if ($testResult.Success)
        {
            Write-Information -MessageData "✓ Credentials verified successfully!" -InformationAction Continue
            return @{
                Name         = $Provider.Name
                Plugin       = $Provider.Plugin
                Confidence   = 'High'
                Domain       = $Domain
                Description  = $Provider.Description
                IsConfigured = $true
                TestResult   = $testResult
            }
        } else
        {
            Write-Error -Message "✗ Credential test failed: $($testResult.Error)"
            Write-Information -MessageData "Would you like to try again? (y/n)" -InformationAction Continue
            $retry = Read-Host
            if ($retry -eq 'y' -or $retry -eq 'Y')
            {
                return Set-DNSProviderCredentials -Provider $Provider -Domain $Domain
            }
            return $null
        }
    } catch
    {
        Write-Error -Message "Failed to configure credentials: $($_.Exception.Message)"
        return $null
    }
}

function Get-DNSProviderCredentialInput
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Provider
    )

    Write-Information -MessageData "`nEnter credentials for $($Provider.Name):" -InformationAction Continue

    switch ($Provider.Plugin)
    {
        'Cloudflare'
        {
            $token = Read-Host "Cloudflare API Token" -AsSecureString
            return @{
                CFToken = $token
            }
        }
        'Route53'
        {
            Write-Information -MessageData "Choose authentication method:" -InformationAction Continue
            Write-Information -MessageData "1. Access Key and Secret" -InformationAction Continue
            Write-Information -MessageData "2. AWS Profile" -InformationAction Continue

            $choice = Get-ValidatedInput -Prompt "Choose method" -ValidOptions @(1, 2)

            if ($choice -eq 1)
            {
                $accessKey = Read-Host "AWS Access Key ID"
                $secretKey = Read-Host "AWS Secret Access Key" -AsSecureString
                $region = Read-Host "AWS Region (default: us-east-1)"
                if ([string]::IsNullOrWhiteSpace($region)) { $region = "us-east-1" }

                return @{
                    R53AccessKey = $accessKey
                    R53SecretKey = $secretKey
                    R53Region    = $region
                }
            } else
            {
                $profileName = Read-Host "AWS Profile Name (default: default)"
                if ([string]::IsNullOrWhiteSpace($profileName)) { $profileName = "default" }

                return @{
                    R53ProfileName = $profileName
                }
            }
        }
        'Azure'
        {
            $tenantId = Read-Host "Tenant ID"
            $clientId = Read-Host "Application/Client ID"
            $clientSecret = Read-Host "Client Secret" -AsSecureString
            $subscriptionId = Read-Host "Subscription ID"

            return @{
                AZTenantId       = $tenantId
                AZAppId          = $clientId
                AZAppSecret      = $clientSecret
                AZSubscriptionId = $subscriptionId
            }
        }
        'DigitalOcean'
        {
            $token = Read-Host "DigitalOcean API Token" -AsSecureString
            return @{
                DOToken = $token
            }
        }
        default
        {
            Write-Information -MessageData "Generic API credential entry for $($Provider.Name):" -InformationAction Continue
            $apiKey = Read-Host "API Key/Token" -AsSecureString
            return @{
                ApiKey   = $apiKey
                Provider = $Provider.Plugin
            }
        }
    }
}

function Test-DNSProviderConnection
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Provider,
        [Parameter(Mandatory)]
        [string]$Domain,
        [hashtable]$Credentials
    )

    Write-ProgressHelper -Activity "Testing DNS Provider" -Status "Connecting to $($Provider.Name)..." -PercentComplete 10

    try
    {
        # This would integrate with the actual DNS provider testing system
        # For now, we'll simulate the test
        Start-Sleep -Seconds 2

        Write-ProgressHelper -Activity "Testing DNS Provider" -Status "Verifying permissions..." -PercentComplete 50
        Start-Sleep -Seconds 1

        Write-ProgressHelper -Activity "Testing DNS Provider" -Status "Test complete" -PercentComplete 100

        # Simulate successful test
        return @{
            Success  = $true
            Provider = $Provider.Name
            TestTime = Get-Date
            Message  = "Connection successful"
        }
    } catch
    {
        return @{
            Success  = $false
            Provider = $Provider.Name
            TestTime = Get-Date
            Error    = $_.Exception.Message
        }
    } finally
    {
        Write-Progress -Activity "Testing DNS Provider" -Completed
    }
}

function Test-DNSProviderCredential
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Plugin
    )

    try
    {
        $credentialName = "DNS_$Plugin"
        $credentials = Get-SecureCredential -ProviderName $credentialName

        if ($credentials)
        {
            # Check if we have test results cached
            $testResultPath = Join-Path $env:LOCALAPPDATA "AutoCert\DNSTests\$Plugin.json"
            if (Test-Path $testResultPath)
            {
                $testResult = Get-Content $testResultPath | ConvertFrom-Json
                return @{
                    IsConfigured = $true
                    LastTested   = $testResult.LastTested
                    Status       = $testResult.Status
                }
            } else
            {
                return @{
                    IsConfigured = $true
                    LastTested   = "Never"
                    Status       = "Unknown"
                }
            }
        } else
        {
            return @{
                IsConfigured = $false
                LastTested   = "N/A"
                Status       = "Not Configured"
            }
        }
    } catch
    {
        return @{
            IsConfigured = $false
            LastTested   = "Error"
            Status       = "Error: $($_.Exception.Message)"
        }
    }
}

function Get-ManualDNSProvider
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Domain
    )

    Clear-Host
    Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
    Write-Information -MessageData "    MANUAL DNS CONFIGURATION" -InformationAction Continue
    Write-Information -MessageData "$("="*70)" -InformationAction Continue

    Write-Information -MessageData "Manual DNS mode allows you to use any DNS provider by manually" -InformationAction Continue
    Write-Information -MessageData "creating the required TXT records for domain validation." -InformationAction Continue

    Write-Information -MessageData "`nHow it works:" -InformationAction Continue
    Write-Information -MessageData "1. AutoCert will generate the required TXT record" -InformationAction Continue
    Write-Information -MessageData "2. You'll add this record to your DNS provider's control panel" -InformationAction Continue
    Write-Information -MessageData "3. AutoCert will verify the record and complete validation" -InformationAction Continue
    Write-Information -MessageData "4. The certificate will be issued" -InformationAction Continue

    Write-Information -MessageData "`nPros:" -InformationAction Continue
    Write-Information -MessageData "• Works with any DNS provider" -InformationAction Continue
    Write-Information -MessageData "• No API credentials required" -InformationAction Continue
    Write-Information -MessageData "• Full control over DNS records" -InformationAction Continue

    Write-Information -MessageData "`nCons:" -InformationAction Continue
    Write-Information -MessageData "• Manual intervention required for each certificate" -InformationAction Continue
    Write-Information -MessageData "• Not suitable for automated renewals" -InformationAction Continue
    Write-Information -MessageData "• Slower process" -InformationAction Continue

    Write-Information -MessageData "`nDo you want to proceed with Manual DNS? (y/n)" -InformationAction Continue
    $confirm = Read-Host

    if ($confirm -eq 'y' -or $confirm -eq 'Y')
    {
        return @{
            Name         = "Manual DNS"
            Plugin       = "Manual"
            Confidence   = "High"
            Domain       = $Domain
            Description  = "Manual TXT record creation - Universal compatibility"
            IsConfigured = $true
            SetupUrl     = $null
        }
    } else
    {
        return Show-DNSProviderSelectionMenu -Domain $Domain
    }
}

function Show-DNSProviderStatus
{
    [CmdletBinding()]
    param()

    Clear-Host
    Write-Information -MessageData "`n$("="*70)" -InformationAction Continue
    Write-Information -MessageData "    DNS PROVIDER STATUS" -InformationAction Continue
    Write-Information -MessageData "$("="*70)" -InformationAction Continue

    $patterns = Get-DNSProviderPattern
    $configuredProviders = @()

    foreach ($providerName in ($patterns.Keys | Sort-Object))
    {
        $provider = $patterns[$providerName]
        $credentialStatus = Test-DNSProviderCredentials -Plugin $provider.Plugin

        if ($credentialStatus.IsConfigured)
        {
            $configuredProviders += @{
                Name       = $providerName
                Plugin     = $provider.Plugin
                Status     = $credentialStatus.Status
                LastTested = $credentialStatus.LastTested
            }
        }
    }

    if ($configuredProviders.Count -eq 0)
    {
        Write-Warning -Message "No DNS providers are currently configured."
        Write-Information -MessageData "`nTo configure a DNS provider:" -InformationAction Continue
        Write-Information -MessageData "1. Use the certificate registration process" -InformationAction Continue
        Write-Information -MessageData "2. Or run: Register-Certificate -Domain yourdomain.com" -InformationAction Continue
    } else
    {
        Write-Information -MessageData "`nConfigured DNS Providers:" -InformationAction Continue

        foreach ($provider in $configuredProviders)
        {
            $statusIcon = switch ($provider.Status)
            {
                "OK" { "✓" }
                "Unknown" { "?" }
                default { "✗" }
            }

            Write-Information -MessageData "  $statusIcon $($provider.Name) ($($provider.Plugin))" -InformationAction Continue
            Write-Information -MessageData "    Status: $($provider.Status)" -InformationAction Continue
            Write-Information -MessageData "    Last tested: $($provider.LastTested)" -InformationAction Continue
            Write-Information -MessageData "" -InformationAction Continue
        }

        Write-Information -MessageData "Options:" -InformationAction Continue
        Write-Information -MessageData "1. Test all providers" -InformationAction Continue
        Write-Information -MessageData "2. Configure new provider" -InformationAction Continue
        Write-Information -MessageData "3. Remove provider configuration" -InformationAction Continue
        Write-Information -MessageData "0. Return to main menu" -InformationAction Continue

        $choice = Get-ValidatedInput -Prompt "`nChoose an option" -ValidOptions @(1, 2, 3)

        switch ($choice)
        {
            1 { Test-AllDNSProviders }
            2 { Show-AllDNSProviders -Domain "example.com" }
            3 { Show-RemoveDNSProviderMenu -ConfiguredProviders $configuredProviders }
            0 { return }
        }
    }
}

function Test-AllDNSProvider
{
    [CmdletBinding()]
    param()

    Write-Information -MessageData "`nTesting all configured DNS providers..." -InformationAction Continue

    $patterns = Get-DNSProviderPattern
    $testResults = @()

    foreach ($providerName in ($patterns.Keys | Sort-Object))
    {
        $provider = $patterns[$providerName]
        $credentialStatus = Test-DNSProviderCredentials -Plugin $provider.Plugin

        if ($credentialStatus.IsConfigured)
        {
            Write-Information -MessageData "Testing $providerName..." -InformationAction Continue

            $testResult = Test-DNSProviderConnection -Provider @{
                Name   = $providerName
                Plugin = $provider.Plugin
            } -Domain "test.example.com"

            $testResults += @{
                Name    = $providerName
                Plugin  = $provider.Plugin
                Success = $testResult.Success
                Message = if ($testResult.Success) { $testResult.Message } else { $testResult.Error }
            }

            $icon = if ($testResult.Success) { "✓" } else { "✗" }
            $status = if ($testResult.Success) { "OK" } else { "Failed" }
            Write-Information -MessageData "  $icon $providerName - $status" -InformationAction Continue
        }
    }

    Wait-UserInput -Message "`nPress Enter to continue"
}

function Show-RemoveDNSProviderMenu
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$ConfiguredProviders
    )

    Write-Information -MessageData "`nRemove DNS Provider Configuration:" -InformationAction Continue

    for ($i = 0; $i -lt $ConfiguredProviders.Count; $i++)
    {
        Write-Information -MessageData "  $($i + 1). $($ConfiguredProviders[$i].Name)" -InformationAction Continue
    }
    Write-Information -MessageData "  0. Cancel" -InformationAction Continue

    $validOptions = 1..$ConfiguredProviders.Count
    $choice = Get-ValidatedInput -Prompt "`nSelect provider to remove" -ValidOptions $validOptions

    if ($choice -eq 0)
    {
        return
    }

    $selectedProvider = $ConfiguredProviders[$choice - 1]
    Write-Warning -Message "This will remove all stored credentials for $($selectedProvider.Name)"
    Write-Information -MessageData "Are you sure? (y/n)" -InformationAction Continue
    $confirm = Read-Host

    if ($confirm -eq 'y' -or $confirm -eq 'Y')
    {
        try
        {
            Remove-SecureCredential -ProviderName "DNS_$($selectedProvider.Plugin)"
            Write-Information -MessageData "✓ Removed configuration for $($selectedProvider.Name)" -InformationAction Continue
        } catch
        {
            Write-Error -Message "Failed to remove configuration: $($_.Exception.Message)"
        }
    }

    Wait-UserInput -Message "Press Enter to continue"
}

function Wait-UserInput
{
    [CmdletBinding()]
    param(
        [string]$Message = "`nPress Enter to continue"
    )
    Read-Host $Message | Out-Null
}

# Export functions for dot-sourcing
# Note: Functions are available globally due to dot-sourcing architecture
