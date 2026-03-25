function Get-CompleteViewDeploymentConfigPath {
    [CmdletBinding()]
    param()

    Join-Path $env:LOCALAPPDATA 'PoshACME\completeview_deployment.json'
}

function Get-CompleteViewDeploymentStatePath {
    [CmdletBinding()]
    param()

    Join-Path $env:LOCALAPPDATA 'PoshACME\completeview_deployment_state.json'
}

function Get-CompleteViewKnownInstallations {
    [CmdletBinding()]
    param()

    $installations = @(
        @{
            Name = 'CompleteView'
            ManagementServerAppSettingsPath = 'C:\Program Files\Salient Security Platform\CompleteView\Management Server\appsettings.json'
            ManagementServerServiceName = 'CompleteView Management Server'
            RecordingServerCertificateFolder = 'C:\Program Files\Salient Security Platform\CompleteView\Recording Server\Certificates'
            RecordingServerServiceName = 'CompleteView Recording Server'
        },
        @{
            Name = 'CompleteView 2020'
            ManagementServerAppSettingsPath = 'C:\Program Files\Salient Security Platform\CompleteView 2020\Management Server\appsettings.json'
            ManagementServerServiceName = 'CompleteView Management Server'
            RecordingServerCertificateFolder = 'C:\Program Files\Salient Security Platform\CompleteView 2020\Recording Server\Certificates'
            RecordingServerServiceName = 'CompleteView Recording Server'
        }
    )

    foreach ($installation in $installations) {
        if ((Test-Path $installation.ManagementServerAppSettingsPath) -or
            (Test-Path $installation.RecordingServerCertificateFolder)) {
            return $installation
        }
    }

    $installations[0]
}

function Get-CompleteViewDefaultDeploymentConfig {
    [CmdletBinding()]
    param()

    $installation = Get-CompleteViewKnownInstallations
    $computerName = $env:COMPUTERNAME

    [ordered]@{
        Enabled = $false
        DeploymentName = 'CompleteView Default Deployment'
        CompleteViewDeployment = [ordered]@{
            ManagementServer = [ordered]@{
                Fqdn = $computerName
                ComputerName = $computerName
                ServiceName = $installation.ManagementServerServiceName
                AppSettingsPath = $installation.ManagementServerAppSettingsPath
                HttpsPort = 8096
                CertificateStore = [ordered]@{
                    StoreLocation = 'LocalMachine'
                    StoreName = 'My'
                    FriendlyName = 'CompleteView.AutoCert.HTTPS'
                }
                RestartService = $true
                VerifyAfterDeploy = $true
                Enabled = $true
            }
            RecordingServers = @()
            CertificateOrders = [ordered]@{
                BaseDomain = ''
                UseWildcard = $true
                SubjectAlternativeNames = @()
                MainDomain = ''
                FriendlyName = 'CompleteView.AutoCert.HTTPS'
            }
            DnsChallenge = [ordered]@{
                Provider = 'Manual'
                Plugin = 'Manual'
                PluginArgs = [ordered]@{}
                PluginArgsSource = 'Inline'
                CredentialName = ''
                ContactEmail = ''
                PropagationSeconds = 120
            }
            RemoteExecution = [ordered]@{
                Enabled = $true
                UseSsl = $false
                CredentialName = ''
                OperationTimeoutSeconds = 120
            }
            DeploymentOptions = [ordered]@{
                ArtifactRoot = (Join-Path $env:LOCALAPPDATA 'PoshACME\CompleteView\Artifacts')
                RecordingServerCertificateFileName = 'cert-autocert.pem'
                RecordingServerPrivateKeyFileName = 'pvkey-autocert.pem'
                ContinueOnRecordingServerFailure = $true
                SendNotifications = $true
                UpdateManagementServerAppSettings = $true
                UpdateRecordingServerConfig = $false
            }
        }
    }
}

function Get-CompleteViewDeploymentConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Get-CompleteViewDeploymentConfigPath)
    )

    if (Test-Path $ConfigPath) {
        try {
            return Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        }
        catch {
            Write-Warning "Failed to load CompleteView deployment config: $($_.Exception.Message)"
            Write-Log "Failed to load CompleteView deployment config: $($_.Exception.Message)" -Level 'Warning'
        }
    }

    [pscustomobject](Get-CompleteViewDefaultDeploymentConfig)
}

function Save-CompleteViewDeploymentConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [string]$ConfigPath = (Get-CompleteViewDeploymentConfigPath)
    )

    $configDir = Split-Path -Path $ConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($ConfigPath, 'Save CompleteView deployment configuration')) {
        $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-Log "Saved CompleteView deployment configuration to $ConfigPath" -Level 'Info'
        return $true
    }

    $false
}

function Get-CompleteViewDeploymentState {
    [CmdletBinding()]
    param(
        [string]$StatePath = (Get-CompleteViewDeploymentStatePath)
    )

    if (Test-Path $StatePath) {
        return Get-Content -Path $StatePath -Raw | ConvertFrom-Json
    }

    [pscustomobject]@{
        LastRunId = $null
        LastRun = $null
        Runs = @()
    }
}

function Save-CompleteViewDeploymentState {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,
        [string]$StatePath = (Get-CompleteViewDeploymentStatePath)
    )

    $stateDir = Split-Path -Path $StatePath -Parent
    if (-not (Test-Path $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($StatePath, 'Save CompleteView deployment state')) {
        $State | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8
        return $true
    }

    $false
}

function New-CompleteViewRunId {
    [CmdletBinding()]
    param()

    "cvdeploy-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function Get-CompleteViewCertificateDomains {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $order = $Config.CompleteViewDeployment.CertificateOrders
    $domains = New-Object System.Collections.Generic.List[string]

    if ($order.UseWildcard -and -not [string]::IsNullOrWhiteSpace($order.BaseDomain)) {
        $domains.Add("*.{0}" -f $order.BaseDomain.Trim())
    }

    if (-not [string]::IsNullOrWhiteSpace($Config.CompleteViewDeployment.ManagementServer.Fqdn)) {
        $domains.Add($Config.CompleteViewDeployment.ManagementServer.Fqdn.Trim())
    }

    foreach ($server in @($Config.CompleteViewDeployment.RecordingServers)) {
        if ($server.Enabled -and -not [string]::IsNullOrWhiteSpace($server.Fqdn)) {
            $domains.Add($server.Fqdn.Trim())
        }
    }

    foreach ($name in @($order.SubjectAlternativeNames)) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $domains.Add($name.Trim())
        }
    }

    @($domains | Where-Object { $_ } | Select-Object -Unique)
}

