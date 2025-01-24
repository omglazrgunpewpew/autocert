<#
    .SYNOPSIS
        Handles the registration of a new TLS certificate, including domain validation
        and plugin configuration.
#>

function Register-Certificate {
    # Ensure the ACME server is set
    Initialize-ACMEServer

    # Prompt for domain name
    $domain = Read-Host "`nEnter the domain name (e.g., server.domain.com) or 0 to go back"
    if ($domain -eq '0') {
        return
    }

    # Validate domain name format
    if (-not $domain -or $domain -notmatch '^[a-zA-Z0-9.-]+$') {
        Write-Host "Invalid domain name format." -ForegroundColor Yellow
        return
    }

    # Extract base domain using Posh-ACME built-in
    $baseDomain = Get-BaseDomain -domainName $domain

    # Ask for server-specific vs wildcard
    while ($true) {
        Write-Host "`nSelect the type of certificate to create:"
        Write-Host "1) Server-specific certificate for $domain"
        Write-Host "2) Wildcard certificate for *.$baseDomain"
        Write-Host "0) Back"
        $certTypeChoice = Get-ValidatedInput -Prompt "`nEnter your choice (0-2)" -ValidOptions 1,2
        if ($certTypeChoice -eq 0) {
            return
        } elseif ($certTypeChoice -eq 1) {
            $mainDomain = $domain
            break
        } elseif ($certTypeChoice -eq 2) {
            $mainDomain = "*.$baseDomain"
            break
        }
    }

    # Attempt to auto-detect DNS provider from NS records
    $plugin = $null
    Write-Host "`nDetecting DNS provider for $baseDomain..."
    try {
        $nsRecords = (Resolve-DnsName -Name $baseDomain -Type NS -ErrorAction Stop).NameHost
        foreach ($ns in $nsRecords) {
            if    ($ns -like "*.cloudflare.com") { $plugin = 'Cloudflare'; break }
            elseif($ns -like "*.awsdns-*.*.amazonaws.com") { $plugin = 'Route53'; break }
            elseif($ns -like "*.azure-dns*.info" -or
                   $ns -like "*.azure-dns*.org"  -or
                   $ns -like "*.azure-dns*.com"  -or
                   $ns -like "*.azure-dns*.net") { $plugin = 'Azure'; break }
            elseif($ns -like "*.googledomains.com") { $plugin = 'GoogleDomains'; break }
            elseif($ns -like "*.digitalocean.com")  { $plugin = 'DigitalOcean'; break }
            elseif($ns -like "*.dnsmadeeasy.com")    { $plugin = 'DNSMadeEasy'; break }
            # Add more providers as needed
        }
    } catch {
        Write-Host "Failed to retrieve NS records for ${baseDomain}: $($_)" -ForegroundColor Yellow
        Write-Log "Failed to retrieve NS records for ${baseDomain}: $($_)" -Level 'Warning'
    }

    if ($plugin) {
        Write-Host "`nDetected DNS provider: $plugin" -ForegroundColor Green
        Write-Log "Detected DNS provider: $plugin"
    } else {
        Write-Host "DNS provider could not be automatically detected." -ForegroundColor Yellow
    }

    # If DNS provider not detected, prompt user
    if (-not $plugin) {
        Write-Host "`nSelect the challenge plugin:"
        Write-Host "1) DNS - Cloudflare"
        Write-Host "2) DNS - AWS Route53"
        Write-Host "3) DNS - Azure"
        Write-Host "4) Manual (default)"
        Write-Host "5) Other DNS Plugin"
        Write-Host "0) Back"
        $pluginOption = Get-ValidatedInput -Prompt "`nEnter your choice (0-5)" -ValidOptions 1,2,3,4,5
        switch ($pluginOption) {
            0 { return }
            1 { $plugin = 'Cloudflare' }
            2 { $plugin = 'Route53' }
            3 { $plugin = 'Azure' }
            4 { $plugin = 'Manual' }
            5 {
                $plugins = Get-PAPlugin | Where-Object { $_.ChallengeType -eq 'dns-01' }
                if ($plugins.Count -eq 0) {
                    Write-Host "No DNS plugins are available." -ForegroundColor Yellow
                    $plugin = 'Manual'
                } else {
                    while ($true) {
                        Write-Host "`nAvailable DNS Plugins:"
                        $i = 1
                        foreach ($p in $plugins) {
                            Write-Host "$i) $($p.Name)"
                            $i++
                        }
                        Write-Host "0) Back"
                        $sel = Get-ValidatedInput -Prompt "`nEnter the number corresponding to your choice" -ValidOptions (1..$plugins.Count)
                        if ($sel -eq 0) {
                            return
                        } else {
                            $plugin = $plugins[$sel - 1].Name
                            break
                        }
                    }
                }
            }
        }
    }

    # Ensure an ACME account exists
    if (-not (Get-PAAccount)) {
        Write-Host "`nNo ACME account found. Creating a new account..."
        $email = Read-Host "`nEnter your email address for Let's Encrypt notifications or 0 to go back"
        if ($email -eq '0') {
            return
        }
        try {
            New-PAAccount -AcceptTOS -Contact $email -ErrorAction Stop
            Write-Host "`nACME account created."
            Write-Log "ACME account created with email: $email"
        } catch {
            Write-Host "Failed to create ACME account: $($_)" -ForegroundColor Red
            Write-Log "Failed to create ACME account: $($_)" -Level 'Error'
            return
        }
    }

    # Initialize plugin arguments
    $pluginArgs = @{}

    # Handle plugin-specific auth
    switch ($plugin) {
        'Cloudflare' {
            $cred = Get-SecureCredential -ProviderName 'Cloudflare'
            if (-not $cred) {
                Write-Host "`nCloudflare credentials not found. Opening browser for API token creation..."
                Start-Process "https://dash.cloudflare.com/profile/api-tokens"
                Write-Host "`nPlease follow these steps to create an API Token (Zone:DNS:Edit) then enter it here."

                $cfToken = Read-Host "`nEnter your Cloudflare API Token or 0 to go back" -AsSecureString
                if (([System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($cfToken))
                    ) -eq '0') {
                    return
                }
                $cfCredential = New-Object System.Management.Automation.PSCredential ('CFToken', $cfToken)
                Set-SecureCredential -ProviderName 'Cloudflare' -Credential $cfCredential
                $pluginArgs = @{ CFToken = $cfToken }
            } else {
                $pluginArgs = @{ CFToken = $cred.Password }
            }
        }
        'Route53' {
            $awsProfile = Read-Host "`nEnter your AWS profile name (leave blank for default) or 0 to go back"
            if ($awsProfile -eq '0') {
                return
            }
            if ($awsProfile) { $pluginArgs = @{ ProfileName = $awsProfile } }
        }
        'Azure' {
            # For older machines, we can do interactive
            Write-Host "`nAuthenticating with Azure..."
            if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
                Write-Host "Az.Accounts module not found. Installing..."
                try {
                    Install-Module -Name Az.Accounts -Scope CurrentUser -Force -ErrorAction Stop
                    Import-Module Az.Accounts -ErrorAction Stop
                } catch {
                    Write-Host "Failed to install Az.Accounts module: $($_)" -ForegroundColor Red
                    Write-Log "Failed to install Az.Accounts module: $($_)" -Level 'Error'
                    return
                }
            } else {
                Import-Module Az.Accounts -ErrorAction Stop
            }

            try {
                Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop
                $azContext = Get-AzContext
                $pluginArgs = @{
                    SubscriptionId = $azContext.Subscription.Id
                    TenantId       = $azContext.Tenant.Id
                }
            } catch {
                Write-Host "Failed to authenticate with Azure: $($_)" -ForegroundColor Red
                Write-Log "Failed to authenticate with Azure: $($_)" -Level 'Error'
                return
            }
        }
        'Manual' {
            Write-Host "`nManual challenge selected. You will need to create DNS TXT records manually."
        }
        default {
            # "Other" plugin
            Write-Host "`nYou selected the $plugin plugin."
            # Prompt to view the plugin’s guide
            $viewGuide = Read-Host "`nWould you like to view the $plugin plugin guide? (Y/N)"
            if ($viewGuide -match '^(Y|y)$') {
                $guideUrl = "https://poshac.me/docs/v4/Plugins/$plugin/"
                Start-Process $guideUrl
            }

            # Retrieve plugin parameter info
            $pluginInfo = Get-PAPlugin -Plugin $plugin
            $pluginParams = $pluginInfo.Params

            if ($pluginParams) {
                Write-Host "`nThe $plugin plugin requires the following parameters:"
                foreach ($param in $pluginParams) {
                    $paramValue = Read-Host "`nEnter value for '$param' or 0 to go back"
                    if ($paramValue -eq '0') {
                        return
                    }
                    $pluginArgs[$param] = $paramValue
                }
            } else {
                Write-Host "`nThe $plugin plugin does not require any parameters."
            }
        }
    }

    # Request the certificate
    Write-Host "`nRequesting certificate for domain: $mainDomain"
    Write-Log "Requesting certificate for domain: $mainDomain"

    try {
        if ($plugin -eq 'Manual') {
            # Manual challenge handling
            $cert = New-PACertificate -Domain $mainDomain -Plugin $plugin -DnsSleep 0 -Verbose

            Write-Host "`nPlease create the following DNS TXT records (if any) before continuing:"
            Write-Host "-------------------------------------------------"
            foreach ($authz in $cert.Authorization) {
                foreach ($challenge in $authz.Challenges) {
                    if ($challenge.Type -eq 'dns-01') {
                        $dnsName  = "_acme-challenge." + $authz.Identifier
                        $txtValue = $challenge.DnsDigest
                        Write-Host "$dnsName -> $txtValue"
                    }
                }
            }
            Write-Host "-------------------------------------------------"

            while ($true) {
                $continue = Read-Host "`nPress Enter when DNS records are created, or type '0' to cancel"
                if ($continue -eq '0') {
                    Write-Host "`nOperation canceled." -ForegroundColor Yellow
                    return
                }

                # Check DNS records
                $allRecordsPresent = $true
                foreach ($authz in $cert.Authorization) {
                    $dnsName = "_acme-challenge." + $authz.Identifier
                    try {
                        $dnsRecord = (Resolve-DnsName -Name $dnsName -Type TXT -ErrorAction Stop).Strings
                        Write-Host "Found DNS TXT record for ${dnsName}: $dnsRecord" -ForegroundColor Green
                    } catch {
                        Write-Host "DNS TXT record not found for $dnsName. Please wait for propagation." -ForegroundColor Yellow
                        $allRecordsPresent = $false
                        break
                    }
                }

                if ($allRecordsPresent) {
                    # Validate
                    try {
                        Complete-AuthChallenge -AuthChain $cert -DnsSleep 0 -Verbose
                        break
                    } catch {
                        Write-Host "Validation failed: $($_)" -ForegroundColor Red
                        Write-Log "Validation failed during manual challenge: $($_)" -Level 'Error'
                        $retry = Read-Host "`nRetry validation? (Y/N)"
                        if ($retry -notmatch '^(Y|y)$') {
                            return
                        }
                    }
                } else {
                    Write-Host "Please wait a few minutes for DNS propagation and try again." -ForegroundColor Yellow
                }
            }

            # Final check
            $cert = Get-PACertificate -MainDomain $mainDomain
            if (-not $cert.Certificate) {
                Write-Host "Certificate validation failed." -ForegroundColor Red
                Write-Log "Certificate validation failed for $mainDomain" -Level 'Error'
                return
            }
        }
        else {
            # Automated challenge
            # -Force overwrites existing orders if present
            $cert = New-PACertificate -Domain $mainDomain -Plugin $plugin -PluginArgs $pluginArgs -Force -Verbose
            if (-not $cert.CertFile -and -not $cert.FullChainFile -and -not $cert.PfxFile) {
                Write-Host "Failed to obtain the certificate." -ForegroundColor Red
                Write-Log "Failed to obtain the certificate for $mainDomain" -Level 'Error'
                return
            }
        }

        # Call Install-Certificate to handle post-issuance installation
        Install-Certificate -PACertificate $cert
    } catch {
        Write-Host "Error during certificate request: $($_)" -ForegroundColor Red
        Write-Log "Error during certificate request: $($_)" -Level 'Error'
    }
}
