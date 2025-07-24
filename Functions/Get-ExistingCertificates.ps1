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
        Write-Warning -Message "No existing certificates found."
        return $null
    }
    if ($ShowMenu) {
        # Interactive menu mode
        Write-Information -MessageData "Available certificates:" -InformationAction Continue
        Write-Information -MessageData "" -InformationAction Continue
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
                Write-Host -Object "  $($i + 1). $($order.MainDomain)" -ForegroundColor White
                if ($cert.Certificate) {
                    Write-Host -Object "      Expires: $($cert.Certificate.NotAfter) ($daysUntilExpiry days)" -ForegroundColor $expiryColor
                    Write-Host -Object "      SANs: $($order.AllDnsNames -join ', ')" -ForegroundColor Gray
                } else {
                    Write-Error -Message "      Status: No local certificate file"
                }
                Write-Information -MessageData "" -InformationAction Continue
            } catch {
                Write-Host -Object "  $($i + 1). $($order.MainDomain)" -ForegroundColor White
                Write-Error -Message "      Status: Error retrieving details"
                Write-Information -MessageData "" -InformationAction Continue
            }
        }
        Write-Host -Object "0. Cancel / Return to previous menu" -ForegroundColor DarkRed
        Write-Information -MessageData "" -InformationAction Continue
        $choice = Read-Host "Select a certificate to manage (1-$($orders.Count))"
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) {
            return $null
        }
        $choiceNum = 0
        if ([int]::TryParse($choice, [ref]$choiceNum) -and $choiceNum -ge 1 -and $choiceNum -le $orders.Count) {
            return $orders[$choiceNum - 1]
        } else {
            Write-Error -Message "Invalid selection."
            return $null
        }
    } else {
        # Standard listing mode
        foreach ($order in $orders) {
            try {
                $cert = Get-PACertificate -MainDomain $order.MainDomain
                Write-Host -Object "`nOrder Name: $($order.OrderName)" -ForegroundColor Cyan
                Write-Host -Object "Main Domain: $($order.MainDomain)" -ForegroundColor White
                Write-Host -Object "Alternative Names: $($order.AllDnsNames -join ', ')" -ForegroundColor Gray
                if ($cert.Certificate) {
                    $daysUntilExpiry = ($cert.Certificate.NotAfter - (Get-Date)).Days
                    $expiryColor = if ($daysUntilExpiry -le 7) {
                        "Red"
                    } elseif ($daysUntilExpiry -le 30) {
                        "Yellow"
                    } else {
                        "Green"
                    }
                    Write-Host -Object "Expires: $($cert.Certificate.NotAfter) ($daysUntilExpiry days remaining)" -ForegroundColor $expiryColor
                    Write-Host -Object "Issuer: $($cert.Certificate.Issuer)" -ForegroundColor Gray
                    Write-Host -Object "Thumbprint: $($cert.Certificate.Thumbprint)" -ForegroundColor Gray
                    Write-Host -Object "Serial Number: $($cert.Certificate.SerialNumber)" -ForegroundColor Gray
                    # Check if certificate is installed in store
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
                    $store.Open("ReadOnly")
                    $installedCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $cert.Certificate.Thumbprint }
                    $store.Close()
                    if ($installedCert) {
                        Write-Information -MessageData "Installation Status: Installed in LocalMachine\My store" -InformationAction Continue
                    } else {
                        Write-Warning -Message "Installation Status: Not installed in certificate store"
                    }
                } else {
                    Write-Error -Message "Status: No local certificate file. Possibly revoked or incomplete."
                }
                Write-Host -Object "Order Status: $($order.status)" -ForegroundColor $(if ($order.status -eq 'valid') { 'Green' } else { 'Yellow' })
                Write-Host -Object "Created: $($order.FinalizedDate)" -ForegroundColor Gray
                Write-Host -Object "-" * 70 -ForegroundColor DarkGray
            } catch {
                Write-Host -Object "`nOrder Name: $($order.OrderName)" -ForegroundColor Cyan
                Write-Host -Object "Main Domain: $($order.MainDomain)" -ForegroundColor White
                Write-Error -Message "Status: Error retrieving certificate details - $($_.Exception.Message)" -ForegroundColor Red
                Write-Host -Object "-" * 70 -ForegroundColor DarkGray
            }
        }
        Write-Host -Object "`nTotal certificates found: $($orders.Count)" -ForegroundColor Cyan
    }
}




