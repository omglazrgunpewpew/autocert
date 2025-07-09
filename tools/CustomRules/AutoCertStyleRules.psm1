# AutoCertStyleRules.psm1
# Custom PSScriptAnalyzer rules for AutoCert style guide compliance

<#
.SYNOPSIS
    Custom PSScriptAnalyzer rules to enforce AutoCert style guide standards.

.DESCRIPTION
    This module contains custom rules that check for:
    - Marketing language in comments and strings
    - Use of "successfully" in status messages
    - Overly verbose function names
    - Non-factual log messages
#>

# Rule: Avoid marketing language in comments and strings
function Measure-AvoidMarketingLanguage {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $marketingWords = @(
        'Enhanced', 'Advanced', 'Improved', 'Comprehensive',
        'Sophisticated', 'Intelligent', 'Smart', 'Cutting-edge',
        'State-of-the-art', 'Next-generation', 'World-class',
        'Industry-leading', 'Enterprise-grade', 'Professional',
        'Premium', 'Superior', 'Exceptional', 'Outstanding',
        'Revolutionary', 'Innovative', 'Breakthrough',
        'Perfect', 'Ideal', 'Ultimate', 'Maximum', 'Complete'
    )

    $results = @()
    
    # Check comments for marketing language
    $comments = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.Token] -and $args[0].Kind -eq 'Comment' }, $true)
    foreach ($comment in $comments) {
        $commentText = $comment.Text
        foreach ($word in $marketingWords) {
            if ($commentText -match "\b$word\b") {
                $results += New-Object Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord (
                    "Avoid marketing language: '$word' in comments. Use direct, functional descriptions instead.",
                    $comment.Extent,
                    'AvoidMarketingLanguage',
                    'Warning',
                    $null
                )
            }
        }
    }
    
    # Check string literals for marketing language
    $strings = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
    foreach ($string in $strings) {
        $stringValue = $string.Value
        foreach ($word in $marketingWords) {
            if ($stringValue -match "\b$word\b") {
                $results += New-Object Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord (
                    "Avoid marketing language: '$word' in strings. Use direct, functional descriptions instead.",
                    $string.Extent,
                    'AvoidMarketingLanguage',
                    'Warning',
                    $null
                )
            }
        }
    }
    
    return $results
}

# Rule: Avoid "successfully" in status messages
function Measure-AvoidSuccessfullyAdverb {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $results = @()
    
    # Check string literals for "successfully"
    $strings = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true)
    foreach ($string in $strings) {
        if ($string.Value -match '\bsuccessfully\b') {
            $results += New-Object Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord (
                "Avoid 'successfully' in status messages. Use factual statements instead (e.g., 'Certificate installed' instead of 'Certificate installed successfully').",
                $string.Extent,
                'AvoidSuccessfullyAdverb',
                'Warning',
                $null
            )
        }
    }
    
    return $results
}

# Rule: Avoid overly verbose function names
function Measure-AvoidVerboseFunctionNames {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $verbosePatterns = @(
        'Advanced\w+',
        'Enhanced\w+',
        'Comprehensive\w+',
        'Intelligent\w+',
        'Sophisticated\w+',
        '\w+WithAdvanced\w+',
        '\w+WithEnhanced\w+',
        '\w+WithComprehensive\w+'
    )

    $results = @()
    
    # Check function names
    $functions = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($function in $functions) {
        $functionName = $function.Name
        foreach ($pattern in $verbosePatterns) {
            if ($functionName -match $pattern) {
                $results += New-Object Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord (
                    "Function name '$functionName' is overly verbose. Use clear, descriptive names without marketing adjectives.",
                    $function.Extent,
                    'AvoidVerboseFunctionNames',
                    'Warning',
                    $null
                )
            }
        }
    }
    
    return $results
}

# Rule: Ensure proper comment style (explain "why" not "what")
function Measure-CommentQuality {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $obviousPatterns = @(
        '# Set \$\w+ to',
        '# Assign \$\w+ to',
        '# Create \$\w+ variable',
        '# Initialize \$\w+',
        '# Return \$\w+',
        '# Get \$\w+ from'
    )

    $results = @()
    
    # Check comments for obvious statements
    $comments = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.Token] -and $args[0].Kind -eq 'Comment' }, $true)
    foreach ($comment in $comments) {
        $commentText = $comment.Text
        foreach ($pattern in $obviousPatterns) {
            if ($commentText -match $pattern) {
                $results += New-Object Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord (
                    "Comment explains 'what' instead of 'why'. Focus on explaining the reasoning or business logic.",
                    $comment.Extent,
                    'CommentQuality',
                    'Information',
                    $null
                )
            }
        }
    }
    
    return $results
}

# Rule: Check for proper variable naming (avoid overly verbose names)
function Measure-VariableNamingConvention {
    [CmdletBinding()]
    [OutputType([Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord[]])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.Language.ScriptBlockAst]
        $ScriptBlockAst
    )

    $results = @()
    
    # Check variable names for excessive verbosity (more than 50 characters)
    $variables = $ScriptBlockAst.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
    foreach ($variable in $variables) {
        $variableName = $variable.VariablePath.UserPath
        if ($variableName.Length -gt 50) {
            $results += New-Object Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord (
                "Variable name '$variableName' is overly verbose (${$variableName.Length} characters). Use descriptive but concise names.",
                $variable.Extent,
                'VariableNamingConvention',
                'Warning',
                $null
            )
        }
        
        # Check for marketing language in variable names
        $marketingWords = @('Advanced', 'Enhanced', 'Comprehensive', 'Intelligent', 'Sophisticated')
        foreach ($word in $marketingWords) {
            if ($variableName -match "\b$word\b") {
                $results += New-Object Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord (
                    "Variable name '$variableName' contains marketing language '$word'. Use functional names instead.",
                    $variable.Extent,
                    'VariableNamingConvention',
                    'Warning',
                    $null
                )
            }
        }
    }
    
    return $results
}

# Export the rule functions
Export-ModuleMember -Function Measure-AvoidMarketingLanguage, Measure-AvoidSuccessfullyAdverb, Measure-AvoidVerboseFunctionNames, Measure-CommentQuality, Measure-VariableNamingConvention
