# Enhanced Functions/Register-Certificate.ps1
<#
    .SYNOPSIS
        Enhanced certificate registration with comprehensive DNS provider support,
        robust error handling, and advanced validation.
#>

function Register-Certificate {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param (
        [Parameter()]
        [switch]$Force
    )

    # Ensure ACME server is set
    Initialize-ACMEServer

    # Load public suffix list for accurate domain parsing
    Write-ProgressHelper -Activity "Certificate Registration" -Status "Loading domain database..." -PercentComplete 5
    $publicSuffixes = Get-PublicSuffixList

    # Load user settings
    $settings = Get-ScriptSettings

    # Prompt for domain name with validation
    do {
        $domain = Read-Host "`nEnter the domain name (e.g., server.domain.com) or 0 to go back"
        if ($domain -eq '0') {
            return
        }
        
        if (Test-ValidDomain -Domain $domain) {
            break
        }
        Write-Warning "Please enter a valid domain name."
    } while ($true)

    Write-ProgressHelper -Activity "Certificate Registration" -Status "Analyzing domain structure..." -PercentComplete 15

    # Extract base domain using public suffix list
    $baseDomain = Get-BaseDomain -domainName $domain -Suffixes $publicSuffixes
    Write-Verbose "Base domain identified: $baseDomain"

    # Initialize variables
    $mainDomain = $domain
    $domains = @()

    # Ask for certificate type with enhanced options
    while ($true) {
        Write-Host "`nSelect the type of certificate you want to create:"
        Write-Host "1) Server-specific certificate for $domain"
        Write-Host "2) Wildcard certificate for *.$baseDomain"
        Write-Host "3) Multi-domain certificate (SAN)"
        Write-Host "0) Back"
        
        $certTypeChoice = Get-ValidatedInput -Prompt "`nEnter the number corresponding to your choice (0-3)" -ValidOptions 1,2,3
        
        switch ($certTypeChoice) {
            0 { return }
            1 {
                $mainDomain = $domain
                $domains = @($mainDomain)
                break
            }
            2 {
                $mainDomain = "*.$baseDomain"
                $domains = @($mainDomain)
                break
            }
            3 {
                # Multi-domain certificate
                $domains = @($domain)  # Start with main domain
                
                while ($true) {
                    $additionalDomain = Read-Host "`nEnter additional domain (or press Enter to finish, 0 to cancel)"
                    if ($additionalDomain -eq '0') {
                        return
                    }
                    if ([string]::IsNullOrWhiteSpace($additionalDomain)) {
                        break
                    }
                    if (Test-ValidDomain -Domain $additionalDomain) {
                        if ($domains -notcontains $additionalDomain) {
                            $domains += $additionalDomain
                            Write-Host "Added: $additionalDomain" -ForegroundColor Green
                        } else {
                            Write-Warning "Domain already added: $additionalDomain"
                        }
                    } else {
                        Write-Warning "Invalid domain format: $additionalDomain"
                    }
                }
                $mainDomain = $domains[0]  # First domain is main domain
                break
            }
        }
        
        if ($domains.Count -gt 0) {
            break
        }
    }

    Write-Host "`nCertificate will be issued for:" -ForegroundColor Cyan
    $domains | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }

    Write-ProgressHelper -Activity "Certificate Registration" -Status "Detecting DNS provider..." -PercentComplete 25

    # Attempt to auto-detect DNS provider
    $dnsProvider = Get-DNSProvider -Domain $baseDomain
    $plugin = $null

    if ($dnsProvider.Name -ne "Unknown") {
        Write-Host "`nDetected DNS provider: $($dnsProvider.Name) (Confidence: $($dnsProvider.Confidence))" -ForegroundColor Green
        Write-Log "Detected DNS provider: $($dnsProvider.Name)"
        
        if ($dnsProvider.Confidence -eq "High") {
            $useDetected = Read-Host "`nUse detected provider $($dnsProvider.Name)? (Y/N)"
            if ($useDetected -match '^[Yy]$') {
                $plugin = $dnsProvider.Plugin
            }
        }
    } else {
        Write-Warning "`nDNS provider could not be automatically detected."
        if ($dnsProvider.NSRecords.Count -gt 0) {
            Write-Host "Detected NS records:" -ForegroundColor Cyan
            $dnsProvider.NSRecords | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
        }
    }

    # If DNS provider not detected or user declined, prompt for manual selection
    if (-not $plugin) {
        $pluginSelected = $false
        while (-not $pluginSelected) {
            Write-Host "`nSelect the challenge plugin:"
            Write-Host "1) DNS - Cloudflare"
            Write-Host "2) DNS - AWS Route53"
            Write-Host "3) DNS - Azure"
            Write-Host "4) DNS - Google Cloud"
            Write-Host "5) DNS - DigitalOcean"
            Write-Host "6) Manual (default)"
            Write-Host "7) Other DNS Plugin"
            Write-Host "0) Back"
            
            $pluginOption = Get-ValidatedInput -Prompt "`nEnter the corresponding number (0-7)" -ValidOptions 1,2,3,4,5,6,7
            
            switch ($pluginOption) {
                0 { return }
                1 { $plugin = 'Cloudflare'; $pluginSelected = $true }
                2 { $plugin = 'Route53'; $pluginSelected = $true }
                3 { $plugin = 'Azure'; $pluginSelected = $true }
                4 { $plugin = 'GoogleDomains'; $pluginSelected = $true }
                5 { $plugin = 'DigitalOcean'; $pluginSelected = $true }
                6 { $plugin = 'Manual'; $pluginSelected = $true }
                7 {
                    # List all available DNS plugins
                    $plugins = @(Get-PAPlugin | Where-Object { $_.ChallengeType -eq 'dns-01' })
                    if ($plugins.Count -eq 0) {
                        Write-Warning "`nNo DNS plugins are available."
                        $plugin = 'Manual'
                        $pluginSelected = $true
                    } else {
                        $dnsPluginSelected = $false
                        while (-not $dnsPluginSelected) {
                            Write-Host "`nAvailable DNS Plugins:"
                            $i = 1
                            foreach ($p in $plugins) {
                                Write-Host "$i) $($p.Name)"
                                $i++
                            }
                            Write-Host "0) Back"
                            
                            $pluginSelection = Get-ValidatedInput -Prompt "`nEnter the number corresponding to your choice" -ValidOptions (1..$plugins.Count)
                            if ($pluginSelection -eq 0) {
                                break
                            } else {
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

    Write-ProgressHelper -Activity "Certificate Registration" -Status "Configuring ACME account..." -PercentComplete 40

    # Ensure an ACME account exists
    if (-not (Get-PAAccount)) {
        Write-Host "`nNo ACME account found. Creating a new account..."
        
        $email = $settings.LastUsedEmail
        if (-not $email -or -not (Test-ValidEmail -Email $email)) {
            do {
                $email = Read-Host "`nEnter your email address for Let's Encrypt notifications or 0 to go back"
                if ($email -eq '0') {
                    return
                }
            } while (-not (Test-ValidEmail -Email $email))
        } else {
            $useStoredEmail = Read-Host "`nUse stored email address ($email)? (Y/N)"
            if ($useStoredEmail -notmatch '^[Yy]$') {
                do {
                    $email = Read-Host "`nEnter your email address for Let's Encrypt notifications or 0 to go back"
                    if ($email -eq '0') {
                        return
                    }
                } while (-not (Test-ValidEmail -Email $email))
            }
        }

        try {
            Invoke-WithRetry -ScriptBlock {
                New-PAAccount -AcceptTOS -Contact $email -ErrorAction Stop
            } -MaxAttempts 3 -InitialDelaySeconds 5 `
              -OperationName "ACME account creation"

            Write-Host "`nACME account created successfully." -ForegroundColor Green
            Write-Log "ACME account created with email: $email"
            
            # Save email for future use
            $settings.LastUsedEmail = $email
            Save-ScriptSettings -Settings $settings
            
        } catch {
            Write-Error "Failed to create ACME account after multiple attempts: $($_)"
            Write-Log "Failed to create ACME account: $($_)" -Level 'Error'
            return
        }
    }

    Write-ProgressHelper -Activity "Certificate Registration" -Status "Configuring DNS plugin..." -PercentComplete 55

    # Initialize plugin arguments
    $pluginArgs = @{}

    # Handle plugin-specific authentication with enhanced error handling
    switch ($plugin) {
        'Cloudflare' {
            $cred = Get-SecureCredential -ProviderName 'Cloudflare'
            if (-not $cred) {
                Write-Host "`nCloudflare credentials not found. Opening browser for API token creation..." -ForegroundColor Cyan
                Start-Process "https://dash.cloudflare.com/profile/api-tokens"
                
                Write-Host "`nPlease follow these steps to create an API Token:`n" -ForegroundColor Cyan
                Write-Host "1. Log in to your Cloudflare account."
                Write-Host "2. Navigate to 'My Profile' > 'API Tokens'."
                Write-Host "3. Click 'Create Token'."
                Write-Host "4. Select 'Create Custom Token'."
                Write-Host "5. In the 'Permissions' section, add:"
                Write-Host "   - Zone:DNS:Edit"
                Write-Host "6. In the 'Zone Resources' section:"
                Write-Host "   - Include: All zones (or specify your zone)"
                Write-Host "7. Give your token a name and click 'Continue to summary'."
                Write-Host "8. Review and click 'Create Token'."
                Write-Host "9. Copy the API Token displayed.`n"

                do {
                    $cfToken = Read-Host "`nEnter your Cloudflare API Token or 0 to go back" -AsSecureString
                    $tokenString = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cfToken))
                    
                    if ($tokenString -eq '0') {
                        return
                    }
                    
                    # Validate token format (basic check)
                    if ($tokenString.Length -ge 40 -and $tokenString -match '^[a-zA-Z0-9_-]+$') {
                        break
                    } else {
                        Write-Warning "Invalid token format. Cloudflare API tokens are typically 40+ characters of letters, numbers, underscores, and hyphens."
                    }
                } while ($true)

                $cfCredential = New-Object System.Management.Automation.PSCredential ('CFToken', $cfToken)
                Set-SecureCredential -ProviderName 'Cloudflare' -Credential $cfCredential
            } else {
                $cfToken = $cred.Password
            }
            $pluginArgs = @{ CFToken = $cfToken }
        }
        
        'Route53' {
            $awsProfile = Read-Host "`nEnter your AWS profile name (leave blank for default) or 0 to go back"
            if ($awsProfile -eq '0') {
                return
            }
            if ($awsProfile) { 
                $pluginArgs = @{ ProfileName = $awsProfile }
            }
        }
        
        'Azure' {
            Write-Host "`nAuthenticating with Azure..."
            if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
                Write-Host "Az.Accounts module not found. Installing..." -ForegroundColor Yellow
                try {
                    Install-Module -Name Az.Accounts -Scope CurrentUser -Force -ErrorAction Stop
                    Import-Module Az.Accounts
                } catch {
                    $msg = "Failed to install Az.Accounts module: $($_.Exception.Message)"
                    Write-Error $msg
                    Write-Log $msg -Level 'Error'
                    return
                }
            } else {
                Import-Module Az.Accounts
            }

            try {
                Invoke-WithRetry -ScriptBlock {
                    Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop
                } -MaxAttempts 3 -InitialDelaySeconds 5 `
                  -OperationName "Azure authentication" `
                  -SuccessCondition { Get-AzContext }

                $azContext = Get-AzContext
                $pluginArgs = @{
                    SubscriptionId = $azContext.Subscription.Id
                    TenantId       = $azContext.Tenant.Id
                }
                Write-Host "Azure authentication successful." -ForegroundColor Green
            } catch {
                Write-Error "Failed to authenticate with Azure after multiple attempts: $($_)"
                Write-Log "Failed to authenticate with Azure: $($_)" -Level 'Error'
                return
            }
        }
        
        'Manual' {
            Write-Host "`nManual challenge selected. You will need to create DNS TXT records manually." -ForegroundColor Yellow
        }
        
        default {
            # Handle other plugins with enhanced parameter collection
            Write-Host "`nYou selected the $plugin plugin."
            
            # Prompt to view plugin's guide
            $viewGuide = Read-Host "`nWould you like to view the $plugin plugin guide? (Y/N)"
            if ($viewGuide -match '^[Yy]$') {
                $guideUrl = "https://poshac.me/docs/v4/Plugins/$plugin/"
                Start-Process $guideUrl
            }

            # Retrieve plugin parameter information
            try {
                $pluginInfo = Get-PAPlugin -Plugin $plugin
                $pluginParams = $pluginInfo.Params

                if ($pluginParams) {
                    Write-Host "`nThe $plugin plugin requires the following parameters:"
                    
                    foreach ($param in $pluginParams) {
                        do {
                            $paramValue = Read-Host -Prompt "`nEnter value for '$param' or type '0' to go back"
                            if ($paramValue -eq '0') { return }
                            
                            $pluginArgs[$param] = $paramValue

                            # Validate parameters if rules exist
                            if (-not (Test-PluginParameters -Plugin $plugin -Parameters $pluginArgs)) {
                                Write-Warning "Invalid parameter format. Please try again."
                                $pluginArgs.Remove($param)
                                continue
                            }
                            break
                        } while ($true)
                    }
                } else {
                    Write-Host "`nThe $plugin plugin does not require any parameters."
                    $pluginArgs = @{}
                }
            } catch {
                Write-Warning "Failed to get plugin information: $($_)"
                $pluginArgs = @{}
            }
        }
    }

    Write-ProgressHelper -Activity "Certificate Registration" -Status "Requesting certificate..." -PercentComplete 70

    # Submit certificate order
    Write-Host "`nRequesting certificate for domain(s): $($domains -join ', ')" -ForegroundColor Cyan
    Write-Log "Requesting certificate for domain(s): $($domains -join ', ')"

    try {
        if ($plugin -eq 'Manual') {
            # Enhanced manual challenge handling
            Write-ProgressHelper -Activity "Certificate Registration" -Status "Preparing manual challenge..." -PercentComplete 75
            
            $cert = New-PACertificate -Domain $mainDomain -Plugin $plugin -DnsSleep 0 -Verbose

            Write-Host "`nPlease create the following DNS TXT records:" -ForegroundColor Yellow
            Write-Host "=" * 80 -ForegroundColor Yellow
            
            $challengeRecords = @()
            foreach ($authz in $cert.Authorization) {
                foreach ($challenge in $authz.Challenges) {
                    if ($challenge.Type -eq 'dns-01') {
                        $dnsName = "_acme-challenge." + $authz.Identifier
                        $txtValue = $challenge.DnsDigest
                        Write-Host "$dnsName -> $txtValue" -ForegroundColor White
                        $challengeRecords += @{
                            Name = $dnsName
                            Value = $txtValue
                            Domain = $authz.Identifier
                        }
                    }
                }
            }
            Write-Host "=" * 80 -ForegroundColor Yellow

            # Enhanced DNS propagation checking
            while ($true) {
                $continue = Read-Host "`nPress Enter when you have created the DNS records and they have propagated, or type '0' to cancel"
                if ($continue -eq '0') {
                    Write-Warning "`nOperation canceled by the user."
                    return
                }

                Write-ProgressHelper -Activity "Certificate Registration" -Status "Verifying DNS propagation..." -PercentComplete 80

                # Test DNS record propagation with enhanced checking
                $allRecordsPresent = $true
                $propagationResults = @()
                
                foreach ($record in $challengeRecords) {
                    Write-Host "Checking DNS propagation for $($record.Name)..." -ForegroundColor Cyan
                    
                    $isPropagated = Test-DNSPropagation -DnsName $record.Name -ExpectedValue $record.Value -MaxAttempts 5 -DelaySeconds 10
                    
                    $propagationResults += @{
                        Domain = $record.Domain
                        DnsName = $record.Name
                        Expected = $record.Value
                        Propagated = $isPropagated
                    }
                    
                    if (-not $isPropagated) {
                        $allRecordsPresent = $false
                        Write-Warning "DNS TXT record not found for $($record.Name)"
                    } else {
                        Write-Host "✓ DNS TXT record found for $($record.Name)" -ForegroundColor Green
                    }
                }

                if ($allRecordsPresent) {
                    # Proceed with validation using enhanced retry logic
                    Write-ProgressHelper -Activity "Certificate Registration" -Status "Validating domain ownership..." -PercentComplete 85
                    
                    try {
                        $validationResult = Invoke-WithRetry -ScriptBlock {
                            Complete-AuthChallenge -AuthChain $cert -DnsSleep 0 -Verbose
                            
                            # Check authorization status
                            $allValid = $true
                            foreach ($authz in $cert.Authorization) {
                                $status = Get-PAAuthorization -AuthUrl $authz.location -Verbose
                                if ($status.status -ne 'valid') {
                                    $allValid = $false
                                    Write-Error "Authorization failed for domain $($authz.Identifier). Status: $($status.status)"
                                    break
                                }
                            }
                            return $allValid
                        } -MaxAttempts 3 -InitialDelaySeconds 30 `
                          -OperationName "Domain validation" `
                          -SuccessCondition { $_ -eq $true }

                        if ($validationResult) {
                            Write-Host "`nAll domain validations completed successfully!" -ForegroundColor Green
                            Write-Log "All domain validations completed successfully."
                            break
                        }
                    } catch {
                        Write-Error "`nValidation failed: $($_)"
                        Write-Log "Validation failed during manual challenge: $($_)" -Level 'Error'
                        
                        $retry = Read-Host "`nWould you like to retry validation? (Y/N)"
                        if ($retry -notmatch '^[Yy]$') {
                            Write-Warning "`nReturning to the main menu"
                            return
                        }
                    }
                } else {
                    Write-Host "`nDNS Propagation Summary:" -ForegroundColor Yellow
                    foreach ($result in $propagationResults) {
                        $status = if ($result.Propagated) { "✓ READY" } else { "✗ PENDING" }
                        $color = if ($result.Propagated) { "Green" } else { "Red" }
                        Write-Host "  $($result.Domain): $status" -ForegroundColor $color
                    }
                    
                    Write-Host "`nPlease wait a few minutes for DNS propagation and try again." -ForegroundColor Yellow
                    Write-Host "Note: DNS propagation can take up to 15 minutes depending on your provider." -ForegroundColor Gray
                }
            }

            # Final certificate retrieval and verification
            Write-ProgressHelper -Activity "Certificate Registration" -Status "Finalizing certificate..." -PercentComplete 90
            
            try {
                $cert = Invoke-WithRetry -ScriptBlock {
                    Get-PACertificate -MainDomain $mainDomain -ErrorAction Stop
                } -MaxAttempts 5 -InitialDelaySeconds 10 `
                  -OperationName "Certificate retrieval" `
                  -SuccessCondition { $null -ne $_.Certificate }

                if (-not $cert.Certificate) {
                    Write-Error "`nCertificate was not issued successfully. Please check the Let's Encrypt logs."
                    Write-Log "Certificate was not issued for $mainDomain" -Level 'Error'
                    Read-Host "`nPress Enter to return to the main menu"
                    return
                }

                # Display certificate details
                Write-Host "`nCertificate issued successfully!" -ForegroundColor Green
                Write-Host "Subject: $($cert.Certificate.Subject)" -ForegroundColor Cyan
                Write-Host "Issuer: $($cert.Certificate.Issuer)" -ForegroundColor Cyan
                Write-Host "Valid Until: $($cert.Certificate.NotAfter)" -ForegroundColor Cyan
                Write-Host "Thumbprint: $($cert.Certificate.Thumbprint)" -ForegroundColor Cyan
                
                Write-Log "Certificate issued successfully for $mainDomain, valid until $($cert.Certificate.NotAfter)"
                
            } catch {
                Write-Error "`nFailed to retrieve issued certificate: $($_)"
                Write-Log "Failed to retrieve issued certificate for ${mainDomain}: $($_)" -Level 'Error'
                Read-Host "`nPress Enter to return to the main menu"
                return
            }
        } else {
            # Automated challenge handling with enhanced error handling
            Write-ProgressHelper -Activity "Certificate Registration" -Status "Processing automated challenge..." -PercentComplete 75
            
            $cert = Invoke-WithRetry -ScriptBlock {
                # Use -Force to overwrite existing orders
                New-PACertificate -Domain $mainDomain -Plugin $plugin -PluginArgs $pluginArgs -Force -Verbose
            } -MaxAttempts 3 -InitialDelaySeconds 30 `
              -OperationName "Certificate acquisition" `
              -SuccessCondition { 
                $_ -and ($_.CertFile -or $_.FullChainFile -or $_.PfxFile)
              }

            # Verify certificate was obtained
            if (-not $cert -or (-not $cert.CertFile -and -not $cert.FullChainFile -and -not $cert.PfxFile)) {
                Write-Error "`nFailed to obtain the certificate. Please check the output above for errors."
                Write-Log "Failed to obtain the certificate for $mainDomain" -Level 'Error'
                Read-Host "`nPress Enter to return to the main menu"
                return
            }

            Write-Host "`nCertificate obtained successfully!" -ForegroundColor Green
            Write-Log "Certificate obtained successfully for $mainDomain"
        }

        Write-ProgressHelper -Activity "Certificate Registration" -Status "Certificate ready for installation" -PercentComplete 95

        # Call Install-Certificate function to handle installation options
        Write-Host "`nProceeding to certificate installation..." -ForegroundColor Cyan
        Install-Certificate -PACertificate $cert

    } catch {
        Write-Error "`nAn error occurred during certificate request: $($_)"
        Write-Log "An error occurred during certificate request: $($_)" -Level 'Error'
        
        # Provide helpful troubleshooting information
        Write-Host "`nTroubleshooting Tips:" -ForegroundColor Yellow
        Write-Host "1. Verify your DNS provider credentials are correct"
        Write-Host "2. Check that your domain's DNS is properly configured"
        Write-Host "3. Ensure the domain is publicly resolvable"
        Write-Host "4. Check your internet connection"
        Write-Host "5. Try again in a few minutes"
        
    } finally {
        Write-Progress -Activity "Certificate Registration" -Completed
    }
    
    Read-Host "`nPress Enter to return to the main menu"
}