function Resolve-CompleteViewMainDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $domains = Get-CompleteViewCertificateDomains -Config $Config
    $order = $Config.CompleteViewDeployment.CertificateOrders

    if (-not [string]::IsNullOrWhiteSpace($order.MainDomain)) {
        return $order.MainDomain
    }

    if ($order.UseWildcard -and -not [string]::IsNullOrWhiteSpace($order.BaseDomain)) {
        return "*.{0}" -f $order.BaseDomain.Trim()
    }

    if ($domains.Count -gt 0) {
        return $domains[0]
    }

    throw "No certificate domains are configured for the CompleteView deployment."
}

function Resolve-CompleteViewPluginArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $dns = $Config.CompleteViewDeployment.DnsChallenge
    $pluginArgs = @{}

    if ($dns.PluginArgs) {
        foreach ($property in $dns.PluginArgs.PSObject.Properties) {
            $pluginArgs[$property.Name] = $property.Value
        }
    }

    if ($pluginArgs.Count -gt 0) {
        return $pluginArgs
    }

    if ([string]::IsNullOrWhiteSpace($dns.CredentialName)) {
        return $pluginArgs
    }

    $credential = Get-SecureCredential -ProviderName $dns.CredentialName
    if ($null -eq $credential) {
        throw "DNS credential '$($dns.CredentialName)' was not found."
    }

    switch ($dns.Plugin) {
        'Cloudflare' {
            $pluginArgs['CFToken'] = $credential.GetNetworkCredential().Password
        }
        'Route53' {
            $pluginArgs['R53AccessKey'] = $credential.UserName
            $pluginArgs['R53SecretKey'] = $credential.GetNetworkCredential().Password
        }
        'DigitalOcean' {
            $pluginArgs['DOToken'] = $credential.GetNetworkCredential().Password
        }
        'Azure' {
            $pluginArgs['AZSubscriptionId'] = $credential.UserName
            $pluginArgs['AZAccessToken'] = $credential.GetNetworkCredential().Password
        }
        default {
            throw "Credential-to-plugin mapping is not implemented for plugin '$($dns.Plugin)'. Use DnsChallenge.PluginArgs instead."
        }
    }

    $pluginArgs
}

function Backup-CompleteViewJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backupPath = '{0}.bak.{1}' -f $Path, $timestamp
    Copy-Item -Path $Path -Destination $backupPath -Force
    $backupPath
}

function Set-JsonPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Object,
        [Parameter(Mandatory = $true)]
        [string[]]$Path,
        [Parameter(Mandatory = $true)]
        $Value
    )

    $current = $Object
    for ($i = 0; $i -lt ($Path.Count - 1); $i++) {
        $segment = $Path[$i]
        $next = $current.PSObject.Properties[$segment]
        if ($null -eq $next) {
            $child = [pscustomobject]@{}
            Add-Member -InputObject $current -MemberType NoteProperty -Name $segment -Value $child
            $current = $child
        }
        else {
            $current = $next.Value
        }
    }

    $leaf = $Path[-1]
    $existing = $current.PSObject.Properties[$leaf]
    if ($null -eq $existing) {
        Add-Member -InputObject $current -MemberType NoteProperty -Name $leaf -Value $Value
    }
    else {
        $existing.Value = $Value
    }
}

function Update-CompleteViewManagementServerAppSettings {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [object]$PACertificate
    )

    $ms = $Config.CompleteViewDeployment.ManagementServer
    $result = @{
        Success = $false
        Updated = $false
        BackupPath = $null
        AppSettingsPath = $ms.AppSettingsPath
    }

    if (-not $Config.CompleteViewDeployment.DeploymentOptions.UpdateManagementServerAppSettings) {
        $result.Success = $true
        return $result
    }

    if (-not (Test-Path $ms.AppSettingsPath)) {
        throw "Management Server appsettings.json not found at $($ms.AppSettingsPath)"
    }

    $json = Get-Content -Path $ms.AppSettingsPath -Raw | ConvertFrom-Json
    $result.BackupPath = Backup-CompleteViewJsonFile -Path $ms.AppSettingsPath

    Set-JsonPropertyValue -Object $json -Path @('CertificateFromStore', 'StoreName') -Value $ms.CertificateStore.StoreName
    Set-JsonPropertyValue -Object $json -Path @('CertificateFromStore', 'FriendlyName') -Value $ms.CertificateStore.FriendlyName
    Set-JsonPropertyValue -Object $json -Path @('CertificateFromStore', 'SubjectCN') -Value $ms.Fqdn
    Set-JsonPropertyValue -Object $json -Path @('CertificateFromStore', 'Thumbprint') -Value $PACertificate.Certificate.Thumbprint

    if ($PSCmdlet.ShouldProcess($ms.AppSettingsPath, 'Update CompleteView Management Server appsettings.json')) {
        $json | ConvertTo-Json -Depth 20 | Set-Content -Path $ms.AppSettingsPath -Encoding UTF8
        $result.Success = $true
        $result.Updated = $true
        Write-Log "Updated Management Server appsettings.json with certificate thumbprint $($PACertificate.Certificate.Thumbprint)" -Level 'Info'
    }

    $result
}

function Restart-CompleteViewService {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [string]$ComputerName = $env:COMPUTERNAME
    )

    if ($ComputerName -eq $env:COMPUTERNAME -or $ComputerName -eq 'localhost') {
        if ($PSCmdlet.ShouldProcess($ServiceName, "Restart service on $ComputerName")) {
            Restart-Service -Name $ServiceName -Force -ErrorAction Stop
            $service = Get-Service -Name $ServiceName -ErrorAction Stop
            $service.WaitForStatus('Running', [timespan]::FromSeconds(90))
        }
        return $true
    }

    $scriptBlock = {
        param($TargetServiceName)
        Restart-Service -Name $TargetServiceName -Force -ErrorAction Stop
        $service = Get-Service -Name $TargetServiceName -ErrorAction Stop
        $service.WaitForStatus('Running', [timespan]::FromSeconds(90))
        $true
    }

    if ($PSCmdlet.ShouldProcess($ServiceName, "Restart remote service on $ComputerName")) {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ArgumentList $ServiceName -ErrorAction Stop | Out-Null
    }

    $true
}

function Get-TlsEndpointCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $tcp.Connect($HostName, $Port)
        $ssl = [System.Net.Security.SslStream]::new(
            $tcp.GetStream(),
            $false,
            { param($sender, $certificate, $chain, $sslPolicyErrors) return $true }
        )

        try {
            $ssl.AuthenticateAsClient($HostName)
            return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
        }
        finally {
            $ssl.Dispose()
        }
    }
    finally {
        $tcp.Dispose()
    }
}

