# Functions/Register-Certificate.ps1
<#
    .SYNOPSIS
        Certificate registration with DNS provider support,
        robust error handling, and validation.
#>
function Register-Certificate
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        [Parameter()]
        [switch]$Force
    )
    # Ensure circuit breaker is loaded
    if (-not (Get-Command -Name Invoke-WithCircuitBreaker -ErrorAction SilentlyContinue)) {
        . "$PSScriptRoot\..\Core\CircuitBreaker.ps1"
    }

    # Ensure ACME server is set
    Initialize-ACMEServer
    # Load public suffix list for accurate domain parsing
    Write-ProgressHelper -Activity "Certificate Registration" -Status "Loading domain database..." -PercentComplete 5
    $publicSuffixes = Get-PublicSuffixList
    # Load user settings
    $settings = Get-ScriptSettings
    # Prompt for domain name with validation
    do
    {
        $domain = Read-Host "`nEnter the domain name (e.g., server.domain.com) or 0 to go back"
        if ($domain -eq '0')
        {
            return
        }
        if (Test-ValidDomain -Domain $domain)
        {
            break
        }
        Write-Warning -Message "Please enter a valid domain name."
    } while ($true)
    Write-ProgressHelper -Activity "Certificate Registration" -Status "Analyzing domain structure..." -PercentComplete 15
    # Extract base domain using public suffix list
    $baseDomain = Get-BaseDomain -domainName $domain -Suffixes $publicSuffixes
    Write-Verbose "Base domain identified: $baseDomain"
    # Initialize variables
    $mainDomain = $domain
    $domains = @()
    # Ask for certificate type
    while ($true)
    {
        Write-Host -Object "`nSelect the type of certificate you want to create:"
        Write-Host -Object "1) Server-specific certificate for $domain"
        Write-Host -Object "2) Wildcard certificate for *.$baseDomain"
        Write-Host -Object "3) Multi-domain certificate (SAN)"
        Write-Host -Object "0) Back"
        $certTypeChoice = Get-ValidatedInput -Prompt "`nEnter the number corresponding to your choice (0-3)" -ValidOptions 1, 2, 3
        switch ($certTypeChoice)
        {
            0 { return }
            1
            {
                $mainDomain = $domain
                $domains = @($mainDomain)
                break
            }
            2
            {
                $mainDomain = "*.$baseDomain"
                $domains = @($mainDomain)
                break
            }
            3
            {
                # Multi-domain certificate
                $domains = @($domain)  # Start with main domain
                while ($true)
                {
                    $additionalDomain = Read-Host "`nEnter additional domain (or press Enter to finish, 0 to cancel)"
                    if ($additionalDomain -eq '0')
                    {
                        return
                    }
                    if ([string]::IsNullOrWhiteSpace($additionalDomain))
                    {
                        break
                    }
                    if (Test-ValidDomain -Domain $additionalDomain)
                    {
                        if ($domains -notcontains $additionalDomain)
                        {
                            $domains += $additionalDomain
                            Write-Information -MessageData "Added: $additionalDomain" -InformationAction Continue
                        } else
                        {
                            Write-Warning -Message "Domain already added: $additionalDomain"
                        }
                    } else
                    {
                        Write-Warning -Message "Invalid domain format: $additionalDomain"
                    }
                }
                $mainDomain = $domains[0]  # First domain is main domain
                break
            }
        }
        if ($domains.Count -gt 0)
        {
            break
        }
    }
    Write-Host -Object "`nCertificate will be issued for:" -ForegroundColor Cyan
    $domains | ForEach-Object { Write-Host -Object "  - $_" -ForegroundColor Yellow }

    # Select challenge type
    Write-Host -Object "`nSelect the challenge validation method:"
    Write-Host -Object "1) DNS-01 Challenge (default - requires DNS provider API access)"
    Write-Host -Object "2) HTTP-01 Challenge - Self-hosted listener (requires port 80 access)"
    Write-Host -Object "3) HTTP-01 Challenge - Existing web server (requires web root access)"
    Write-Host -Object "0) Back"

    $challengeType = $null
    $challengeTypeSelected = $false
    while (-not $challengeTypeSelected)
    {
        $challengeChoice = Get-ValidatedInput -Prompt "`nEnter the corresponding number (0-3)" -ValidOptions 0, 1, 2, 3
        switch ($challengeChoice)
        {
            0 { return }
            1
            {
                $challengeType = 'DNS-01'
                $challengeTypeSelected = $true
            }
            2
            {
                $challengeType = 'HTTP-01-SelfHost'
                $challengeTypeSelected = $true
            }
            3
            {
                $challengeType = 'HTTP-01-WebRoot'
                $challengeTypeSelected = $true
            }
        }
    }

    Write-Log "Challenge type selected: $challengeType"

    # Handle DNS-01 challenge
    if ($challengeType -eq 'DNS-01')
    {
        Write-ProgressHelper -Activity "Certificate Registration" -Status "Detecting DNS provider..." -PercentComplete 25
        # Attempt to auto-detect DNS provider
        $dnsProvider = Get-DNSProvider -Domain $baseDomain
    $plugin = $null
    if ($dnsProvider.Name -ne "Unknown")
    {
        Write-Information -MessageData "`nDetected DNS provider: $($dnsProvider.Name) (Confidence: $($dnsProvider.Confidence))" -InformationAction Continue
        Write-Log "Detected DNS provider: $($dnsProvider.Name)"
        if ($dnsProvider.Confidence -eq "High")
        {
            $useDetected = Read-Host "`nUse detected provider $($dnsProvider.Name)? (Y/N)"
            if ($useDetected -match '^[Yy]$')
            {
                $plugin = $dnsProvider.Plugin
            }
        }
    } else
    {
        Write-Warning -Message "`nDNS provider could not be automatically detected."
        if ($dnsProvider.NSRecords.Count -gt 0)
        {
            Write-Host -Object "Detected NS records:" -ForegroundColor Cyan
            $dnsProvider.NSRecords | ForEach-Object { Write-Host -Object "  - $_" -ForegroundColor Gray }
        }
    }
    # If DNS provider not detected or user declined, prompt for manual selection
    if (-not $plugin)
    {
        $pluginSelected = $false
        while (-not $pluginSelected)
        {
            Write-Host -Object "`nSelect the challenge plugin:"
            Write-Host -Object "1) DNS - Cloudflare"
            Write-Host -Object "2) DNS - AWS Route53"
            Write-Host -Object "3) DNS - Azure"
            Write-Host -Object "4) DNS - Google Cloud"
            Write-Host -Object "5) DNS - DigitalOcean"
            Write-Host -Object "6) Manual (default)"
            Write-Host -Object "7) Other DNS Plugin"
            Write-Host -Object "0) Back"
            $pluginOption = Get-ValidatedInput -Prompt "`nEnter the corresponding number (0-7)" -ValidOptions 1, 2, 3, 4, 5, 6, 7
            switch ($pluginOption)
            {
                0 { return }
                1 { $plugin = 'Cloudflare'; $pluginSelected = $true }
                2 { $plugin = 'Route53'; $pluginSelected = $true }
                3 { $plugin = 'Azure'; $pluginSelected = $true }
                4 { $plugin = 'GoogleDomains'; $pluginSelected = $true }
                5 { $plugin = 'DigitalOcean'; $pluginSelected = $true }
                6 { $plugin = 'Manual'; $pluginSelected = $true }
                7
                {
                    # List all available DNS plugins
                    $plugins = @(Get-PAPlugin | Where-Object { $_.ChallengeType -eq 'dns-01' })
                    if ($plugins.Count -eq 0)
                    {
                        Write-Warning -Message "`nNo DNS plugins are available."
                        $plugin = 'Manual'
                        $pluginSelected = $true
                    } else
                    {
                        $dnsPluginSelected = $false
                        while (-not $dnsPluginSelected)
                        {
                            Write-Host -Object "`nAvailable DNS Plugins:"
                            $i = 1
                            foreach ($p in $plugins)
                            {
                                Write-Host -Object "$i) $($p.Name)"
                                $i++
                            }
                            Write-Host -Object "0) Back"
                            $pluginSelection = Get-ValidatedInput -Prompt "`nEnter the number corresponding to your choice" -ValidOptions (1..$plugins.Count)
                            if ($pluginSelection -eq 0)
                            {
                                break
                            } else
                            {
                                $plugin = $plugins[$pluginSelection - 1].Name
                                $pluginSelected = $true
                                $dnsPluginSelected = $true
                            }
                        }
                    }
                }
            }
        }
    }
    }
    # Handle HTTP-01 Self-Hosted challenge
    elseif ($challengeType -eq 'HTTP-01-SelfHost')
    {
        Write-ProgressHelper -Activity "Certificate Registration" -Status "Configuring HTTP listener..." -PercentComplete 25
        $plugin = 'WebSelfHost'
        $pluginArgs = @{}

        # Ask for port configuration
        Write-Host -Object "`nHTTP-01 Self-Hosted Listener Configuration"
        Write-Host -Object "This will start an HTTP listener on your server to respond to ACME challenges."
        Write-Host -Object "`nIMPORTANT: Ensure that:"
        Write-Host -Object "  - Port 80 (or custom port) is not already in use"
        Write-Host -Object "  - The domain points to this server's public IP"
        Write-Host -Object "  - Firewall allows incoming connections on the specified port"
        Write-Host -Object "  - If using a custom port, ensure proper port forwarding (80 -> custom port)"

        $useCustomPort = Read-Host "`nUse custom port? (Y/N, default=N to use port 80)"
        if ($useCustomPort -match '^[Yy]$')
        {
            do
            {
                $customPort = Read-Host "Enter port number (1-65535) or 0 to cancel"
                if ($customPort -eq '0') { return }
                if ($customPort -match '^\d+$' -and [int]$customPort -ge 1 -and [int]$customPort -le 65535)
                {
                    $pluginArgs['WSHPort'] = $customPort
                    Write-Information -MessageData "Using port: $customPort" -InformationAction Continue
                    break
                }
                Write-Warning -Message "Please enter a valid port number between 1 and 65535."
            } while ($true)
        }
        else
        {
            Write-Information -MessageData "Using default port: 80" -InformationAction Continue
        }

        # Ask for timeout
        $customTimeout = Read-Host "`nEnter listener timeout in seconds (default=120, 0=unlimited)"
        if ($customTimeout -match '^\d+$')
        {
            $pluginArgs['WSHTimeout'] = [int]$customTimeout
        }
        else
        {
            $pluginArgs['WSHTimeout'] = 120
        }

        Write-Log "HTTP-01 SelfHost configured with port: $($pluginArgs.WSHPort), timeout: $($pluginArgs.WSHTimeout)"
    }
    # Handle HTTP-01 WebRoot challenge
    elseif ($challengeType -eq 'HTTP-01-WebRoot')
    {
        Write-ProgressHelper -Activity "Certificate Registration" -Status "Configuring web root..." -PercentComplete 25
        $plugin = 'WebRoot'
        $pluginArgs = @{}

        Write-Host -Object "`nHTTP-01 Web Root Configuration"
        Write-Host -Object "This will place challenge files in your existing web server's document root."
        Write-Host -Object "`nIMPORTANT: Ensure that:"
        Write-Host -Object "  - Your web server (IIS, Apache, nginx) is running"
        Write-Host -Object "  - The domain is configured in your web server"
        Write-Host -Object "  - The web root path is accessible and writable"
        Write-Host -Object "  - The /.well-known/acme-challenge/ path is publicly accessible"

        do
        {
            $webRoot = Read-Host "`nEnter the full path to your web server's document root (e.g., C:\inetpub\wwwroot) or 0 to cancel"
            if ($webRoot -eq '0') { return }

            # Validate path exists
            if (Test-Path -Path $webRoot -PathType Container)
            {
                $pluginArgs['WRPath'] = $webRoot
                Write-Information -MessageData "Web root path set to: $webRoot" -InformationAction Continue
                break
            }
            else
            {
                Write-Warning -Message "Path does not exist or is not accessible: $webRoot"
                $createPath = Read-Host "Would you like to create this directory? (Y/N)"
                if ($createPath -match '^[Yy]$')
                {
                    try
                    {
                        New-Item -Path $webRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
                        $pluginArgs['WRPath'] = $webRoot
                        Write-Information -MessageData "Created web root path: $webRoot" -InformationAction Continue
                        break
                    }
                    catch
                    {
                        Write-Error -Message "Failed to create directory: $($_.Exception.Message)"
                    }
                }
            }
        } while ($true)

        # Ask about exact path
        Write-Host -Object "`nBy default, challenge files will be placed in: $webRoot\.well-known\acme-challenge\"
        $useExactPath = Read-Host "Use the specified path as-is without adding .well-known/acme-challenge? (Y/N, default=N)"
        if ($useExactPath -match '^[Yy]$')
        {
            $pluginArgs['WRExactPath'] = $true
            Write-Information -MessageData "Challenge files will be placed directly in: $webRoot" -InformationAction Continue
        }
        else
        {
            Write-Information -MessageData "Challenge files will be placed in: $webRoot\.well-known\acme-challenge\" -InformationAction Continue
        }

        Write-Log "HTTP-01 WebRoot configured with path: $webRoot"
    }

    Write-ProgressHelper -Activity "Certificate Registration" -Status "Configuring ACME account..." -PercentComplete 40
    # Ensure an ACME account exists
    if (-not (Get-PAAccount))
    {
        Write-Host -Object "`nNo ACME account found. Creating a new account..."
        $email = $settings.LastUsedEmail
        if (-not $email -or -not (Test-ValidEmail -Email $email))
        {
            do
            {
                $email = Read-Host "`nEnter your email address for Let's Encrypt notifications or 0 to go back"
                if ($email -eq '0')
                {
                    return
                }
            } while (-not (Test-ValidEmail -Email $email))
        } else
        {
            $useStoredEmail = Read-Host "`nUse stored email address ($email)? (Y/N)"
            if ($useStoredEmail -notmatch '^[Yy]$')
            {
                do
                {
                    $email = Read-Host "`nEnter your email address for Let's Encrypt notifications or 0 to go back"
                    if ($email -eq '0')
                    {
                        return
                    }
                } while (-not (Test-ValidEmail -Email $email))
            }
        }
        try
        {
            Invoke-WithRetry -ScriptBlock {
                New-PAAccount -AcceptTOS -Contact $email -ErrorAction Stop
            } -MaxAttempts 3 -InitialDelaySeconds 5 `
                -OperationName "ACME account creation"
            Write-Information -MessageData "`nACME account created." -InformationAction Continue
            Write-Log "ACME account created with email: $email"
            # Save email for future use
            $settings.LastUsedEmail = $email
            Save-ScriptSettings -Settings $settings
        } catch
        {
            Write-Error -Message "Failed to create ACME account after multiple attempts: $($_)"
            Write-Log "Failed to create ACME account: $($_)" -Level 'Error'
            return
        }
    }

    # Configure DNS plugin arguments (only for DNS-01 challenges)
    if ($challengeType -eq 'DNS-01')
    {
        Write-ProgressHelper -Activity "Certificate Registration" -Status "Configuring DNS plugin..." -PercentComplete 55
        # Initialize plugin arguments if not already set
        if (-not $pluginArgs) {
            $pluginArgs = @{}
        }
        # Handle plugin-specific authentication
        switch ($plugin)
    {
        'Cloudflare'
        {
            $cred = Get-SecureCredential -ProviderName 'Cloudflare'
            if (-not $cred)
            {
                Write-Host -Object "`nCloudflare credentials not found. Opening browser for API token creation..." -ForegroundColor Cyan
                Start-Process "https://dash.cloudflare.com/profile/api-tokens"
                Write-Host -Object "`nPlease follow these steps to create an API Token:`n" -ForegroundColor Cyan
                Write-Host -Object "1. Log in to your Cloudflare account."
                Write-Host -Object "2. Navigate to 'My Profile' > 'API Tokens'."
                Write-Host -Object "3. Click 'Create Token'."
                Write-Host -Object "4. Select 'Create Custom Token'."
                Write-Host -Object "5. In the 'Permissions' section, add:"
                Write-Host -Object "   - Zone:DNS:Edit"
                Write-Host -Object "6. In the 'Zone Resources' section:"
                Write-Host -Object "   - Include: All zones (or specify your zone)"
                Write-Host -Object "7. Give your token a name and click 'Continue to summary'."
                Write-Host -Object "8. Review and click 'Create Token'."
                Write-Host -Object "9. Copy the API Token displayed.`n"
                do
                {
                    $cfToken = Read-Host "`nEnter your Cloudflare API Token or 0 to go back" -AsSecureString
                    $tokenString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cfToken))
                    if ($tokenString -eq '0')
                    {
                        return
                    }
                    # Validate token format (basic check)
                    if ($tokenString.Length -ge 40 -and $tokenString -match '^[a-zA-Z0-9_-]+$')
                    {
                        break
                    } else
                    {
                        Write-Warning -Message "Invalid token format. Cloudflare API tokens are typically 40+ characters of letters, numbers, underscores, and hyphens."
                    }
                } while ($true)
                $cfCredential = New-Object System.Management.Automation.PSCredential ('CFToken', $cfToken)
                Set-SecureCredential -ProviderName 'Cloudflare' -Credential $cfCredential
            } else
            {
                $cfToken = $cred.Password
            }
            $pluginArgs = @{ CFToken = $cfToken }
        }
        'Route53'
        {
            $awsProfile = Read-Host "`nEnter your AWS profile name (leave blank for default) or 0 to go back"
            if ($awsProfile -eq '0')
            {
                return
            }
            if ($awsProfile)
            {
                $pluginArgs = @{ ProfileName = $awsProfile }
            }
        }
        'Azure'
        {
            Write-Host -Object "`nAuthenticating with Azure..."
            if (-not (Get-Module -ListAvailable -Name Az.Accounts))
            {
                Write-Warning -Message "Az.Accounts module not found. Installing..."
                try
                {
                    Install-Module -Name Az.Accounts -Scope CurrentUser -Force -ErrorAction Stop
                    Import-Module Az.Accounts
                } catch
                {
                    $msg = "Failed to install Az.Accounts module: $($_.Exception.Message)"
                    Write-Error -Message $msg
                    Write-Log $msg -Level 'Error'
                    return
                }
            } else
            {
                Import-Module Az.Accounts
            }
            try
            {
                Invoke-WithRetry -ScriptBlock {
                    Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop
                } -MaxAttempts 3 -InitialDelaySeconds 5 `
                    -OperationName "Azure authentication" `
                    -SuccessCondition { Get-AzContext }
                $azContext = Get-AzContext
                $pluginArgs = @{
                    SubscriptionId = $azContext.Subscription.Id
                    TenantId = $azContext.Tenant.Id
                }
                Write-Information -MessageData "Azure authentication successful." -InformationAction Continue
            } catch
            {
                Write-Error -Message "Failed to authenticate with Azure after multiple attempts: $($_)"
                Write-Log "Failed to authenticate with Azure: $($_)" -Level 'Error'
                return
            }
        }
        'Manual'
        {
            Write-Warning -Message "`nManual challenge selected. You will need to create DNS TXT records manually."
        }
        default
        {
            # Handle other plugins
            Write-Host -Object "`nYou selected the $plugin plugin."
            # Prompt to view plugin's guide
            $viewGuide = Read-Host "`nWould you like to view the $plugin plugin guide? (Y/N)"
            if ($viewGuide -match '^[Yy]$')
            {
                $guideUrl = "https://poshac.me/docs/v4/Plugins/$plugin/"
                Start-Process $guideUrl
            }
            # Retrieve plugin parameter information
            try
            {
                $pluginInfo = Get-PAPlugin -Plugin $plugin
                $pluginParams = $pluginInfo.Params
                if ($pluginParams)
                {
                    Write-Host -Object "`nThe $plugin plugin requires the following parameters:"
                    foreach ($param in $pluginParams)
                    {
                        do
                        {
                            $paramValue = Read-Host -Prompt "`nEnter value for '$param' or type '0' to go back"
                            if ($paramValue -eq '0') { return }
                            $pluginArgs[$param] = $paramValue
                            # Validate parameters if rules exist
                            if (-not (Test-PluginParameters -Plugin $plugin -Parameters $pluginArgs))
                            {
                                Write-Warning -Message "Invalid parameter format. Please try again."
                                $pluginArgs.Remove($param)
                                continue
                            }
                            break
                        } while ($true)
                    }
                } else
                {
                    Write-Host -Object "`nThe $plugin plugin does not require any parameters."
                    $pluginArgs = @{}
                }
            } catch
            {
                Write-Warning -Message "Failed to get plugin information: $($_)"
                $pluginArgs = @{}
            }
        }
    }
    }  # End of DNS-01 configuration block

    Write-ProgressHelper -Activity "Certificate Registration" -Status "Requesting certificate..." -PercentComplete 70
    # Submit certificate order
    Write-Host -Object "`nRequesting certificate for domain(s): $($domains -join ', ')" -ForegroundColor Cyan
    Write-Log "Requesting certificate for domain(s): $($domains -join ', ')"
    try
    {
        if ($plugin -eq 'Manual')
        {
            # Manual challenge handling with circuit breaker protection
            Write-ProgressHelper -Activity "Certificate Registration" -Status "Preparing manual challenge..." -PercentComplete 75
            $cert = Invoke-WithCircuitBreaker -OperationName 'CertificateRenewal' -Operation {
                New-PACertificate -Domain $mainDomain -Plugin $plugin -DnsSleep 0 -Verbose
            }
            Write-Warning -Message "`nPlease create the following DNS TXT records:"
            Write-Warning -Message "=" * 80
            $challengeRecords = @()
            foreach ($authz in $cert.Authorization)
            {
                foreach ($challenge in $authz.Challenges)
                {
                    if ($challenge.Type -eq 'dns-01')
                    {
                        $dnsName = "_acme-challenge." + $authz.Identifier
                        $txtValue = $challenge.DnsDigest
                        Write-Host -Object "$dnsName -> $txtValue" -ForegroundColor White
                        $challengeRecords += @{
                            Name   = $dnsName
                            Value  = $txtValue
                            Domain = $authz.Identifier
                        }
                    }
                }
            }
            Write-Warning -Message "=" * 80
            # DNS propagation checking
            while ($true)
            {
                $continue = Read-Host "`nPress Enter when you have created the DNS records and they have propagated, or type '0' to cancel"
                if ($continue -eq '0')
                {
                    Write-Warning -Message "`nOperation canceled by the user."
                    return
                }
                Write-ProgressHelper -Activity "Certificate Registration" -Status "Verifying DNS propagation..." -PercentComplete 80
                # Test DNS record propagation
                $allRecordsPresent = $true
                $propagationResults = @()
                foreach ($record in $challengeRecords)
                {
                    Write-Host -Object "Checking DNS propagation for $($record.Name)..." -ForegroundColor Cyan
                    $isPropagated = Test-DNSPropagation -DnsName $record.Name -ExpectedValue $record.Value -MaxAttempts 5 -DelaySeconds 10
                    $propagationResults += @{
                        Domain     = $record.Domain
                        DnsName    = $record.Name
                        Expected   = $record.Value
                        Propagated = $isPropagated
                    }
                    if (-not $isPropagated)
                    {
                        $allRecordsPresent = $false
                        Write-Warning -Message "DNS TXT record not found for $($record.Name)"
                    } else
                    {
                        Write-Information -MessageData "OK DNS TXT record found for $($record.Name)" -InformationAction Continue
                    }
                }
                if ($allRecordsPresent)
                {
                    # Proceed with validation using retry logic
                    Write-ProgressHelper -Activity "Certificate Registration" -Status "Validating domain ownership..." -PercentComplete 85
                    try
                    {
                        $validationResult = Invoke-WithRetry -ScriptBlock {
                            Complete-AuthChallenge -AuthChain $cert -DnsSleep 0 -Verbose
                            # Check authorization status
                            $allValid = $true
                            foreach ($authz in $cert.Authorization)
                            {
                                $status = Get-PAAuthorization -AuthUrl $authz.location -Verbose
                                if ($status.status -ne 'valid')
                                {
                                    $allValid = $false
                                    Write-Error -Message "Authorization failed for domain $($authz.Identifier). Status: $($status.status)"
                                    break
                                }
                            }
                            return $allValid
                        } -MaxAttempts 3 -InitialDelaySeconds 30 `
                            -OperationName "Domain validation" `
                            -SuccessCondition { $_ -eq $true }
                        if ($validationResult)
                        {
                            Write-Information -MessageData "`nAll domain validations completed!" -InformationAction Continue
                            Write-Log "All domain validations completed."
                            break
                        }
                    } catch
                    {
                        Write-Error -Message "`nValidation failed: $($_)"
                        Write-Log "Validation failed during manual challenge: $($_)" -Level 'Error'
                        $retry = Read-Host "`nWould you like to retry validation? (Y/N)"
                        if ($retry -notmatch '^[Yy]$')
                        {
                            Write-Warning -Message "`nReturning to the main menu"
                            return
                        }
                    }
                } else
                {
                    Write-Warning -Message "`nDNS Propagation Summary:"
                    foreach ($result in $propagationResults)
                    {
                        $status = if ($result.Propagated) { "OK READY" } else { "X PENDING" }
                        $color = if ($result.Propagated) { "Green" } else { "Red" }
                        Write-Host -Object "  $($result.Domain): $status" -ForegroundColor $color
                    }
                    Write-Warning -Message "`nPlease wait a few minutes for DNS propagation and try again."
                    Write-Host -Object "Note: DNS propagation can take up to 15 minutes depending on your provider." -ForegroundColor Gray
                }
            }
            # Final certificate retrieval and verification
            Write-ProgressHelper -Activity "Certificate Registration" -Status "Finalizing certificate..." -PercentComplete 90
            try
            {
                $cert = Invoke-WithRetry -ScriptBlock {
                    Get-PACertificate -MainDomain $mainDomain -ErrorAction Stop
                } -MaxAttempts 5 -InitialDelaySeconds 10 `
                    -OperationName "Certificate retrieval" `
                    -SuccessCondition { $null -ne $_.Certificate }
                if (-not $cert.Certificate)
                {
                    Write-Error -Message "`nCertificate was not issued. Please check the Let's Encrypt logs."
                    Write-Log "Certificate was not issued for $mainDomain" -Level 'Error'
                    Read-Host "`nPress Enter to return to the main menu"
                    return
                }
                # Display certificate details
                Write-Information -MessageData "`nCertificate issued!" -InformationAction Continue
                Write-Host -Object "Subject: $($cert.Certificate.Subject)" -ForegroundColor Cyan
                Write-Host -Object "Issuer: $($cert.Certificate.Issuer)" -ForegroundColor Cyan
                Write-Host -Object "Valid Until: $($cert.Certificate.NotAfter)" -ForegroundColor Cyan
                Write-Host -Object "Thumbprint: $($cert.Certificate.Thumbprint)" -ForegroundColor Cyan
                Write-Log "Certificate issued for $mainDomain, valid until $($cert.Certificate.NotAfter)"
            } catch
            {
                Write-Error -Message "`nFailed to retrieve issued certificate: $($_)"
                Write-Log "Failed to retrieve issued certificate for ${mainDomain}: $($_)" -Level 'Error'
                Read-Host "`nPress Enter to return to the main menu"
                return
            }
        } else
        {
            # Automated challenge handling with circuit breaker and retry protection
            Write-ProgressHelper -Activity "Certificate Registration" -Status "Processing automated challenge..." -PercentComplete 75
            $cert = Invoke-WithCircuitBreaker -OperationName 'CertificateRenewal' -Operation {
                Invoke-WithRetry -ScriptBlock {
                    # Use -Force to overwrite existing orders
                    New-PACertificate -Domain $mainDomain -Plugin $plugin -PluginArgs $pluginArgs -Force -Verbose
                } -MaxAttempts 3 -InitialDelaySeconds 30 `
                    -OperationName "Certificate acquisition" `
                    -SuccessCondition {
                    $_ -and ($_.CertFile -or $_.FullChainFile -or $_.PfxFile)
                }
            }
            # Verify certificate was obtained
            if (-not $cert -or (-not $cert.CertFile -and -not $cert.FullChainFile -and -not $cert.PfxFile))
            {
                Write-Error -Message "`nFailed to obtain the certificate. Please check the output above for errors."
                Write-Log "Failed to obtain the certificate for $mainDomain" -Level 'Error'
                Read-Host "`nPress Enter to return to the main menu"
                return
            }
            Write-Information -MessageData "`nCertificate obtained!" -InformationAction Continue
            Write-Log "Certificate obtained for $mainDomain"
        }
        Write-ProgressHelper -Activity "Certificate Registration" -Status "Certificate ready for installation" -PercentComplete 95
        # Call Install-Certificate function to handle installation options
        Write-Host -Object "`nProceeding to certificate installation..." -ForegroundColor Cyan
        Install-Certificate -PACertificate $cert
    } catch
    {
        Write-Error -Message "`nAn error occurred during certificate request: $($_)"
        Write-Log "An error occurred during certificate request: $($_)" -Level 'Error'
        # Provide helpful troubleshooting information
        Write-Warning -Message "`nTroubleshooting Tips:"
        Write-Host -Object "1. Verify your DNS provider credentials are correct"
        Write-Host -Object "2. Check that your domain's DNS is properly configured"
        Write-Host -Object "3. Ensure the domain is publicly resolvable"
        Write-Host -Object "4. Check your internet connection"
        Write-Host -Object "5. Try again in a few minutes"
    } finally
    {
        Write-Progress -Activity "Certificate Registration" -Completed
    }
    Read-Host "`nPress Enter to return to the main menu"
}


