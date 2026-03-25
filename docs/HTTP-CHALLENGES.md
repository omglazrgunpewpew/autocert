# HTTP-01 Challenge Support in AutoCert

## Overview

AutoCert now supports HTTP-01 challenges in addition to DNS-01 challenges, providing flexible validation options for obtaining Let's Encrypt certificates.

## Table of Contents

1. [Challenge Types](#challenge-types)
2. [When to Use HTTP-01](#when-to-use-http-01)
3. [Prerequisites](#prerequisites)
4. [HTTP-01 Methods](#http-01-methods)
5. [Configuration Guide](#configuration-guide)
6. [Troubleshooting](#troubleshooting)
7. [Security Considerations](#security-considerations)

---

## Challenge Types

### DNS-01 Challenge (Default)
- Validates domain ownership via DNS TXT records
- Supports 50+ DNS provider APIs
- Works for wildcard certificates (`*.domain.com`)
- Requires DNS provider API access
- Challenge location: `_acme-challenge.domain.com` (TXT record)

### HTTP-01 Challenge (New)
- Validates domain ownership via HTTP request
- Two methods: Self-hosted listener or existing web server
- Does NOT support wildcard certificates
- Requires port 80 accessibility
- Challenge location: `http://domain.com/.well-known/acme-challenge/{token}`

---

## When to Use HTTP-01

### ✅ Use HTTP-01 When:

1. **No DNS API Access**
   - Your DNS provider doesn't offer API access
   - You don't have DNS credentials
   - DNS provider not supported by Posh-ACME

2. **Existing Web Server**
   - You already run IIS, Apache, nginx, or other web server
   - Web server is accessible on port 80
   - Easier than configuring DNS

3. **Simple Server Certificates**
   - Single domain certificates (no wildcards)
   - Public-facing web server
   - Want quick validation

4. **Testing/Development**
   - Testing certificate acquisition flow
   - No DNS zone file access
   - Temporary certificates

### ❌ Don't Use HTTP-01 When:

1. **Wildcard Certificates Needed**
   - HTTP-01 cannot validate wildcards (`*.domain.com`)
   - Must use DNS-01 for wildcards

2. **Port 80 Not Accessible**
   - Server behind strict firewall
   - Port 80 blocked by ISP
   - No public IP address

3. **Internal/Private Domains**
   - Domain not publicly resolvable
   - Internal network only
   - Let's Encrypt cannot reach server

4. **Port 80 Already in Use**
   - Unless using WebRoot method with existing server
   - Cannot run self-hosted listener if port busy

---

## Prerequisites

### General Requirements
- ✅ Domain must be publicly resolvable
- ✅ Domain must point to the server running AutoCert
- ✅ Firewall must allow incoming port 80 connections
- ✅ No wildcard domains (use DNS-01 for wildcards)

### Method-Specific Requirements

#### Self-Hosted Listener
- ✅ Port 80 (or custom port) must be available
- ✅ Administrator/root privileges to bind port 80
- ✅ Temporary service interruption acceptable (2-5 minutes)
- ⚠️ Port 80 cannot be used by another service during validation

#### Existing Web Server (WebRoot)
- ✅ Web server running (IIS, Apache, nginx, etc.)
- ✅ Web root directory accessible and writable
- ✅ `.well-known/acme-challenge/` path publicly accessible
- ✅ Web server configured for the domain

---

## HTTP-01 Methods

### Method 1: Self-Hosted Listener (WebSelfHost)

**How it works:**
1. AutoCert starts a temporary HTTP listener
2. Listener responds to ACME challenge requests
3. Let's Encrypt validates domain ownership
4. Listener stops after validation

**Pros:**
- No existing web server needed
- Simple setup
- Full control over process

**Cons:**
- Port 80 must be available
- Temporary service interruption
- Manual process for each certificate

**Best for:**
- Standalone servers
- API servers without web interface
- Services not using port 80

**Configuration:**
```
Challenge Method: HTTP-01 Challenge - Self-hosted listener
Port: 80 (default) or custom port
Timeout: 120 seconds (default)
```

### Method 2: Existing Web Server (WebRoot)

**How it works:**
1. AutoCert writes challenge file to web root
2. Your web server serves the challenge file
3. Let's Encrypt reads the file via HTTP
4. AutoCert removes the challenge file

**Pros:**
- No service interruption
- Works with existing web servers
- Can run while site is live
- Multiple domains on same server

**Cons:**
- Requires existing web server
- Web root must be writable
- `.well-known` path must be accessible
- More complex troubleshooting

**Best for:**
- IIS servers
- Apache/nginx servers
- Active production websites
- Multiple virtual hosts

**Configuration:**
```
Challenge Method: HTTP-01 Challenge - Existing web server
Web Root Path: C:\inetpub\wwwroot (IIS) or /var/www/html (Apache/nginx)
Exact Path: No (creates .well-known/acme-challenge/ subdirectory)
```

---

## Configuration Guide

### Using AutoCert Menu

1. **Start Certificate Registration**
   ```
   Main Menu → Option 1: Register a new certificate
   ```

2. **Select Validation Method**
   ```
   Select the challenge validation method:
   1) DNS-01 Challenge (default)
   2) HTTP-01 Challenge - Self-hosted listener
   3) HTTP-01 Challenge - Existing web server
   ```

### Self-Hosted Listener Configuration

**Step-by-Step:**

1. Select option 2: "HTTP-01 Challenge - Self-hosted listener"

2. **Port Configuration**
   ```
   Use custom port? (Y/N, default=N to use port 80)
   ```
   - Press N for port 80 (standard)
   - Press Y to specify custom port (1-65535)

3. **Timeout Configuration**
   ```
   Enter listener timeout in seconds (default=120, 0=unlimited)
   ```
   - Default: 120 seconds
   - 0 = unlimited (waits until validation complete)
   - Recommended: 120-300 seconds

4. **Validation Process**
   - Listener starts automatically
   - ACME server connects to your server
   - Challenge validated
   - Certificate issued
   - Listener stops

**Example Configuration:**
```
Domain: example.com
Challenge: HTTP-01 Self-Hosted
Port: 80
Timeout: 120 seconds
URL: http://example.com/.well-known/acme-challenge/{token}
```

### Existing Web Server Configuration

**Step-by-Step:**

1. Select option 3: "HTTP-01 Challenge - Existing web server"

2. **Web Root Path**
   ```
   Enter the full path to your web server's document root
   ```
   - IIS: `C:\inetpub\wwwroot`
   - Apache (Linux): `/var/www/html`
   - Apache (Windows): `C:\Apache24\htdocs`
   - nginx (Linux): `/usr/share/nginx/html`
   - nginx (Windows): `C:\nginx\html`

3. **Exact Path Option**
   ```
   Use the specified path as-is without adding .well-known/acme-challenge? (Y/N)
   ```
   - N (default): Creates `.well-known/acme-challenge/` subdirectory
   - Y: Places files directly in specified path

4. **Validation Process**
   - Challenge file written to web root
   - Your web server serves the file
   - ACME server reads the file
   - Certificate issued
   - Challenge file removed

**Example Configuration:**
```
Domain: example.com
Challenge: HTTP-01 WebRoot
Web Root: C:\inetpub\wwwroot
Path: C:\inetpub\wwwroot\.well-known\acme-challenge\
URL: http://example.com/.well-known/acme-challenge/{token}
```

### IIS-Specific Configuration

1. **Ensure Static Content is Enabled**
   ```
   Server Manager → Roles → Web Server (IIS) → Static Content
   ```

2. **Allow Extension-less Files**
   - IIS serves files without extensions by default
   - No additional configuration needed

3. **Verify MIME Types**
   - AutoCert creates plain text files
   - IIS handles automatically

4. **Multiple Sites**
   - Configure correct web root for each site
   - Each site can have separate certificate

### Apache/nginx Configuration

1. **Verify Directory Permissions**
   ```bash
   # Make web root writable
   chmod 755 /var/www/html
   chmod 755 /var/www/html/.well-known
   chmod 755 /var/www/html/.well-known/acme-challenge
   ```

2. **Apache: Allow .well-known Access**
   ```apache
   <Directory "/var/www/html/.well-known">
       Require all granted
   </Directory>
   ```

3. **nginx: Serve Challenge Files**
   ```nginx
   location /.well-known/acme-challenge/ {
       root /var/www/html;
       try_files $uri =404;
   }
   ```

---

## Troubleshooting

### Common Issues

#### 1. Port 80 Already in Use

**Error:**
```
Failed to start HTTP listener: The process cannot access the file because it is being used by another process
```

**Solutions:**
- ✅ Use WebRoot method instead
- ✅ Stop conflicting service temporarily
- ✅ Use custom port with port forwarding
- ✅ Check `netstat -ano | findstr :80` to find process

#### 2. Firewall Blocking Port 80

**Error:**
```
Connection timeout during validation
```

**Solutions:**
- ✅ Allow port 80 inbound in Windows Firewall
- ✅ Check router/firewall rules
- ✅ Test with `Test-NetConnection -ComputerName yourdomain.com -Port 80`
- ✅ Temporarily disable firewall for testing

**Windows Firewall Rule:**
```powershell
New-NetFirewallRule -DisplayName "HTTP-01 ACME Challenge" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow
```

#### 3. Domain Not Resolving

**Error:**
```
DNS resolution failed for domain.com
```

**Solutions:**
- ✅ Verify DNS A record points to server IP
- ✅ Test with `nslookup domain.com`
- ✅ Wait for DNS propagation (up to 24 hours)
- ✅ Use `8.8.8.8` for testing

#### 4. Web Root Path Not Writable

**Error:**
```
Access to the path is denied
```

**Solutions:**
- ✅ Check directory permissions
- ✅ Run AutoCert as Administrator
- ✅ Grant write access to AutoCert user account
- ✅ Verify path exists and is correct

#### 5. .well-known Path Not Accessible

**Error:**
```
404 Not Found when accessing challenge URL
```

**Solutions:**
- ✅ Verify web server is running
- ✅ Check virtual host configuration
- ✅ Ensure `.well-known` directory exists
- ✅ Test URL manually in browser
- ✅ Check web server error logs

#### 6. Custom Port Issues

**Error:**
```
Let's Encrypt cannot connect to custom port
```

**Solutions:**
- ⚠️ Let's Encrypt ONLY connects to port 80
- ✅ Must use port forwarding: External 80 → Internal custom port
- ✅ Router must forward port 80 to custom port
- ✅ Or use standard port 80

### Validation Testing

**Test Challenge URL Accessibility:**
```powershell
# Create test file
$testPath = "C:\inetpub\wwwroot\.well-known\acme-challenge\test.txt"
"test content" | Out-File -FilePath $testPath -Encoding ASCII

# Test from external location
Invoke-WebRequest -Uri "http://yourdomain.com/.well-known/acme-challenge/test.txt"

# Clean up
Remove-Item $testPath
```

**Test Port 80 Accessibility:**
```powershell
Test-NetConnection -ComputerName yourdomain.com -Port 80
```

**Test DNS Resolution:**
```powershell
Resolve-DnsName yourdomain.com
```

### Debugging Tips

1. **Check ACME Logs**
   ```
   $env:LOCALAPPDATA\Posh-ACME\
   ```

2. **Enable Verbose Output**
   - AutoCert shows detailed Posh-ACME output
   - Watch for connection errors

3. **Test Manually**
   - Create test file in `.well-known/acme-challenge/`
   - Access via browser
   - Verify content matches

4. **Check Web Server Logs**
   - IIS: `C:\inetpub\logs\LogFiles\`
   - Apache: `/var/log/apache2/error.log`
   - nginx: `/var/log/nginx/error.log`

---

## Security Considerations

### Self-Hosted Listener

1. **Temporary Port Exposure**
   - Port 80 opened only during validation (2-5 minutes)
   - Listener stops automatically after timeout
   - Minimal security risk

2. **Administrator Privileges**
   - Required to bind port 80 on Windows
   - Run AutoCert as Administrator

3. **Service Interruption**
   - Port 80 services must stop temporarily
   - Plan maintenance window if needed

### Existing Web Server

1. **File Permissions**
   - Challenge files are world-readable (by design)
   - Removed immediately after validation
   - No sensitive information exposed

2. **Directory Traversal**
   - `.well-known` is standard path
   - No risk of exposing other files
   - Web server isolation maintained

3. **Concurrent Access**
   - Multiple domains can validate simultaneously
   - Each uses unique token
   - No interference between requests

### General Best Practices

1. **Use Production ACME Server**
   - Staging for testing
   - Production for real certificates

2. **Monitor Logs**
   - Check for failed validation attempts
   - Watch for unusual connection patterns

3. **Firewall Rules**
   - Only open port 80 when needed
   - Consider IP restrictions if possible

4. **Certificate Storage**
   - Certificates stored in `$env:LOCALAPPDATA\Posh-ACME\`
   - Protected by NTFS permissions
   - Backup regularly

---

## Comparison: DNS-01 vs HTTP-01

| Feature | DNS-01 | HTTP-01 |
|---------|--------|---------|
| **Wildcard Support** | ✅ Yes | ❌ No |
| **Requires Public IP** | ❌ No | ✅ Yes |
| **Requires DNS API** | ✅ Yes | ❌ No |
| **Port 80 Required** | ❌ No | ✅ Yes |
| **Works Behind Firewall** | ✅ Yes | ⚠️ Maybe |
| **Service Interruption** | ❌ No | ⚠️ Self-Host only |
| **Setup Complexity** | Medium | Easy |
| **Provider Support** | 50+ DNS providers | Any web server |
| **Validation Speed** | 2-15 minutes | 1-5 minutes |
| **Best For** | Wildcards, private networks | Simple servers, web hosts |

---

## Examples

### Example 1: Simple Web Server Certificate

**Scenario:** Single domain, IIS web server running

**Configuration:**
```
Domain: www.contoso.com
Method: HTTP-01 WebRoot
Path: C:\inetpub\wwwroot
Duration: ~3 minutes
```

**Steps:**
1. Select "Register a new certificate"
2. Enter domain: `www.contoso.com`
3. Select "Server-specific certificate"
4. Select "HTTP-01 Challenge - Existing web server"
5. Enter web root: `C:\inetpub\wwwroot`
6. Select No for exact path
7. Wait for validation
8. Install certificate

### Example 2: API Server (No Web Server)

**Scenario:** REST API server, no web server, port 80 free

**Configuration:**
```
Domain: api.contoso.com
Method: HTTP-01 Self-Host
Port: 80
Timeout: 120 seconds
Duration: ~2 minutes
```

**Steps:**
1. Select "Register a new certificate"
2. Enter domain: `api.contoso.com`
3. Select "Server-specific certificate"
4. Select "HTTP-01 Challenge - Self-hosted listener"
5. Select No for custom port (use 80)
6. Enter timeout: 120
7. Wait for validation
8. Install certificate

### Example 3: Multiple Domains on IIS

**Scenario:** Three websites on IIS, separate certificates

**Configuration:**
```
Domains:
  - site1.contoso.com → C:\inetpub\site1
  - site2.contoso.com → C:\inetpub\site2
  - site3.contoso.com → C:\inetpub\site3
Method: HTTP-01 WebRoot (each site)
```

**Steps:** (Repeat for each site)
1. Register certificate for site1.contoso.com
2. Use WebRoot method
3. Specify correct web root: `C:\inetpub\site1`
4. Repeat for site2 and site3

---

## Additional Resources

### Related Documentation
- [CERTIFICATE-REGISTRATION-FLOW.md](./CERTIFICATE-REGISTRATION-FLOW.md) - Complete registration flow
- [RELIABILITY.md](./RELIABILITY.md) - Circuit breaker and retry logic
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - General troubleshooting

### External Resources
- [Posh-ACME Documentation](https://poshac.me/)
- [Let's Encrypt HTTP-01 Challenge](https://letsencrypt.org/docs/challenge-types/#http-01-challenge)
- [ACME Protocol RFC 8555](https://tools.ietf.org/html/rfc8555)

### Posh-ACME Plugins
- [WebSelfHost Plugin Guide](https://poshac.me/docs/v4/Plugins/WebSelfHost/)
- [WebRoot Plugin Guide](https://poshac.me/docs/v4/Plugins/WebRoot/)

---

**Last Updated:** 2025-10-23
**AutoCert Version:** 2.0.0+
**Status:** ✅ Production Ready