function Test-CompleteViewTlsEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostName,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [string]$ExpectedThumbprint
    )

    try {
        $certificate = Get-TlsEndpointCertificate -HostName $HostName -Port $Port
        $thumbprintMatches = $true
        if ($ExpectedThumbprint) {
            $thumbprintMatches = $certificate.Thumbprint -eq $ExpectedThumbprint
        }

        return @{
            Success = $thumbprintMatches
            Thumbprint = $certificate.Thumbprint
            Subject = $certificate.Subject
            NotAfter = $certificate.NotAfter
            Error = $null
        }
    }
    catch {
        return @{
            Success = $false
            Thumbprint = $null
            Subject = $null
            NotAfter = $null
            Error = $_.Exception.Message
        }
    }
}

function Export-CompleteViewPemArtifacts {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate,
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    $artifactRoot = $Config.CompleteViewDeployment.DeploymentOptions.ArtifactRoot
    $artifactPath = Join-Path $artifactRoot $RunId
    if (-not (Test-Path $artifactPath)) {
        New-Item -ItemType Directory -Path $artifactPath -Force | Out-Null
    }

    $pemContent = Get-CertificatePEMContent -Certificate $PACertificate -IncludeKey
    if (-not $pemContent.Success) {
        throw $pemContent.ErrorMessage
    }

    $certFile = Join-Path $artifactPath $Config.CompleteViewDeployment.DeploymentOptions.RecordingServerCertificateFileName
    $keyFile = Join-Path $artifactPath $Config.CompleteViewDeployment.DeploymentOptions.RecordingServerPrivateKeyFileName

    if ($PSCmdlet.ShouldProcess($artifactPath, 'Export CompleteView PEM artifacts')) {
        Set-Content -Path $certFile -Value $pemContent.CertContent -Encoding ascii
        Set-Content -Path $keyFile -Value $pemContent.KeyContent -Encoding ascii
    }

    @{
        ArtifactPath = $artifactPath
        CertificateFile = $certFile
        PrivateKeyFile = $keyFile
    }
}

function Install-CompleteViewManagementServerCertificate {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$PACertificate,
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $ms = $Config.CompleteViewDeployment.ManagementServer
    $storeLocation = $ms.CertificateStore.StoreLocation
    $storeName = $ms.CertificateStore.StoreName

    $result = @{
        Success = $false
        Thumbprint = $PACertificate.Certificate.Thumbprint
        AppSettings = $null
        Verification = $null
    }

    if ($PSCmdlet.ShouldProcess("$storeLocation\$storeName", 'Install Management Server certificate')) {
        Install-PACertificate -PACertificate $PACertificate -StoreLocation $storeLocation -StoreName $storeName -ErrorAction Stop | Out-Null
        $result.AppSettings = Update-CompleteViewManagementServerAppSettings -Config $Config -PACertificate $PACertificate

        if ($ms.RestartService) {
            Restart-CompleteViewService -ServiceName $ms.ServiceName -ComputerName $ms.ComputerName | Out-Null
        }

        if ($ms.VerifyAfterDeploy) {
            $result.Verification = Test-CompleteViewTlsEndpoint -HostName $ms.Fqdn -Port $ms.HttpsPort -ExpectedThumbprint $PACertificate.Certificate.Thumbprint
            if (-not $result.Verification.Success) {
                throw "Management Server TLS verification failed: $($result.Verification.Error)"
            }
        }

        $result.Success = $true
    }

    $result
}

