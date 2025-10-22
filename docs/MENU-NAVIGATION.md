# Menu Navigation System - Complete Structure

This document provides a complete map of all menu structures, navigation flows, and function linkages in the AutoCert system.

## Menu Hierarchy

```
Main Menu (Main.ps1:2886-2910)
├── 1. Register-Certificate
├── 2. Install-Certificate
├── 3. Set-AutomaticRenewal
├── 4. Certificate Management Menu ───┐
├── 5. Options Menu ──────────────────┼───┐
├── 6. Credential Management Menu ────┼───┼───┐
├── 7. Test-SystemHealth             │   │   │
├── S. Show-Help                      │   │   │
└── 0. Exit                           │   │   │
                                      │   │   │
    ┌─────────────────────────────────┘   │   │
    │                                     │   │
    ▼                                     │   │
Certificate Management Menu               │   │
(Main.ps1:2956-3451)                      │   │
├── 1. View all certificates              │   │
│       (Get-ExistingCertificates)        │   │
├── 2. Manage individual certificate ─┐   │   │
├── 3. Bulk renewal check             │   │   │
├── 4. Export certificates            │   │   │
├── 5. Revoke certificate             │   │   │
├── 6. Delete certificate             │   │   │
└── 0. Return to Main Menu            │   │   │
                                      │   │   │
    ┌─────────────────────────────────┘   │   │
    │                                     │   │
    ▼                                     │   │
Single Certificate Management             │   │
(Invoke-SingleCertificateManagement)      │   │
Main.ps1:2242-2320                        │   │
├── 1. Force Renew                        │   │
├── 2. Re-install Certificate             │   │
├── 3. Revoke Certificate                 │   │
├── 4. View Details                       │   │
└── 0. Return to Certificate Menu         │   │
                                          │   │
        ┌─────────────────────────────────┘   │
        │                                     │
        ▼                                     │
Options Menu                                  │
(Functions/Show-Options.ps1:5-50)            │
├── 1. Change ACME server ─────┐             │
│       (Set-ACMEServer)        │             │
└── 0. Back to Main Menu        │             │
                                │             │
    ┌───────────────────────────┘             │
    │                                         │
    ▼                                         │
Set ACME Server                               │
(Show-Options.ps1:23-50)                      │
├── 1. Let's Encrypt Production               │
├── 2. Let's Encrypt Staging                  │
└── 0. Back to Options                        │
                                              │
            ┌─────────────────────────────────┘
            │
            ▼
Credential Management Menu
(Main.ps1:2149-2240)
├── 1. Add new credential
├── 2. Remove credential
├── 3. Test credential
└── 0. Return to Main Menu

⚠️  ISSUE: This menu has NO LOOP!
    Will return to main menu after ONE action.
```

## Main Menu Options Mapping

### Entry Point: Main.ps1 Line 2886-2910

| Option | Label | Function Called | Location | Loop? | Status |
|--------|-------|-----------------|----------|-------|--------|
| 1 | Register Certificate | `Register-Certificate` | Functions/Register-Certificate.ps1:7 | No | ✅ Working |
| 2 | Install Certificate | `Install-Certificate` | Functions/Install-Certificate.ps1 | No | ✅ Working |
| 3 | Configure automatic renewal | `Set-AutomaticRenewal` | Functions/Set-AutomaticRenewal.ps1 | No | ✅ Working |
| 4 | View and Manage certificates | `Show-CertificateManagementMenu` | Main.ps1:2956 | Yes | ✅ Working |
| 5 | Options | `Show-Options` | Functions/Show-Options.ps1:5 | Yes | ✅ Working |
| 6 | Manage Credentials | `Show-CredentialManagementMenu` | Main.ps1:2149 | **NO** | ❌ **Missing Loop** |
| 7 | System health check | `Test-SystemHealth` | Core/SystemDiagnostics.ps1:4 | No | ✅ Working |
| S | Help / About | `Show-Help` | UI/HelpSystem.ps1:16 | No | ✅ Working |
| 0 | Exit | Exit 0 | Built-in | N/A | ✅ Working |

## Certificate Management Submenu

### Entry Point: Main.ps1 Line 2956-3451

| Option | Label | Function Called | Location | Status |
|--------|-------|-----------------|----------|--------|
| 1 | View all certificates | `Get-ExistingCertificates` | Functions/Get-ExistingCertificates.ps1:9 | ✅ Working |
| 2 | Manage individual cert | `Invoke-SingleCertificateManagement` | Main.ps1:2242 | ✅ Working |
| 3 | Bulk renewal check | Inline code | Main.ps1:3029-3066 | ✅ Working |
| 4 | Export certificates | Inline code | Main.ps1:3067-3241 | ✅ Working |
| 5 | Revoke certificate | `Revoke-Certificate` | Functions/Revoke-Certificate.ps1 | ✅ Working |
| 6 | Delete certificate | `Remove-Certificate` | Functions/Remove-Certificate.ps1 | ✅ Working |
| 0 | Return to Main Menu | return | Built-in | ✅ Working |

