# DNS Provider Setup Guide

This guide covers setting up DNS provider credentials for automated certificate validation.

## 🌐 Supported DNS Providers

### Fully Automated Providers (API Integration)

| Provider | Authentication | Wildcard Support | Setup Difficulty |
|----------|---------------|------------------|------------------|
| **Cloudflare** | API Token | ✅ | Easy |
| **AWS Route53** | Access Key/Secret | ✅ | Medium |
| **Azure DNS** | Service Principal | ✅ | Medium |
| **Google Cloud DNS** | Service Account JSON | ✅ | Medium |
| **DigitalOcean** | API Token | ✅ | Easy |
| **DNS Made Easy** | API Key/Secret | ✅ | Easy |
| **Namecheap** | API User/Key | ✅ | Medium |
| **GoDaddy** | API Key/Secret | ✅ | Medium |
| **Linode** | API Token | ✅ | Easy |
| **Vultr** | API Key | ✅ | Easy |
| **Hetzner** | API Token | ✅ | Easy |
| **OVH** | API Credentials | ✅ | Hard |
| **1&1 IONOS** | API Key | ✅ | Medium |
| **Hurricane Electric** | API Key | ✅ | Medium |
| **Dynu** | API Key | ✅ | Easy |

## 🔧 Provider-Specific Setup Instructions

### Cloudflare (Recommended)

Cloudflare offers the simplest setup process with excellent API documentation.

#### Step 1: Create API Token