function Install-CompleteViewRecordingServerCertificate {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RecordingServer,
        [Parameter(Mandatory = $true)]
        [hashtable]$Artifacts,
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [string]$ExpectedThumbprint
    )

    $result = @{
        Name = $RecordingServer.Name
        Fqdn = $RecordingServer.Fqdn
        ComputerName = $RecordingServer.ComputerName
        Success = $false
        Verification = $null
        Error = $null
    }

    try {
        $scriptBlock = {
            param(
                [string]$CertificateFolder,
                [string]$CertificateFileName,
                [string]$PrivateKeyFileName,
                [string]$CertificateContent,
                [string]$PrivateKeyContent,
                [bool]$UpdateConfig,
                [string]$ConfigurationFilePath,
                [int]$SecurePort,
                [string]$HostName
            )

            if (-not (Test-Path $CertificateFolder)) {
                New-Item -ItemType Directory -Path $CertificateFolder -Force | Out-Null
            }

            $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
            $certPath = Join-Path $CertificateFolder $CertificateFileName
            $keyPath = Join-Path $CertificateFolder $PrivateKeyFileName

            if (Test-Path $certPath) {
                Move-Item -Path $certPath -Destination ($certPath + ".bak.$timestamp") -Force
            }
            if (Test-Path $keyPath) {
                Move-Item -Path $keyPath -Destination ($keyPath + ".bak.$timestamp") -Force
            }

            Set-Content -Path $certPath -Value $CertificateContent -Encoding ascii
            Set-Content -Path $keyPath -Value $PrivateKeyContent -Encoding ascii

            if ($UpdateConfig -and $ConfigurationFilePath -and (Test-Path $ConfigurationFilePath)) {
                $configJson = Get-Content -Path $ConfigurationFilePath -Raw | ConvertFrom-Json

                if ($null -eq $configJson.TlsSettings) {
                    Add-Member -InputObject $configJson -MemberType NoteProperty -Name TlsSettings -Value ([pscustomobject]@{})
                }

                foreach ($pair in @{
                    PemCertificatePath = $certPath
                    PemPrivateKeyPath = $keyPath
                    UseTls = $true
                    SecurePort = $SecurePort
                    HostName = $HostName
                }.GetEnumerator()) {
                    if ($null -eq $configJson.TlsSettings.PSObject.Properties[$pair.Key]) {
                        Add-Member -InputObject $configJson.TlsSettings -MemberType NoteProperty -Name $pair.Key -Value $pair.Value
                    }
                    else {
                        $configJson.TlsSettings.PSObject.Properties[$pair.Key].Value = $pair.Value
                    }
                }

                $configJson | ConvertTo-Json -Depth 20 | Set-Content -Path $ConfigurationFilePath -Encoding UTF8
            }

            @{
                CertificatePath = $certPath
                PrivateKeyPath = $keyPath
            }
        }

        $certificateContent = Get-Content -Path $Artifacts.CertificateFile -Raw
        $privateKeyContent = Get-Content -Path $Artifacts.PrivateKeyFile -Raw
        $deploymentOptions = $Config.CompleteViewDeployment.DeploymentOptions

        if ($RecordingServer.ComputerName -eq $env:COMPUTERNAME -or $RecordingServer.ComputerName -eq 'localhost') {
            & $scriptBlock `
                $RecordingServer.CertificateFolder `
                $deploymentOptions.RecordingServerCertificateFileName `
                $deploymentOptions.RecordingServerPrivateKeyFileName `
                $certificateContent `
                $privateKeyContent `
                ([bool]$deploymentOptions.UpdateRecordingServerConfig) `
                $RecordingServer.ConfigurationFilePath `
                ([int]$RecordingServer.SecurePort) `
                $RecordingServer.Fqdn | Out-Null
        }
        else {
            if ($PSCmdlet.ShouldProcess($RecordingServer.ComputerName, 'Deploy Recording Server certificate remotely')) {
                Invoke-Command -ComputerName $RecordingServer.ComputerName -ScriptBlock $scriptBlock -ArgumentList @(
                    $RecordingServer.CertificateFolder,
                    $deploymentOptions.RecordingServerCertificateFileName,
                    $deploymentOptions.RecordingServerPrivateKeyFileName,
                    $certificateContent,
                    $privateKeyContent,
                    [bool]$deploymentOptions.UpdateRecordingServerConfig,
                    $RecordingServer.ConfigurationFilePath,
                    [int]$RecordingServer.SecurePort,
                    $RecordingServer.Fqdn
                ) -ErrorAction Stop | Out-Null
            }
        }

        if ($RecordingServer.RestartService) {
            Restart-CompleteViewService -ServiceName $RecordingServer.ServiceName -ComputerName $RecordingServer.ComputerName | Out-Null
        }

        if ($RecordingServer.VerifyAfterDeploy) {
            $result.Verification = Test-CompleteViewTlsEndpoint -HostName $RecordingServer.Fqdn -Port $RecordingServer.SecurePort -ExpectedThumbprint $ExpectedThumbprint
            if (-not $result.Verification.Success) {
                throw "Recording Server TLS verification failed: $($result.Verification.Error)"
            }
        }

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Log "Recording Server deployment failed for $($RecordingServer.Name): $($_.Exception.Message)" -Level 'Error'
    }

    $result
}

function Test-CompleteViewDeployment {
    [CmdletBinding()]
    param(
        [object]$Config = (Get-CompleteViewDeploymentConfig),
        [switch]$Detailed
    )

    $checks = New-Object System.Collections.Generic.List[object]
    $ms = $Config.CompleteViewDeployment.ManagementServer
    $dns = $Config.CompleteViewDeployment.DnsChallenge
    $remote = $Config.CompleteViewDeployment.RemoteExecution

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    $checks.Add([pscustomobject]@{ Name = 'AdministratorPrivileges'; Success = $isAdmin; Details = 'Local administrator permissions required' })

    $baseDomainValid = -not [string]::IsNullOrWhiteSpace($Config.CompleteViewDeployment.CertificateOrders.BaseDomain) -and
        (Test-ValidDomain -Domain $Config.CompleteViewDeployment.CertificateOrders.BaseDomain)
    $checks.Add([pscustomobject]@{ Name = 'BaseDomain'; Success = $baseDomainValid; Details = $Config.CompleteViewDeployment.CertificateOrders.BaseDomain })

    $domains = Get-CompleteViewCertificateDomains -Config $Config
    $checks.Add([pscustomobject]@{ Name = 'CertificateDomainCount'; Success = $domains.Count -gt 0; Details = ($domains -join ', ') })

    $checks.Add([pscustomobject]@{
        Name = 'ManagementServerAppSettings'
        Success = (Test-Path $ms.AppSettingsPath)
        Details = $ms.AppSettingsPath
    })

    $serviceExists = $null -ne (Get-Service -Name $ms.ServiceName -ErrorAction SilentlyContinue)
    $checks.Add([pscustomobject]@{
        Name = 'ManagementServerService'
        Success = $serviceExists
        Details = $ms.ServiceName
    })

    $pluginAvailable = $true
    if ($dns.Plugin -ne 'Manual') {
        $pluginAvailable = $null -ne (Get-PAPlugin | Where-Object { $_.Name -eq $dns.Plugin -and $_.ChallengeType -eq 'dns-01' })
    }
    $checks.Add([pscustomobject]@{
        Name = 'DnsPlugin'
        Success = $pluginAvailable
        Details = $dns.Plugin
    })

    try {
        Resolve-CompleteViewPluginArgs -Config $Config | Out-Null
        $checks.Add([pscustomobject]@{
            Name = 'DnsPluginArgs'
            Success = $true
            Details = if ($dns.CredentialName) { "Resolved from $($dns.CredentialName)" } else { 'Inline or empty' }
        })
    }
    catch {
        $checks.Add([pscustomobject]@{
            Name = 'DnsPluginArgs'
            Success = $false
            Details = $_.Exception.Message
        })
    }

    foreach ($server in @($Config.CompleteViewDeployment.RecordingServers)) {
        if (-not $server.Enabled) {
            continue
        }

        $remoteCheckName = "RecordingServerRemote::{0}" -f $server.Name
        if ($server.ComputerName -eq $env:COMPUTERNAME -or $server.ComputerName -eq 'localhost') {
            $checks.Add([pscustomobject]@{
                Name = $remoteCheckName
                Success = $true
                Details = 'Local deployment target'
            })
            $checks.Add([pscustomobject]@{
                Name = "RecordingServerFolder::{0}" -f $server.Name
                Success = (Test-Path $server.CertificateFolder)
                Details = $server.CertificateFolder
            })
        }
        else {
            try {
                if ($remote.Enabled) {
                    Test-WSMan -ComputerName $server.ComputerName -ErrorAction Stop | Out-Null
                }
                $checks.Add([pscustomobject]@{
                    Name = $remoteCheckName
                    Success = $true
                    Details = $server.ComputerName
                })
            }
            catch {
                $checks.Add([pscustomobject]@{
                    Name = $remoteCheckName
                    Success = $false
                    Details = $_.Exception.Message
                })
            }
        }
    }

    $overallSuccess = @($checks | Where-Object { -not $_.Success }).Count -eq 0
    $report = [pscustomobject]@{
        OverallSuccess = $overallSuccess
        Checks = @($checks)
    }

    if ($Detailed) {
        foreach ($check in $report.Checks) {
            $color = if ($check.Success) { 'Green' } else { 'Red' }
            Write-Host ("[{0}] {1} - {2}" -f $(if ($check.Success) { 'OK' } else { 'FAIL' }), $check.Name, $check.Details) -ForegroundColor $color
        }
    }

    $report
}

function Invoke-CompleteViewCertificateRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,
        [switch]$Force
    )

    Initialize-ACMEServer

    $domains = Get-CompleteViewCertificateDomains -Config $Config
    $mainDomain = Resolve-CompleteViewMainDomain -Config $Config
    $friendlyName = $Config.CompleteViewDeployment.CertificateOrders.FriendlyName
    $dns = $Config.CompleteViewDeployment.DnsChallenge
    $renewalConfig = Get-RenewalConfig

    $existing = Get-PACertificate -MainDomain $mainDomain -ErrorAction SilentlyContinue
    if ($existing -and -not $Force) {
        $daysUntilExpiry = ($existing.Certificate.NotAfter - (Get-Date)).Days
        if ($daysUntilExpiry -gt $renewalConfig.RenewalThresholdDays) {
            Write-Log "Using existing CompleteView certificate for $mainDomain with $daysUntilExpiry days remaining" -Level 'Info'
            return $existing
        }
    }

    if (-not (Get-PAAccount -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($dns.ContactEmail)) {
            throw "No ACME account is configured and DnsChallenge.ContactEmail is empty."
        }

        New-PAAccount -AcceptTOS -Contact $dns.ContactEmail -ErrorAction Stop | Out-Null
    }

    $pluginArgs = Resolve-CompleteViewPluginArgs -Config $Config
    $newParams = @{
        Domain = $domains
        Plugin = $dns.Plugin
        DnsSleep = [int]$dns.PropagationSeconds
        FriendlyName = $friendlyName
        Install = $false
        Verbose = $true
    }

    if ($pluginArgs.Count -gt 0) {
        $newParams['PluginArgs'] = $pluginArgs
    }

    if ($Force -or $existing) {
        $newParams['Force'] = $true
    }

    Write-Log "Requesting CompleteView certificate for domains: $($domains -join ', ')" -Level 'Info'
    $cert = New-PACertificate @newParams
    if (-not $cert) {
        throw "Posh-ACME did not return a certificate object for the CompleteView deployment."
    }

    Get-PACertificate -MainDomain $mainDomain -ErrorAction Stop
}

function Send-CompleteViewDeploymentNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Subject,
        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    $renewalConfig = Get-RenewalConfig
    if (-not $renewalConfig.EmailNotifications -or [string]::IsNullOrWhiteSpace($renewalConfig.NotificationEmail)) {
        return
    }

    Send-RenewalNotification -Subject $Subject -Body $Body -ToEmail $renewalConfig.NotificationEmail | Out-Null
}

function Invoke-CompleteViewDeploymentRun {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [object]$Config = (Get-CompleteViewDeploymentConfig),
        [switch]$Force,
        [switch]$SkipCertificateRequest,
        [switch]$DryRun
    )

    if (-not $Config.Enabled) {
        throw "CompleteView deployment is disabled. Run Initialize-CompleteViewDeployment first."
    }

    $runId = New-CompleteViewRunId
    $runState = [ordered]@{
        RunId = $runId
        StartedAt = (Get-Date).ToString('o')
        ManagementServer = $null
        RecordingServers = @()
        Certificate = $null
        Success = $false
        PartialFailure = $false
        DryRun = [bool]$DryRun
    }

    try {
        $preflight = Test-CompleteViewDeployment -Config $Config
        if (-not $preflight.OverallSuccess) {
            throw "CompleteView preflight validation failed."
        }

        if ($DryRun) {
            $runState.Success = $true
            $runState.CompletedAt = (Get-Date).ToString('o')
            return [pscustomobject]$runState
        }

        if ($SkipCertificateRequest) {
            $pacertificate = Get-PACertificate -MainDomain (Resolve-CompleteViewMainDomain -Config $Config) -ErrorAction Stop
        }
        else {
            $pacertificate = Invoke-CompleteViewCertificateRequest -Config $Config -Force:$Force
        }

        $runState.Certificate = [ordered]@{
            MainDomain = $pacertificate.MainDomain
            Thumbprint = $pacertificate.Certificate.Thumbprint
            NotAfter = $pacertificate.Certificate.NotAfter.ToString('o')
            Domains = @($pacertificate.AllSANs)
        }

        $artifacts = Export-CompleteViewPemArtifacts -PACertificate $pacertificate -Config $Config -RunId $runId
        $runState.ManagementServer = Install-CompleteViewManagementServerCertificate -PACertificate $pacertificate -Config $Config

        $failedServers = 0
        foreach ($server in @($Config.CompleteViewDeployment.RecordingServers)) {
            if (-not $server.Enabled) {
                continue
            }

            $serverResult = Install-CompleteViewRecordingServerCertificate -RecordingServer $server -Artifacts $artifacts -Config $Config -ExpectedThumbprint $pacertificate.Certificate.Thumbprint
            $runState.RecordingServers += $serverResult
            if (-not $serverResult.Success) {
                $failedServers++
            }
        }

        $runState.PartialFailure = $failedServers -gt 0
        $runState.Success = $failedServers -eq 0 -and $runState.ManagementServer.Success
        $runState.CompletedAt = (Get-Date).ToString('o')

        $state = Get-CompleteViewDeploymentState
        $runs = @($state.Runs)
        $runs += [pscustomobject]$runState
        $state.LastRunId = $runId
        $state.LastRun = [pscustomobject]$runState
        $state.Runs = $runs
        Save-CompleteViewDeploymentState -State $state | Out-Null

        if ($runState.Success) {
            Send-CompleteViewDeploymentNotification -Subject "CompleteView certificate deployment succeeded" -Body "Run $runId succeeded for $($pacertificate.MainDomain)."
        }
        elseif ($runState.PartialFailure) {
            Send-CompleteViewDeploymentNotification -Subject "CompleteView certificate deployment partially failed" -Body "Run $runId renewed $($pacertificate.MainDomain) but one or more Recording Server deployments failed."
        }

        [pscustomobject]$runState
    }
    catch {
        $runState.CompletedAt = (Get-Date).ToString('o')
        $runState.Error = $_.Exception.Message
        $runState.Success = $false

        $state = Get-CompleteViewDeploymentState
        $runs = @($state.Runs)
        $runs += [pscustomobject]$runState
        $state.LastRunId = $runId
        $state.LastRun = [pscustomobject]$runState
        $state.Runs = $runs
        Save-CompleteViewDeploymentState -State $state | Out-Null

        Send-CompleteViewDeploymentNotification -Subject "CompleteView certificate deployment failed" -Body "Run $runId failed: $($_.Exception.Message)"
        throw
    }
}

function Initialize-CompleteViewDeployment {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$BaseDomain,
        [string]$ManagementServerFqdn,
        [string[]]$RecordingServerHosts,
        [string]$DnsPlugin = 'Manual',
        [string]$DnsCredentialName,
        [string]$ContactEmail,
        [switch]$UseWildcard,
        [switch]$NonInteractive,
        [switch]$Force
    )

    $config = Get-CompleteViewDeploymentConfig
    if ($config.Enabled -and -not $Force) {
        Write-Warning "CompleteView deployment configuration already exists. Use -Force to overwrite."
        return $config
    }

    $defaults = Get-CompleteViewDefaultDeploymentConfig
    $config = [pscustomobject]$defaults

    if (-not $NonInteractive) {
        Write-Host "`n=== CompleteView Deployment Initialization ===" -ForegroundColor Cyan
        if (-not $BaseDomain) {
            $BaseDomain = Read-Host "Base certificate domain (e.g. example.com)"
        }
        if (-not $ManagementServerFqdn) {
            $ManagementServerFqdn = Read-Host "Management Server FQDN [$env:COMPUTERNAME]"
            if (-not $ManagementServerFqdn) {
                $ManagementServerFqdn = $env:COMPUTERNAME
            }
        }
        if (-not $RecordingServerHosts) {
            $recordingServerInput = Read-Host "Recording Server FQDNs (comma separated, blank for none)"
            if ($recordingServerInput) {
                $RecordingServerHosts = @($recordingServerInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
        }
        if (-not $ContactEmail) {
            $ContactEmail = Read-Host "Let's Encrypt contact email"
        }
        if (-not $DnsCredentialName -and $DnsPlugin -ne 'Manual') {
            $DnsCredentialName = Read-Host "Stored DNS credential name (blank to use inline plugin args later)"
        }
        if (-not $PSBoundParameters.ContainsKey('UseWildcard')) {
            $UseWildcard = (Read-Host "Use wildcard certificate? (Y/N) [Y]") -notmatch '^[Nn]$'
        }
    }

    if ([string]::IsNullOrWhiteSpace($BaseDomain)) {
        throw "BaseDomain is required."
    }

    $config.Enabled = $true
    $config.CompleteViewDeployment.CertificateOrders.BaseDomain = $BaseDomain.Trim()
    $config.CompleteViewDeployment.CertificateOrders.UseWildcard = [bool]$UseWildcard
    $config.CompleteViewDeployment.ManagementServer.Fqdn = $ManagementServerFqdn
    $config.CompleteViewDeployment.DnsChallenge.Plugin = $DnsPlugin
    $config.CompleteViewDeployment.DnsChallenge.Provider = $DnsPlugin
    $config.CompleteViewDeployment.DnsChallenge.CredentialName = $DnsCredentialName
    $config.CompleteViewDeployment.DnsChallenge.ContactEmail = $ContactEmail

    $rsInstall = Get-CompleteViewKnownInstallations
    $recordingServers = @()
    foreach ($host in @($RecordingServerHosts)) {
        $recordingServers += [pscustomobject]@{
            Name = $host
            Fqdn = $host
            ComputerName = $host
            CertificateFolder = $rsInstall.RecordingServerCertificateFolder
            ServiceName = $rsInstall.RecordingServerServiceName
            SecurePort = 4503
            RestartService = $true
            VerifyAfterDeploy = $true
            Enabled = $true
            ConfigurationFilePath = $null
        }
    }
    $config.CompleteViewDeployment.RecordingServers = $recordingServers

    Save-CompleteViewDeploymentConfig -Config $config | Out-Null
    $config
}

function Install-CompleteViewCertificates {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Force,
        [switch]$DryRun
    )

    $config = Get-CompleteViewDeploymentConfig
    Invoke-CompleteViewDeploymentRun -Config $config -Force:$Force -DryRun:$DryRun
}

function Update-CompleteViewCertificates {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Force,
        [switch]$DryRun
    )

    $config = Get-CompleteViewDeploymentConfig
    Invoke-CompleteViewDeploymentRun -Config $config -Force:$Force -DryRun:$DryRun
}

