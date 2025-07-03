# Autocert Utility

Autocert provides a set of PowerShell scripts for managing Let's Encrypt certificates using the [Posh-ACME](https://github.com/rmbolger/Posh-ACME) module. The utility can register new certificates, install them on local or remote servers, automate renewal via scheduled tasks and handle revocation.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+
- Internet access to retrieve the Posh-ACME module the first time

All required modules are automatically installed and updated when you run `Main.ps1`.

## Getting Started

1. Clone or download this repository.
2. Launch an elevated PowerShell prompt and run `Main.ps1`:
   ```powershell
   .\Main.ps1
   ```
3. Follow the interactive menu to request certificates or configure automatic renewal.

### Automatic Renewal

Running `Set-AutomaticRenewal` (option 3 in the menu) creates a scheduled task that calls:
```powershell
.\Main.ps1 -RenewAll
```
This renews all certificates and installs them using the same logic as manual issuance.

### Updating Posh-ACME

The utility stores a copy of the Posh-ACME module in the `Modules` directory. `Initialize-PoshAcme.ps1` automatically checks for new versions and updates both the installed module and the bundled copy.

## Advanced Functions

- **Revoke-Certificate** – revoke a certificate and mark it as revoked locally
- **Remove-Certificate** – delete an order from Posh-ACME storage
- **Show-AdvancedOptions** – switch between Let's Encrypt production and staging environments

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. Changes are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

