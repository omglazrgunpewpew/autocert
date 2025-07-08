<#
    .SYNOPSIS
        Lists all existing Posh-ACME certificates and displays relevant details.
        
    .PARAMETER ShowMenu
        Shows an interactive menu for certificate selection and returns the selected order.
#>

function Get-ExistingCertificates {
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [switch]$ShowMenu
    )
    
    Initialize-ACMEServer
    $orders = Get-PAOrder
    
    if (-not $orders) {
        Write-Host "No existing certificates found." -ForegroundColor Yellow
        return $null
    }
    
    if ($ShowMenu) {
        # Interactive menu mode
        Write-Host "Available certificates:" -ForegroundColor Green
        Write-Host ""
        
        for ($i = 0; $i -lt $orders.Count; $i++) {
            $order = $orders[$i]
            try {
                $cert = Get-PACertificate -MainDomain $order.MainDomain
                $daysUntilExpiry = if ($cert.Certificate) { 
                    ($cert.Certificate.NotAfter - (Get-Date)).Days 
                } else { 
                    "Unknown" 
                }
                
                $expiryColor = if ($daysUntilExpiry -eq "Unknown") {
                    "Gray"
                } elseif ($daysUntilExpiry -le 7) {
                    "Red"
                } elseif ($daysUntilExpiry -le 30) {
                    "Yellow"
                } else {
                    "Green"
                }
                
                Write-Host "  $($i + 1). $($order.MainDomain)" -ForegroundColor White
                if ($cert.Certificate) {
                    Write-Host "      Expires: $($cert.Certificate.NotAfter) ($daysUntilExpiry days)" -ForegroundColor $expiryColor
                    Write-Host "      SANs: $($order.AllDnsNames -join ', ')" -ForegroundColor Gray
                } else {
                    Write-Host "      Status: No local certificate file" -ForegroundColor Red
                }
                Write-Host ""
            } catch {
                Write-Host "  $($i + 1). $($order.MainDomain)" -ForegroundColor White
                Write-Host "      Status: Error retrieving details" -ForegroundColor Red
                Write-Host ""
            }
        }
        
        Write-Host "0. Cancel / Return to previous menu" -ForegroundColor DarkRed
        Write-Host ""
        
        $choice = Read-Host "Select a certificate to manage (1-$($orders.Count))"
        
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) {
            return $null
        }
        
        $choiceNum = 0
        if ([int]::TryParse($choice, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $orders.Count) {
            return $orders[$choiceNum - 1]
        } else {
            Write-Host "Invalid selection." -ForegroundColor Red
            return $null
        }
    } else {
        # Standard listing mode
        foreach ($order in $orders) {
            try {
                $cert = Get-PACertificate -MainDomain $order.MainDomain
                Write-Host "`nOrder Name: $($order.OrderName)" -ForegroundColor Cyan
                Write-Host "Main Domain: $($order.MainDomain)" -ForegroundColor White
                Write-Host "Alternative Names: $($order.AllDnsNames -join ', ')" -ForegroundColor Gray
                
                if ($cert.Certificate) {
                    $daysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                    $expiryColor = if ($daysUntilExpiry -le 7) {
                        "Red"
                    } elseif ($daysUntilExpiry -le 30) {
                        "Yellow"
                    } else {
                        "Green"
                    }
                    
                    Write-Host "Expires: $($cert.Certificate.NotAfter) ($daysUntilExpiry days remaining)" -ForegroundColor $expiryColor
                    Write-Host "Issuer: $($cert.Certificate.Issuer)" -ForegroundColor Gray
                    Write-Host "Thumbprint: $($cert.Certificate.Thumbprint)" -ForegroundColor Gray
                    Write-Host "Serial Number: $($cert.Certificate.SerialNumber)" -ForegroundColor Gray
                    
                    # Check if certificate is installed in store
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                    $store.Open("ReadOnly")
                    $installedCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Certificate.Thumbprint }
                    $store.Close()
                    
                    if ($installedCert) {
                        Write-Host "Installation Status: Installed in LocalMachine\My store" -ForegroundColor Green
                    } else {
                        Write-Host "Installation Status: Not installed in certificate store" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Status: No local certificate file. Possibly revoked or incomplete." -ForegroundColor Red
                }
                
                Write-Host "Order Status: $($order.status)" -ForegroundColor $(if ($order.status -eq 'valid') { 'Green' } else { 'Yellow' })
                Write-Host "Created: $($order.FinalizedDate)" -ForegroundColor Gray
                Write-Host "-" * 70 -ForegroundColor DarkGray
                
            } catch {
                Write-Host "`nOrder Name: $($order.OrderName)" -ForegroundColor Cyan
                Write-Host "Main Domain: $($order.MainDomain)" -ForegroundColor White
                Write-Host "Status: Error retrieving certificate details - $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "-" * 70 -ForegroundColor DarkGray
            }
        }
        
        Write-Host "`nTotal certificates found: $($orders.Count)" -ForegroundColor Cyan
    }
}
