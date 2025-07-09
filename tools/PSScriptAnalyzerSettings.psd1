# PSScriptAnalyzerSettings.psd1
# PowerShell Script Analyzer configuration for AutoCert project

@{
    # Global rule settings
    Rules = @{
        # Write-Host usage - should use Write-Information, Write-Verbose, or Write-Output
        PSAvoidUsingWriteHost = @{
            Enable = $true
        }
        
        # Function naming - should use singular nouns
        PSUseSingularNouns = @{
            Enable = $true
        }
        
        # Should use ShouldProcess for state-changing functions
        PSUseShouldProcessForStateChangingFunctions = @{
            Enable = $true
        }
        
        # Should declare OutputType attribute
        PSUseOutputTypeCorrectly = @{
            Enable = $true
        }
        
        # Avoid empty catch blocks
        PSAvoidUsingEmptyCatchBlock = @{
            Enable = $true
        }
        
        # Use CIM cmdlets instead of WMI
        PSAvoidUsingWMICmdlets = @{
            Enable = $true
        }
        
        # Use named parameters
        PSAvoidUsingPositionalParameters = @{
            Enable = $true
        }
        
        # Proper BOM encoding
        PSUseBOMForUnicodeEncodedFile = @{
            Enable = $true
        }
        
        # Avoid trailing whitespace
        PSAvoidTrailingWhitespace = @{
            Enable = $true
        }
        
        # Use declared variables
        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }
        
        # Review unused parameters
        PSReviewUnusedParameter = @{
            Enable = $true
        }
        
        # Consistent indentation (4 spaces, Allman style)
        PSUseConsistentIndentation = @{
            Enable = $true
            IndentationSize = 4
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            Kind = 'space'
        }
        
        # Consistent whitespace
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckSeparator = $true
        }
        
        # Allman style braces (opening brace on new line)
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $false
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }
        
        # Consistent closing brace placement
        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore = $false
        }
        
        # Align assignment statements
        PSAlignAssignmentStatement = @{
            Enable = $true
            CheckHashtable = $true
        }
        
        # Use correct casing for cmdlets
        PSUseCorrectCasing = @{
            Enable = $true
        }
    }
    
    # Rules to exclude (if any specific exemptions are needed)
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'  # Write-Host is used for interactive UI in this certificate management tool
    )
    
    # Include default rules
    IncludeDefaultRules = $true
    
    # Severity levels to report
    Severity = @(
        'Error',
        'Warning', 
        'Information'
    )
    
    # Custom rule paths for AutoCert style guide enforcement
    CustomRulePath = @(
        '.\CustomRules\AutoCertStyleRules.psm1'
    )
}
