# Test-StyleGuideRules.ps1
# Test script to verify custom PSScriptAnalyzer rules are working

<#
.SYNOPSIS
    Tests the custom AutoCert style guide rules.

.DESCRIPTION
    This script contains examples of code that should trigger the custom
    PSScriptAnalyzer rules to verify they are working correctly.
#>

# Test marketing language in comments
# This is an enhanced function with advanced features
# This comprehensive solution provides intelligent processing

# Test marketing language in strings
function Test-MarketingLanguage {
    Write-Information -MessageData "Advanced certificate processing completed successfully!" -InformationAction Continue
    Write-Warning -Message "Enhanced validation with comprehensive checks"
    $message = "This sophisticated tool provides intelligent management"
    return $message
}

# Test verbose function names
function Get-AdvancedCertificateInformationWithEnhancedFeatures {
    # This should trigger the verbose function name rule
    return "test"
}

function Set-ComprehensiveConfigurationWithIntelligentValidation {
    # Another verbose function name
    return "test"
}

# Test "successfully" usage
function Test-SuccessfullyUsage {
    Write-Information -MessageData "Certificate installed successfully" -InformationAction Continue
    Write-Information -MessageData "Module loaded successfully" -InformationAction Continue
    Write-Log "Operation completed successfully" -Level 'Info'
}

# Test obvious comments (what instead of why)
function Test-CommentQuality {
    # Set $certificateThumbprint to the thumbprint value
    $certificateThumbprint = $cert.Thumbprint

    # Create $renewalDate variable
    $renewalDate = (Get-Date).AddDays(30)

    # Return $result
    return $result
}

# Test overly verbose variable names
function Test-VariableNaming {
    $advancedCertificateManagementSystemConfigurationPath = "C:\Config"
    $enhancedDnsProviderValidationWithComprehensiveChecking = $true
    $sophisticatedRenewalSchedulingWithIntelligentAlgorithms = @{}
}

# Good examples that should NOT trigger rules
function Get-Certificate {
    <#
    .SYNOPSIS
        Retrieves certificate information from the store.
    #>
    param([string]$Thumbprint)

    try {
        $cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $Thumbprint }
        Write-Information -MessageData "Certificate retrieved" -InformationAction Continue  # No "successfully"
        Write-Log "Certificate found: $Thumbprint" -Level 'Info'
        return $cert
    } catch {
        Write-Error -Message "Failed to retrieve certificate: $($_.Exception.Message)"
        return $null
    }
}