function Write-CompleteViewMenuHeader {
    [CmdletBinding()]
    param(
        [string]$Title = 'COMPLETEVIEW DEPLOYMENT'
    )

    $line = '=' * 70
    Write-Host ("`n{0}" -f $line) -ForegroundColor Cyan
    Write-Host ("    {0}" -f $Title) -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
}

function Get-CompleteViewDeploymentSummary {
    [CmdletBinding()]
    param(
        [object]$Config = (Get-CompleteViewDeploymentConfig),
        [object]$State = (Get-CompleteViewDeploymentState)
    )

    $enabledServers = @($Config.CompleteViewDeployment.RecordingServers | Where-Object { $_.Enabled })
    $lastRun = $State.LastRun
    $lastRunLabel = 'Never'
    $lastRunStatus = 'NotRun'

    if ($lastRun) {
        $lastRunLabel = $lastRun.CompletedAt
        if ($lastRun.Success) {
            $lastRunStatus = 'Success'
        }
        elseif ($lastRun.PartialFailure) {
            $lastRunStatus = 'PartialFailure'
        }
        else {
            $lastRunStatus = 'Failed'
        }
    }

    [pscustomobject]@{
        Enabled = [bool]$Config.Enabled
        DeploymentName = $Config.DeploymentName
        BaseDomain = $Config.CompleteViewDeployment.CertificateOrders.BaseDomain
        UseWildcard = [bool]$Config.CompleteViewDeployment.CertificateOrders.UseWildcard
        ManagementServerFqdn = $Config.CompleteViewDeployment.ManagementServer.Fqdn
        ManagementServerService = $Config.CompleteViewDeployment.ManagementServer.ServiceName
        RecordingServerCount = $enabledServers.Count
        DnsPlugin = $Config.CompleteViewDeployment.DnsChallenge.Plugin
        ContactEmail = $Config.CompleteViewDeployment.DnsChallenge.ContactEmail
        LastRun = $lastRunLabel
        LastRunStatus = $lastRunStatus
        LastThumbprint = if ($lastRun -and $lastRun.Certificate) { $lastRun.Certificate.Thumbprint } else { '' }
    }
}