1. Log into [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token"
3. Use "Custom token" template
4. Set permissions:
   - **Zone**: `Zone Settings:Read`
   - **Zone**: `Zone:Read`
   - **Zone**: `DNS:Edit`
5. Set zone resources:
   - **Include**: `All zones` (or specific zones)
6. Copy the token immediately (shown only once)

#### Step 2: Test the Token

```powershell
# Test API access
$token = "your_cloudflare_token_here"
$headers = @{ "Authorization" = "Bearer $token" }
Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/user/tokens/verify" -Headers $headers
```

#### Step 3: Store in AutoCert

When prompted for credentials in AutoCert:

- **Provider**: Cloudflare
- **Token**: Your API token

---

### AWS Route53

Route53 provides reliable DNS services with comprehensive API support.

#### Step 1: Create IAM User

1. Open [AWS IAM Console](https://console.aws.amazon.com/iam/)
2. Create new user with programmatic access
3. Attach policy with these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetChange",
        "route53:ChangeResourceRecordSets",
        "route53:ListHostedZonesByName",
        "route53:ListHostedZones"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Step 2: Note Credentials

- **Access Key ID**: Note this value
- **Secret Access Key**: Note this value (shown only once)
- **Region**: Default is `us-east-1`

#### Step 3: Store in AutoCert

When prompted for credentials in AutoCert:

- **Provider**: Route53
- **Access Key**: Your Access Key ID
- **Secret Key**: Your Secret Access Key

---

### Azure DNS

Azure DNS integrates well with Azure environments and supports service principals.

#### Step 1: Create Service Principal

```powershell
# Connect to Azure
Connect-AzAccount

# Create service principal
$sp = New-AzADServicePrincipal -DisplayName "AutoCert-DNS-ServicePrincipal"

# Note these values:
Write-Host "Tenant ID: $((Get-AzContext).Tenant.Id)"
Write-Host "Client ID: $($sp.ApplicationId)"
Write-Host "Client Secret: $($sp.PasswordCredentials.SecretText)"
```

#### Step 2: Grant DNS Zone Contributor Role

```powershell
# Get your DNS zone
$dnsZone = Get-AzDnsZone -Name "yourdomain.com"

# Assign role
New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName "DNS Zone Contributor" -Scope $dnsZone.ResourceId
```

#### Step 3: Store in AutoCert

When prompted for credentials in AutoCert:

- **Provider**: Azure
- **Tenant ID**: Your Azure AD tenant ID
- **Client ID**: Service principal application ID
- **Client Secret**: Service principal password

---

### Google Cloud DNS

Google Cloud DNS offers global DNS resolution with excellent performance.

#### Step 1: Create Service Account

1. Open [Google Cloud Console](https://console.cloud.google.com/iam-admin/serviceaccounts)
2. Create new service account
3. Grant "DNS Administrator" role
4. Create and download JSON key file

#### Step 2: Enable Cloud DNS API

```bash
gcloud services enable dns.googleapis.com
```

#### Step 3: Store in AutoCert

When prompted for credentials in AutoCert:

- **Provider**: Google Cloud DNS
- **Service Account JSON**: Path to downloaded JSON file
- **Project ID**: Your Google Cloud project ID

---

### DigitalOcean

DigitalOcean provides simple API access for DNS management.

#### Step 1: Generate API Token

1. Log into [DigitalOcean Control Panel](https://cloud.digitalocean.com/account/api/tokens)
2. Generate new token with "Write" scope
3. Copy the token

#### Step 2: Store in AutoCert

When prompted for credentials in AutoCert:

- **Provider**: DigitalOcean
- **API Token**: Your DigitalOcean token

---

### Manual DNS Mode

Use this method when your DNS provider doesn't have API integration or you prefer manual control.

#### How It Works

1. AutoCert generates a TXT record name and value
2. You manually add the TXT record to your DNS
3. AutoCert monitors DNS propagation
4. Certificate is issued after validation

#### Step-by-Step Process

1. Start certificate registration in AutoCert
2. Select "Manual DNS" as provider
3. Note the TXT record details:
   - **Name**: `_acme-challenge.yourdomain.com`
   - **Value**: Random string provided by AutoCert
4. Add the TXT record in your DNS provider's control panel
5. Wait for DNS propagation (usually 5-15 minutes)
6. Return to AutoCert and continue the process

#### DNS Propagation Check

```powershell
# Check if TXT record is propagated
nslookup -type=TXT _acme-challenge.yourdomain.com

# Or use online tools:
# https://whatsmydns.net/
# https://dnschecker.org/
```

## 🔒 Security Best Practices

### API Token Security

1. **Minimal Permissions**: Grant only necessary permissions
2. **Token Rotation**: Rotate tokens every 90 days
3. **Secure Storage**: Store tokens in Windows Credential Manager
4. **Monitor Usage**: Review API access logs regularly

### Network Security

1. **IP Restrictions**: Limit API access to specific IP addresses where possible
2. **Rate Limiting**: Be aware of provider rate limits
3. **Audit Logs**: Monitor DNS changes in provider dashboards

### Credential Management

```powershell
# AutoCert stores credentials securely using Windows Credential Manager
# Credentials are encrypted and tied to the current user account

# View stored credentials (for troubleshooting)
cmdkey /list:AutoCert*

# Remove stored credentials if needed
cmdkey /delete:AutoCert-DNSProvider-Cloudflare
```

## 🚨 Troubleshooting DNS Issues

### Common Problems

#### Authentication Failures

```powershell
# Test DNS provider credentials manually
Test-DnsProvider -Provider Cloudflare -Token $yourToken

# Check credential storage
Get-StoredCredential -Target "AutoCert-DNSProvider-Cloudflare"
```

#### DNS Propagation Delays

```powershell
# Check DNS propagation status
Test-DNSPropagation -RecordName "_acme-challenge.yourdomain.com" -RecordValue $txtValue

# Force DNS cache flush
ipconfig /flushdns
Clear-DnsClientCache
```

#### Rate Limiting

- **Let's Encrypt**: 50 certificates per domain per week
- **DNS Providers**: Vary by provider (check documentation)
- **Solution**: Use staging environment for testing

#### Firewall Issues

```powershell
# Test HTTPS connectivity to DNS provider APIs
Test-NetConnection -ComputerName api.cloudflare.com -Port 443
Test-NetConnection -ComputerName route53.amazonaws.com -Port 443
```

### Diagnostic Commands

```powershell
# Comprehensive DNS diagnostics
.\Main.ps1 # Select option 7 for System Health Check

# Manual DNS testing
Resolve-DnsName -Name "_acme-challenge.yourdomain.com" -Type TXT
nslookup -type=TXT _acme-challenge.yourdomain.com 8.8.8.8

# Check DNS provider API status
Invoke-WebRequest -Uri "https://www.cloudflarestatus.com/" -UseBasicParsing
```

## 🔄 Switching DNS Providers

To change DNS providers:

1. **Add New Provider Credentials**:

   ```powershell
   .\Main.ps1 # Select option 6 for Credential Management
   ```

2. **Update Configuration**:
   Edit `dns-config.json` to set new default provider

3. **Test New Provider**:

   ```powershell
   .\Main.ps1 -ConfigTest
   ```

4. **Remove Old Credentials**:
   Remove old provider credentials from Credential Manager

## 📚 Additional Resources

### Provider Documentation

- [Cloudflare API Docs](https://developers.cloudflare.com/api/)
- [AWS Route53 API Reference](https://docs.aws.amazon.com/route53/latest/APIReference/)
- [Azure DNS REST API](https://docs.microsoft.com/en-us/rest/api/dns/)
- [Google Cloud DNS API](https://cloud.google.com/dns/docs/reference)

### DNS Tools

- [DNS Propagation Checker](https://whatsmydns.net/)
- [DNS Lookup Tool](https://dnschecker.org/)
- [MX Toolbox](https://mxtoolbox.com/SuperTool.aspx)

### Support

- Check provider status pages for API issues
- Review provider documentation for rate limits
- Test credentials using provider's own tools before using with AutoCert