## Single Certificate Management Submenu

### Entry Point: Main.ps1 Line 2242-2320

| Option | Label | Function Called | Location | Status |
|--------|-------|-----------------|----------|--------|
| 1 | Force Renew | `New-PACertificate` | Posh-ACME Module | ✅ Working |
| 2 | Re-install Certificate | `Install-Certificate` | Functions/Install-Certificate.ps1 | ✅ Working |
| 3 | Revoke Certificate | `Revoke-Certificate` | Functions/Revoke-Certificate.ps1 | ✅ Working |
| 4 | View Details | `Get-PAOrder \| Format-List` | Posh-ACME Module | ✅ Working |
| 0 | Return to Certificate Menu | return | Built-in | ✅ Working |

## Options Submenu

### Entry Point: Functions/Show-Options.ps1 Line 5-50

| Option | Label | Function Called | Location | Status |
|--------|-------|-----------------|----------|--------|
| 1 | Change ACME server | `Set-ACMEServer` | Show-Options.ps1:23 | ✅ Working |
| 0 | Back | return | Built-in | ✅ Working |

### Set ACME Server (called from Options)

| Option | Label | Function Called | Status |
|--------|-------|-----------------|--------|
| 1 | Let's Encrypt Production | `Set-PAServer LE_PROD` | ✅ Working |
| 2 | Let's Encrypt Staging | `Set-PAServer LE_STAGING` | ✅ Working |
| 0 | Back | return | ✅ Working |

## Credential Management Submenu

### Entry Point: Main.ps1 Line 2149-2240

| Option | Label | Function Called | Location | Status |
|--------|-------|-----------------|----------|--------|
| 1 | Add new credential | Inline code | Main.ps1:2176-2191 | ⚠️ Works once |
| 2 | Remove credential | `Remove-StoredCredential` | Functions/Manage-Credentials.ps1:140 | ⚠️ Works once |
| 3 | Test credential | Inline code | Main.ps1:2210-2233 | ⚠️ Works once |
| 0 | Return to Main Menu | return | Built-in | ✅ Working |

**CRITICAL ISSUE:** This menu has NO `while ($true)` loop, so it only executes ONCE then returns to main menu. User must re-enter the menu for each operation.

## Required Functions Verification

All functions called from menus exist and are properly loaded:

### From Main.ps1 Module Loading (Line 92-125)

| Function | Source File | Loaded Line | Status |
|----------|-------------|-------------|--------|
| `Register-Certificate` | Functions/Register-Certificate.ps1 | 116 | ✅ Loaded |
| `Install-Certificate` | Functions/Install-Certificate.ps1 | 117 | ✅ Loaded |
| `Set-AutomaticRenewal` | Functions/Set-AutomaticRenewal.ps1 | 121 | ✅ Loaded |
| `Get-ExistingCertificates` | Functions/Get-ExistingCertificates.ps1 | 120 | ✅ Loaded |
| `Revoke-Certificate` | Functions/Revoke-Certificate.ps1 | 118 | ✅ Loaded |
| `Remove-Certificate` | Functions/Remove-Certificate.ps1 | 119 | ✅ Loaded |
| `Show-Options` | Functions/Show-Options.ps1 | 122 | ✅ Loaded |
| `Manage-Credentials` | Functions/Manage-Credentials.ps1 | 124 | ✅ Loaded |
| `Test-SystemHealth` | Core/SystemDiagnostics.ps1 | Loaded via Core | ✅ Loaded |
| `Show-Help` | UI/HelpSystem.ps1 | 108 | ✅ Loaded |
| `Get-StoredCredential` | Functions/Manage-Credentials.ps1 | 102 (function) | ✅ Available |
| `Remove-StoredCredential` | Functions/Manage-Credentials.ps1 | 140 (function) | ✅ Available |
| `Get-CertificateRenewalStatus` | Core/RenewalConfig.ps1 | 170 (function) | ✅ Available |

## Issues Found

### 🔴 Critical Issues

1. **Show-CredentialManagementMenu Missing Loop**
   - **Location:** Main.ps1:2149-2240
   - **Problem:** No `while ($true)` loop
   - **Impact:** Menu only executes once, then returns to main menu
   - **Fix:** Wrap entire menu body in `while ($true) { ... }`

### ⚠️ Security Issues

2. **Password Displayed in Plain Text**
   - **Location:** Main.ps1:2224
   - **Problem:** Test credential option shows password in plain text
   - **Impact:** Security risk if screen is visible to others
   - **Fix:** Mask password with asterisks or remove display

### 📝 Minor Issues

3. **Duplicate Function Definitions**
   - **Locations:** Show-CredentialManagementMenu at lines 621 and 2149
   - **Impact:** Confusing, wastes space, harder to maintain
   - **Fix:** Remove first definition, keep only the later one