function Show-CompleteViewDeploymentSummary {
    [CmdletBinding()]
    param(
        [object]$Config = (Get-CompleteViewDeploymentConfig),
        [object]$State = (Get-CompleteViewDeploymentState)
    )

    $summary = Get-CompleteViewDeploymentSummary -Config $Config -State $State
    $statusColor = switch ($summary.LastRunStatus) {
        'Success' { 'Green' }
        'PartialFailure' { 'Yellow' }
        'Failed' { 'Red' }
        default { 'DarkGray' }
    }
    $enabledColor = if ($summary.Enabled) { 'Green' } else { 'Yellow' }

    Write-Host ("Deployment: {0}" -f $summary.DeploymentName) -ForegroundColor White
    Write-Host ("Enabled: " ) -ForegroundColor Gray -NoNewline
    Write-Host ($(if ($summary.Enabled) { 'Yes' } else { 'No' })) -ForegroundColor $enabledColor
    Write-Host ("Base domain: {0}" -f $(if ($summary.BaseDomain) { $summary.BaseDomain } else { 'Not configured' })) -ForegroundColor Gray
    Write-Host ("Wildcard order: {0}" -f $(if ($summary.UseWildcard) { 'Enabled' } else { 'Disabled' })) -ForegroundColor Gray
    Write-Host ("Management Server: {0}" -f $(if ($summary.ManagementServerFqdn) { $summary.ManagementServerFqdn } else { 'Not configured' })) -ForegroundColor Gray
    Write-Host ("Recording Servers: {0}" -f $summary.RecordingServerCount) -ForegroundColor Gray
    Write-Host ("DNS plugin: {0}" -f $(if ($summary.DnsPlugin) { $summary.DnsPlugin } else { 'Not configured' })) -ForegroundColor Gray
    Write-Host ("Contact email: {0}" -f $(if ($summary.ContactEmail) { $summary.ContactEmail } else { 'Not configured' })) -ForegroundColor Gray
    Write-Host ("Last run: " ) -ForegroundColor Gray -NoNewline
    Write-Host $summary.LastRun -ForegroundColor White -NoNewline
    Write-Host "  [" -ForegroundColor DarkGray -NoNewline
    Write-Host $summary.LastRunStatus -ForegroundColor $statusColor -NoNewline
    Write-Host "]" -ForegroundColor DarkGray

    if ($summary.LastThumbprint) {
        Write-Host ("Last thumbprint: {0}" -f $summary.LastThumbprint) -ForegroundColor Gray
    }
}

