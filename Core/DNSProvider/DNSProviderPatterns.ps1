# Core/DNSProvider/DNSProviderPatterns.ps1
<#
    .SYNOPSIS
        DNS provider pattern definitions and configuration.
    .DESCRIPTION
        This module contains all DNS provider patterns used for automatic detection,
        organized by confidence level and including setup information.
    .NOTES
        Version: 1.0.0
        Author: AutoCert Team
        Created: 2025-01-17
        Updated: 2025-01-17
#>

<#
    .SYNOPSIS
        Returns the DNS provider patterns used for detection.
    .DESCRIPTION
        Provides a centralized configuration of DNS provider patterns, organized by
        confidence level and including setup information.
    .OUTPUTS
        [hashtable] Dictionary of provider patterns and metadata.
#>
function Get-DNSProviderPattern
{
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    return @{
        # Tier 1 - High confidence patterns (Cloud providers)
        'Cloudflare'         = @{
            Patterns    = @('*.cloudflare.com')
            Plugin      = 'Cloudflare'
            Confidence  = 'High'
            Description = 'Cloudflare DNS - Requires API Token'
            SetupUrl    = 'https://dash.cloudflare.com/profile/api-tokens'
        }
        'AWS Route53'        = @{
            Patterns    = @('*.awsdns-*.*.amazonaws.com', '*.awsdns-*.amazonaws.com')
            Plugin      = 'Route53'
            Confidence  = 'High'
            Description = 'Amazon Route53 - Requires AWS credentials or profile'
            SetupUrl    = 'https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html'
        }
        'Azure DNS'          = @{
            Patterns    = @('*.azure-dns*.info', '*.azure-dns*.org', '*.azure-dns*.com', '*.azure-dns*.net')
            Plugin      = 'Azure'
            Confidence  = 'High'
            Description = 'Microsoft Azure DNS - Requires Azure authentication'
            SetupUrl    = 'https://docs.microsoft.com/en-us/azure/dns/'
        }
        'Google Cloud DNS'   = @{
            Patterns    = @('*.googledomains.com', '*.google.com', '*.googledns.com')
            Plugin      = 'GoogleDomains'
            Confidence  = 'High'
            Description = 'Google Cloud DNS - Requires service account or OAuth'
            SetupUrl    = 'https://cloud.google.com/dns/docs'
        }
        'DigitalOcean'       = @{
            Patterns    = @('*.digitalocean.com')
            Plugin      = 'DigitalOcean'
            Confidence  = 'High'
            Description = 'DigitalOcean DNS - Requires API token'
            SetupUrl    = 'https://cloud.digitalocean.com/account/api/tokens'
        }
        'Linode'             = @{
            Patterns    = @('*.linode.com')
            Plugin      = 'Linode'
            Confidence  = 'High'
            Description = 'Linode DNS - Requires API token'
            SetupUrl    = 'https://cloud.linode.com/profile/tokens'
        }
        'Vultr'              = @{
            Patterns    = @('*.vultr.com')
            Plugin      = 'Vultr'
            Confidence  = 'High'
            Description = 'Vultr DNS - Requires API key'
            SetupUrl    = 'https://my.vultr.com/settings/#settingsapi'
        }
        'Hetzner'            = @{
            Patterns    = @('*.hetzner.com', '*.hetzner.de')
            Plugin      = 'Hetzner'
            Confidence  = 'High'
            Description = 'Hetzner DNS - Requires API token'
            SetupUrl    = 'https://dns.hetzner.com/settings/api-token'
        }
        'DNS Made Easy'      = @{
            Patterns    = @('*.dnsmadeeasy.com')
            Plugin      = 'DNSMadeEasy'
            Confidence  = 'High'
            Description = 'DNS Made Easy - Requires API credentials'
            SetupUrl    = 'https://cp.dnsmadeeasy.com/account/info'
        }
        'NS1'                = @{
            Patterns    = @('*.nsone.net', '*.ns1.com')
            Plugin      = 'NS1'
            Confidence  = 'High'
            Description = 'NS1 DNS - Requires API key'
            SetupUrl    = 'https://my.nsone.net/#/account/settings'
        }
        'DNSimple'           = @{
            Patterns    = @('*.dnsimple.com')
            Plugin      = 'DNSimple'
            Confidence  = 'High'
            Description = 'DNSimple - Requires API token'
            SetupUrl    = 'https://dnsimple.com/user'
        }
        'Gandi'              = @{
            Patterns    = @('*.gandi.net')
            Plugin      = 'Gandi'
            Confidence  = 'High'
            Description = 'Gandi DNS - Requires API key'
            SetupUrl    = 'https://account.gandi.net/account/api'
        }
        'Porkbun'            = @{
            Patterns    = @('*.porkbun.com')
            Plugin      = 'Porkbun'
            Confidence  = 'High'
            Description = 'Porkbun DNS - Requires API key'
            SetupUrl    = 'https://porkbun.com/account/api'
        }
        'Dynu'               = @{
            Patterns    = @('*.dynu.com')
            Plugin      = 'Dynu'
            Confidence  = 'High'
            Description = 'Dynu DNS - Requires API credentials'
            SetupUrl    = 'https://www.dynu.com/ControlPanel/APICredentials'
        }
        'Hurricane Electric' = @{
            Patterns    = @('*.he.net')
            Plugin      = 'HurricaneElectric'
            Confidence  = 'High'
            Description = 'Hurricane Electric DNS - Requires API key'
            SetupUrl    = 'https://dns.he.net/'
        }
        # Tier 2 - Medium confidence patterns (Registrar DNS)
        'GoDaddy'            = @{
            Patterns    = @('*.domaincontrol.com')
            Plugin      = 'GoDaddy'
            Confidence  = 'Medium'
            Description = 'GoDaddy DNS - Requires API key and secret'
            SetupUrl    = 'https://developer.godaddy.com/keys'
        }
        'Namecheap'          = @{
            Patterns    = @('*.registrar-servers.com')
            Plugin      = 'Namecheap'
            Confidence  = 'Medium'
            Description = 'Namecheap DNS - Requires API key and username'
            SetupUrl    = 'https://ap.www.namecheap.com/settings/tools/apiaccess/'
        }
        'OVH'                = @{
            Patterns    = @('*.ovh.net', '*.ovh.com')
            Plugin      = 'OVH'
            Confidence  = 'Medium'
            Description = 'OVH DNS - Requires API credentials'
            SetupUrl    = 'https://eu.api.ovh.com/createToken/'
        }
        'Hover'              = @{
            Patterns    = @('*.hover.com')
            Plugin      = 'Hover'
            Confidence  = 'Medium'
            Description = 'Hover DNS - Requires API credentials'
            SetupUrl    = 'https://www.hover.com/api'
        }
        'Network Solutions'  = @{
            Patterns    = @('*.worldnic.com', '*.networksolutions.com')
            Plugin      = 'NetworkSolutions'
            Confidence  = 'Medium'
            Description = 'Network Solutions DNS - May require manual configuration'
            SetupUrl    = 'https://www.networksolutions.com/'
        }
        'Domain.com'         = @{
            Patterns    = @('*.domain.com')
            Plugin      = 'DomainCom'
            Confidence  = 'Medium'
            Description = 'Domain.com DNS - May require manual configuration'
            SetupUrl    = 'https://www.domain.com/'
        }
        'Bluehost'           = @{
            Patterns    = @('*.bluehost.com')
            Plugin      = 'Bluehost'
            Confidence  = 'Medium'
            Description = 'Bluehost DNS - May require manual configuration'
            SetupUrl    = 'https://www.bluehost.com/'
        }
        'HostGator'          = @{
            Patterns    = @('*.hostgator.com')
            Plugin      = 'HostGator'
            Confidence  = 'Medium'
            Description = 'HostGator DNS - May require manual configuration'
            SetupUrl    = 'https://www.hostgator.com/'
        }
    }
}

# Export functions
Export-ModuleMember -Function Get-DNSProviderPattern