4. **Inconsistent Return Behavior**
   - Some menus use `break` in loops
   - Others use `return`
   - **Impact:** Minor inconsistency
   - **Fix:** Standardize on `return` for exiting menus

## Navigation Flow Examples

### Example 1: Register New Certificate

```
User starts Main.ps1
  ↓
Show-Menu displays
  ↓
User enters "1"
  ↓
Register-Certificate called (Functions/Register-Certificate.ps1:7)
  ↓
[Certificate registration process with circuit breaker protection]
  ↓
Function completes and returns
  ↓
Back to Show-Menu (main loop continues)
```

### Example 2: Manage Individual Certificate

```
User at Main Menu
  ↓
User enters "4" (Certificate Management)
  ↓
Show-CertificateManagementMenu called (Main.ps1:2956)
  ↓
while ($true) loop starts
  ↓
User enters "2" (Manage individual)
  ↓
Get-ExistingCertificates -ShowMenu called
  ↓
User selects certificate
  ↓
Invoke-SingleCertificateManagement called (Main.ps1:2242)
  ↓
while ($true) loop starts
  ↓
User enters "1" (Force Renew)
  ↓
New-PACertificate executed
  ↓
Read-Host "Press Enter to continue"
  ↓
Loop continues, menu redisplays
  ↓
User enters "0"
  ↓
return exits Invoke-SingleCertificateManagement
  ↓
Back to Show-CertificateManagementMenu loop
  ↓
User enters "0"
  ↓
return exits Show-CertificateManagementMenu
  ↓
Back to Main Menu loop
```

### Example 3: Credential Management (BROKEN)

```
User at Main Menu
  ↓
User enters "6" (Manage Credentials)
  ↓
Show-CredentialManagementMenu called (Main.ps1:2149)
  ↓
❌ NO LOOP! Single execution only
  ↓
Menu displays with credential list
  ↓
User enters "1" (Add credential)
  ↓
Credential added
  ↓
Read-Host "Press Enter to continue"
  ↓
❌ Function ends, no loop to return to menu
  ↓
return exits Show-CredentialManagementMenu
  ↓
Back to Main Menu
  ↓
User must select option 6 again for next operation!
```

## Testing Checklist

- [ ] Main menu displays correctly
- [ ] Option 1: Register certificate - completes and returns to main menu
- [ ] Option 2: Install certificate - completes and returns to main menu
- [ ] Option 3: Set renewal - completes and returns to main menu
- [ ] Option 4: Certificate management submenu - loops correctly
  - [ ] All 6 sub-options work
  - [ ] Returns to main menu on option 0
- [ ] Option 5: Options submenu - loops correctly
  - [ ] ACME server change works
  - [ ] Returns to main menu on option 0
- [ ] Option 6: Credentials menu - ❌ **BROKEN - needs loop fix**
  - [ ] Add credential works (but returns to main menu)
  - [ ] Remove credential works (but returns to main menu)
  - [ ] Test credential works (but returns to main menu)
- [ ] Option 7: System health - completes and returns to main menu
- [ ] Option S: Help - displays and returns to main menu
- [ ] Option 0: Exit - terminates application

## Recommendations

### Immediate Fix Required

1. **Add Loop to Show-CredentialManagementMenu**
   ```powershell
   function Show-CredentialManagementMenu {
       while ($true) {  # ← ADD THIS
           Clear-Host
           # ... rest of menu code ...
       }  # ← ADD THIS
   }
   ```

2. **Mask Password in Test Credential**
   ```powershell
   # Change from:
   Write-Host -Object "  Password: $password" -ForegroundColor White

   # To:
   Write-Warning -Message "  Password: ******* (hidden for security)"
   ```

3. **Remove Duplicate Function Definitions**
   - Delete lines 621-719 (first Show-CredentialManagementMenu)
   - Keep only lines 2149-2240 (second definition)

### Future Improvements

1. **Consolidate Menu Functions**
   - Move all submenu functions to UI/ directory
   - Keep Main.ps1 focused on main execution loop

2. **Standardize Menu Patterns**
   - All menus should use `while ($true)` loops
   - All menus should use `return` to exit
   - Consistent error handling

3. **Add Menu Navigation History**
   - Track menu path for better user experience
   - Show "breadcrumb" navigation

## Related Documentation

- [CERTIFICATE-REGISTRATION-FLOW.md](./CERTIFICATE-REGISTRATION-FLOW.md) - Complete registration process
- [RELIABILITY.md](./RELIABILITY.md) - Circuit breaker and error handling
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - Common issues and solutions

---

**Last Updated:** 2025-10-22
**Status:** 🔴 **Critical Issue Found** - Credential Management Menu missing loop
**Action Required:** Fix Show-CredentialManagementMenu before production use