function Show-CompleteViewDeploymentConfigView {
    [CmdletBinding()]
    param(
        [object]$Config = (Get-CompleteViewDeploymentConfig)
    )

    $ms = $Config.CompleteViewDeployment.ManagementServer
    $dns = $Config.CompleteViewDeployment.DnsChallenge
    $remote = $Config.CompleteViewDeployment.RemoteExecution
    $options = $Config.CompleteViewDeployment.DeploymentOptions

    Write-CompleteViewMenuHeader -Title 'COMPLETEVIEW CONFIGURATION'
    Write-Host 'Management Server' -ForegroundColor Yellow
    Write-Host ("  FQDN: {0}" -f $ms.Fqdn) -ForegroundColor White
    Write-Host ("  Computer: {0}" -f $ms.ComputerName) -ForegroundColor White
    Write-Host ("  Service: {0}" -f $ms.ServiceName) -ForegroundColor White
    Write-Host ("  HTTPS port: {0}" -f $ms.HttpsPort) -ForegroundColor White
    Write-Host ("  AppSettings: {0}" -f $ms.AppSettingsPath) -ForegroundColor White
    Write-Host ("  Store: {0}\\{1}" -f $ms.CertificateStore.StoreLocation, $ms.CertificateStore.StoreName) -ForegroundColor White
    Write-Host ("  Friendly name: {0}" -f $ms.CertificateStore.FriendlyName) -ForegroundColor White
    Write-Host ''

    Write-Host 'Certificate Order' -ForegroundColor Yellow
    Write-Host ("  Base domain: {0}" -f $Config.CompleteViewDeployment.CertificateOrders.BaseDomain) -ForegroundColor White
    Write-Host ("  Wildcard: {0}" -f $(if ($Config.CompleteViewDeployment.CertificateOrders.UseWildcard) { 'Yes' } else { 'No' })) -ForegroundColor White
    Write-Host ("  Main domain: {0}" -f (Resolve-CompleteViewMainDomain -Config $Config)) -ForegroundColor White
    $domains = Get-CompleteViewCertificateDomains -Config $Config
    Write-Host ("  Domains: {0}" -f ($domains -join ', ')) -ForegroundColor White
    Write-Host ''

    Write-Host 'DNS Challenge' -ForegroundColor Yellow
    Write-Host ("  Plugin: {0}" -f $dns.Plugin) -ForegroundColor White
    Write-Host ("  Credential: {0}" -f $(if ($dns.CredentialName) { $dns.CredentialName } else { 'Inline/none' })) -ForegroundColor White
    Write-Host ("  Contact email: {0}" -f $(if ($dns.ContactEmail) { $dns.ContactEmail } else { 'Not configured' })) -ForegroundColor White
    Write-Host ("  Propagation wait: {0}s" -f $dns.PropagationSeconds) -ForegroundColor White
    Write-Host ''

    Write-Host 'Remote Execution' -ForegroundColor Yellow
    Write-Host ("  Enabled: {0}" -f $(if ($remote.Enabled) { 'Yes' } else { 'No' })) -ForegroundColor White
    Write-Host ("  Use SSL: {0}" -f $(if ($remote.UseSsl) { 'Yes' } else { 'No' })) -ForegroundColor White
    Write-Host ("  Timeout: {0}s" -f $remote.OperationTimeoutSeconds) -ForegroundColor White
    Write-Host ''

    Write-Host 'Deployment Options' -ForegroundColor Yellow
    Write-Host ("  Artifact root: {0}" -f $options.ArtifactRoot) -ForegroundColor White
    Write-Host ("  RS cert file: {0}" -f $options.RecordingServerCertificateFileName) -ForegroundColor White
    Write-Host ("  RS key file: {0}" -f $options.RecordingServerPrivateKeyFileName) -ForegroundColor White
    Write-Host ("  Continue on RS failure: {0}" -f $(if ($options.ContinueOnRecordingServerFailure) { 'Yes' } else { 'No' })) -ForegroundColor White
    Write-Host ("  Update MS appsettings: {0}" -f $(if ($options.UpdateManagementServerAppSettings) { 'Yes' } else { 'No' })) -ForegroundColor White
    Write-Host ("  Update RS config: {0}" -f $(if ($options.UpdateRecordingServerConfig) { 'Yes' } else { 'No' })) -ForegroundColor White
    Write-Host ''

    Write-Host 'Recording Servers' -ForegroundColor Yellow
    if (@($Config.CompleteViewDeployment.RecordingServers).Count -eq 0) {
        Write-Host '  None configured' -ForegroundColor DarkGray
    }
    else {
        foreach ($server in @($Config.CompleteViewDeployment.RecordingServers)) {
            $serverColor = if ($server.Enabled) { 'White' } else { 'DarkGray' }
            $serverState = if ($server.Enabled) { 'Enabled' } else { 'Disabled' }
            Write-Host ("  {0} [{1}]" -f $server.Name, $serverState) -ForegroundColor $serverColor
            Write-Host ("    FQDN: {0}" -f $server.Fqdn) -ForegroundColor $serverColor
            Write-Host ("    Computer: {0}" -f $server.ComputerName) -ForegroundColor $serverColor
            Write-Host ("    Service: {0}" -f $server.ServiceName) -ForegroundColor $serverColor
            Write-Host ("    Port: {0}" -f $server.SecurePort) -ForegroundColor $serverColor
            Write-Host ("    Cert folder: {0}" -f $server.CertificateFolder) -ForegroundColor $serverColor
        }
    }
}

function Show-CompleteViewRunResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Result
    )

    $title = if ($Result.DryRun) { 'COMPLETEVIEW DRY RUN RESULT' } else { 'COMPLETEVIEW DEPLOYMENT RESULT' }
    Write-CompleteViewMenuHeader -Title $title

    $statusLabel = if ($Result.Success) {
        'Success'
    }
    elseif ($Result.PartialFailure) {
        'Partial Failure'
    }
    else {
        'Failed'
    }
    $statusColor = if ($Result.Success) { 'Green' } elseif ($Result.PartialFailure) { 'Yellow' } else { 'Red' }

    Write-Host ("Run ID: {0}" -f $Result.RunId) -ForegroundColor White
    Write-Host ("Status: " ) -ForegroundColor Gray -NoNewline
    Write-Host $statusLabel -ForegroundColor $statusColor
    Write-Host ("Started: {0}" -f $Result.StartedAt) -ForegroundColor Gray
    Write-Host ("Completed: {0}" -f $Result.CompletedAt) -ForegroundColor Gray

    if ($Result.Certificate) {
        Write-Host ''
        Write-Host 'Certificate' -ForegroundColor Yellow
        Write-Host ("  Main domain: {0}" -f $Result.Certificate.MainDomain) -ForegroundColor White
        Write-Host ("  Thumbprint: {0}" -f $Result.Certificate.Thumbprint) -ForegroundColor White
        Write-Host ("  Expires: {0}" -f $Result.Certificate.NotAfter) -ForegroundColor White
    }

    if ($Result.ManagementServer) {
        Write-Host ''
        Write-Host 'Management Server' -ForegroundColor Yellow
        Write-Host ("  Status: {0}" -f $(if ($Result.ManagementServer.Success) { 'Success' } else { 'Failed' })) -ForegroundColor $(if ($Result.ManagementServer.Success) { 'Green' } else { 'Red' })
        if ($Result.ManagementServer.Thumbprint) {
            Write-Host ("  Thumbprint: {0}" -f $Result.ManagementServer.Thumbprint) -ForegroundColor White
        }
        if ($Result.ManagementServer.Verification) {
            Write-Host ("  Verified subject: {0}" -f $Result.ManagementServer.Verification.Subject) -ForegroundColor White
        }
    }

    Write-Host ''
    Write-Host 'Recording Servers' -ForegroundColor Yellow
    if (@($Result.RecordingServers).Count -eq 0) {
        Write-Host '  No Recording Servers were targeted' -ForegroundColor DarkGray
    }
    else {
        foreach ($serverResult in @($Result.RecordingServers)) {
            $serverColor = if ($serverResult.Success) { 'Green' } else { 'Red' }
            Write-Host ("  {0}: {1}" -f $serverResult.Name, $(if ($serverResult.Success) { 'Success' } else { 'Failed' })) -ForegroundColor $serverColor
            if ($serverResult.Verification) {
                Write-Host ("    Verified subject: {0}" -f $serverResult.Verification.Subject) -ForegroundColor White
            }
            if ($serverResult.Error) {
                Write-Host ("    Error: {0}" -f $serverResult.Error) -ForegroundColor Red
            }
        }
    }

    if ($Result.Error) {
        Write-Host ''
        Write-Host ("Error: {0}" -f $Result.Error) -ForegroundColor Red
    }
}

function Show-CompleteViewDeploymentMenu {
    [CmdletBinding()]
    param()

    while ($true) {
        Clear-Host
        $config = Get-CompleteViewDeploymentConfig
        $state = Get-CompleteViewDeploymentState

        Write-CompleteViewMenuHeader
        Show-CompleteViewDeploymentSummary -Config $config -State $state
        Write-Host ''
        Write-Host 'Actions' -ForegroundColor Yellow
        Write-Host "  1. Initialize deployment" -ForegroundColor White
        Write-Host "  2. Test deployment" -ForegroundColor White
        Write-Host "  3. Install certificates now" -ForegroundColor White
        Write-Host "  4. Renew/update certificates now" -ForegroundColor White
        Write-Host "  5. View deployment config" -ForegroundColor White
        Write-Host "0. Back" -ForegroundColor White

        $choice = Get-ValidatedInput -Prompt "`nSelect an option (0-5)" -ValidOptions (0..5)
        switch ($choice) {
            0 { return }
            1 {
                $initializedConfig = Initialize-CompleteViewDeployment
                Show-CompleteViewDeploymentConfigView -Config $initializedConfig
                Read-Host "Press Enter to continue"
            }
            2 {
                Write-CompleteViewMenuHeader -Title 'COMPLETEVIEW PREFLIGHT CHECK'
                Test-CompleteViewDeployment -Detailed | Out-Null
                Read-Host "Press Enter to continue"
            }
            3 {
                $result = Install-CompleteViewCertificates
                Show-CompleteViewRunResult -Result $result
                Read-Host "Press Enter to continue"
            }
            4 {
                $result = Update-CompleteViewCertificates
                Show-CompleteViewRunResult -Result $result
                Read-Host "Press Enter to continue"
            }
            5 {
                Show-CompleteViewDeploymentConfigView -Config $config
                Read-Host "Press Enter to continue"
            }
        }
    }
}
