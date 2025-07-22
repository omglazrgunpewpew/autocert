#!/usr/bin/env pwsh
<#
    .SYNOPSIS
        Build validation script for AutoCert PowerShell project

    .DESCRIPTION
        Runs PSScriptAnalyzer, Pester tests, and other quality checks to validate the codebase

    .PARAMETER Fix
        Attempt to automatically fix formatting issues where possible

    .PARAMETER SkipTests
        Skip running Pester tests (for faster linting-only runs)

    .PARAMETER UseParallel
        Enable parallel processing for PSScriptAnalyzer (PowerShell 7+ only, experimental)
        Note: May fail on some systems due to module loading issues in parallel runspaces

    .PARAMETER Detailed
        Show detailed output for all checks
#>

[CmdletBinding()]
param(
    [switch]$Fix,
    [switch]$SkipTests,
    [switch]$Detailed,
    [switch]$UseParallel
)

$ErrorActionPreference = 'Stop'

# Colors for output
$Colors = @{
    Success = 'Green'
    Warning = 'Yellow'
    Error   = 'Red'
    Info    = 'Cyan'
    Header  = 'Magenta'
}

function Write-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet('Success', 'Warning', 'Error', 'Info', 'Header')]
        [string]$Type = 'Info'
    )

    $color = $Colors[$Type]
    Write-Host -Object $Message -ForegroundColor $color
}

function Test-BuildEnvironment {
    <#
    .SYNOPSIS
        Validates the build environment before running validation
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $issues = @()
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $issues += "PowerShell 5.0 or higher is required (current: $($PSVersionTable.PSVersion))"
    }
    
    # Check if we're in the right directory structure
    $expectedPaths = @(
        Split-Path (Split-Path $PSScriptRoot -Parent) -Parent  # Project root
    )
    
    $projectRoot = $expectedPaths[0]
    if (-not (Test-Path (Join-Path $projectRoot 'Main.ps1'))) {
        $issues += "Cannot find Main.ps1 in expected project root: $projectRoot"
    }
    
    # Check write permissions for fixing issues
    if ($Fix -and -not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::User)) {
        Write-StatusMessage "⚠️  Running with elevated privileges - be careful with -Fix parameter" -Type Warning
    }
    
    if ($issues.Count -gt 0) {
        Write-StatusMessage "❌ Build environment validation failed:" -Type Error
        foreach ($issue in $issues) {
            Write-StatusMessage "  - $issue" -Type Error
        }
        return $false
    }
    
    return $true
}

function Test-ModuleAvailability {
    param([string]$ModuleName)

    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-StatusMessage "Installing required module: $ModuleName" -Type Warning
        try {
            Install-Module $ModuleName -Force -Scope CurrentUser -AllowClobber
            return $true
        }
        catch {
            Write-StatusMessage "Failed to install $ModuleName`: $($_.Exception.Message)" -Type Error
            return $false
        }
    }
    return $true
}

# Main validation function
function Invoke-BuildValidation {
    Write-StatusMessage "🔍 AutoCert Build Validation Starting..." -Type Header
    Write-StatusMessage "Time: $(Get-Date)" -Type Info
    Write-StatusMessage "PowerShell Version: $($PSVersionTable.PSVersion)" -Type Info
    Write-StatusMessage "Location: $PSScriptRoot" -Type Info
    Write-Progress -Activity "Build Validation" -Status "Initializing..." -PercentComplete 0

    # Validate build environment first
    if (-not (Test-BuildEnvironment)) {
        Write-Progress -Activity "Build Validation" -Completed
        return $false
    }

    $validationResults = @{
        PSScriptAnalyzer = @{ Passed = $false; Issues = 0; Details = @() }
        Tests            = @{ Passed = $false; TestCount = 0; FailedCount = 0 }
        OverallSuccess   = $false
    }

    # Check required modules
    Write-StatusMessage "`n📦 Checking required modules..." -Type Header
    Write-Progress -Activity "Build Validation" -Status "Checking required modules..." -PercentComplete 10
    $requiredModules = @('PSScriptAnalyzer', 'Pester')

    foreach ($module in $requiredModules) {
        if (-not (Test-ModuleAvailability $module)) {
            Write-StatusMessage "❌ Build validation cannot continue without $module" -Type Error
            Write-Progress -Activity "Build Validation" -Completed
            return $false
        }
        Write-StatusMessage "✅ $module is available" -Type Success
    }

    # PSScriptAnalyzer validation
    Write-StatusMessage "`n🔍 Running PSScriptAnalyzer..." -Type Header
    Write-Progress -Activity "Build Validation" -Status "Preparing PSScriptAnalyzer..." -PercentComplete 20

    try {
        # Try multiple possible locations for PSScriptAnalyzer settings
        $settingsPaths = @(
            Join-Path $PSScriptRoot '..\tools\PSScriptAnalyzerSettings.psd1'
            Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'tools\PSScriptAnalyzerSettings.psd1'
        )
        
        $settingsPath = $null
        foreach ($path in $settingsPaths) {
            if (Test-Path $path) {
                $settingsPath = $path
                Write-StatusMessage "✅ Using PSScriptAnalyzer settings: $(Split-Path $settingsPath -Leaf)" -Type Info
                break
            }
        }
        
        if (-not $settingsPath) {
            Write-StatusMessage "⚠️  PSScriptAnalyzer settings file not found, using default rules" -Type Warning
        }
        
        # Get the project root path (two levels up from dev-tools\build)
        $rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        
        # Get all PowerShell files to analyze (exclude certain directories)
        $excludePaths = @('Modules\Posh-ACME', '.git', 'bin', 'obj', 'node_modules', '.vscode')
        $psFiles = Get-ChildItem -Path $rootPath -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -ErrorAction SilentlyContinue |
        Where-Object { 
            $exclude = $false
            $relativePath = $_.FullName.Substring($rootPath.Length).TrimStart('\', '/')
            foreach ($excludePath in $excludePaths) {
                if ($relativePath -like "*$excludePath*") {
                    $exclude = $true
                    break
                }
            }
            -not $exclude -and $_.Length -gt 0  # Skip empty files
        }
        
        Write-StatusMessage "Analyzing $($psFiles.Count) PowerShell files..." -Type Info
        
        # Initialize variables for both parallel and sequential paths
        $allIssues = @()
        $problemFiles = @()
        $parallelSuccess = $false
        
        # Check PowerShell version for parallel support
        $supportsParallel = $PSVersionTable.PSVersion.Major -ge 7
        $fileCount = $psFiles.Count
        
        # Only use parallel processing if explicitly requested and supported
        if ($UseParallel -and $supportsParallel -and $fileCount -gt 3) {
            Write-StatusMessage "⚡ Using parallel processing (PowerShell 7+) for faster analysis..." -Type Info
            Write-StatusMessage "ℹ️  PowerShell version: $($PSVersionTable.PSVersion)" -Type Info
            Write-StatusMessage "ℹ️  Files to process: $fileCount" -Type Info
            Write-Progress -Activity "PSScriptAnalyzer" -Status "Running parallel analysis..." -PercentComplete 0
            
            try {
                # Verify PSScriptAnalyzer is available
                $psaModule = Get-Module -ListAvailable -Name PSScriptAnalyzer | Select-Object -First 1
                if (-not $psaModule) {
                    throw "PSScriptAnalyzer module not found"
                }
                
                Write-Verbose "Using PSScriptAnalyzer module: $($psaModule.ModuleBase)"
                $moduleBase = $psaModule.ModuleBase
                $settingsFile = $settingsPath
                $fixIssues = $Fix
                
                # Convert to simple arrays to avoid pipeline complexity
                $filePathArray = @($psFiles | ForEach-Object { $_.FullName })
                $totalFiles = $filePathArray.Count
                
                Write-Verbose "Starting parallel analysis of $totalFiles files with throttle limit 2"
                
                # Use job-based parallel processing with simpler data structures
                $jobs = @()
                $batchSize = [Math]::Max(1, [Math]::Floor($totalFiles / 4)) # 4 batches max
                
                for ($i = 0; $i -lt $totalFiles; $i += $batchSize) {
                    $endIndex = [Math]::Min($i + $batchSize - 1, $totalFiles - 1)
                    $batchFiles = $filePathArray[$i..$endIndex]
                    
                    $job = Start-Job -ScriptBlock {
                        $results = @()
                        
                        try {
                            # Import PSScriptAnalyzer with explicit path
                            if ($Using:moduleBase -and (Test-Path $Using:moduleBase)) {
                                Import-Module "$Using:moduleBase\PSScriptAnalyzer.psd1" -Force -Global
                            }
                            else {
                                Import-Module PSScriptAnalyzer -Force -Global
                            }
                            
                            foreach ($filePath in $Using:batchFiles) {
                                try {
                                    $analyzerParams = @{
                                        Path        = $filePath
                                        ErrorAction = 'Stop'
                                    }
                                    
                                    if ($Using:settingsFile -and (Test-Path $Using:settingsFile)) {
                                        $analyzerParams.Settings = $Using:settingsFile
                                    }
                                    
                                    if ($Using:fixIssues) {
                                        $analyzerParams.Fix = $true
                                    }
                                    
                                    $issues = @(Invoke-ScriptAnalyzer @analyzerParams)
                                    
                                    $results += [PSCustomObject]@{
                                        FilePath = $filePath
                                        Issues   = $issues
                                        Success  = $true
                                        Error    = $null
                                    }
                                }
                                catch {
                                    $results += [PSCustomObject]@{
                                        FilePath = $filePath
                                        Issues   = @()
                                        Success  = $false
                                        Error    = $_.Exception.Message
                                    }
                                }
                            }
                        }
                        catch {
                            # If module import fails, return error for all files
                            foreach ($filePath in $filePaths) {
                                $results += [PSCustomObject]@{
                                    FilePath = $filePath
                                    Issues   = @()
                                    Success  = $false
                                    Error    = "Module import failed: $($_.Exception.Message)"
                                }
                            }
                        }
                        
                        return $results
                    }
                    
                    $jobs += $job
                    Write-Verbose "Started job $($job.Id) for batch $($i + 1) (files $($i + 1) to $($endIndex + 1))"
                }
                
                # Wait for all jobs with progress reporting and timeout
                $allResults = @()
                $completedJobs = 0
                $timeoutSeconds = 300  # 5 minutes timeout
                $startTime = Get-Date
                
                do {
                    Start-Sleep -Milliseconds 500
                    $finished = @($jobs | Where-Object { $_.State -eq 'Completed' -or $_.State -eq 'Failed' })
                    
                    if ($finished.Count -gt $completedJobs) {
                        $completedJobs = $finished.Count
                        $percentComplete = [Math]::Round(($completedJobs / $jobs.Count) * 90, 1)
                        Write-Progress -Activity "PSScriptAnalyzer" -Status "Parallel jobs completed: $completedJobs of $($jobs.Count)" -PercentComplete $percentComplete
                    }
                    
                    # Check for timeout
                    $elapsed = (Get-Date) - $startTime
                    if ($elapsed.TotalSeconds -gt $timeoutSeconds) {
                        Write-StatusMessage "⚠️  Parallel processing timeout after $timeoutSeconds seconds" -Type Warning
                        # Stop remaining jobs
                        $runningJobs = $jobs | Where-Object { $_.State -eq 'Running' }
                        foreach ($runningJob in $runningJobs) {
                            Stop-Job -Job $runningJob -ErrorAction SilentlyContinue
                        }
                        break
                    }
                    
                } while ($completedJobs -lt $jobs.Count)
                
                # Collect results with better error handling
                foreach ($job in $jobs) {
                    try {
                        if ($job.State -eq 'Completed') {
                            $jobResults = Receive-Job -Job $job -ErrorAction Stop
                            if ($jobResults) {
                                $allResults += $jobResults
                            }
                        }
                        elseif ($job.State -eq 'Failed') {
                            Write-StatusMessage "⚠️  Job $($job.Id) failed" -Type Warning
                            # Try to get any partial results
                            try {
                                $jobResults = Receive-Job -Job $job -ErrorAction SilentlyContinue
                                if ($jobResults) {
                                    $allResults += $jobResults
                                }
                            }
                            catch {
                                Write-Verbose "Failed to retrieve results from failed job: $($_.Exception.Message)"
                            }
                        }
                        else {
                            Write-StatusMessage "⚠️  Job $($job.Id) was stopped due to timeout" -Type Warning
                        }
                    }
                    catch {
                        Write-StatusMessage "⚠️  Failed to receive job results: $($_.Exception.Message)" -Type Warning
                    }
                    finally {
                        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                    }
                }
                
                # Process aggregated results
                $allIssues = @()
                $problemFiles = @()
                
                foreach ($result in $allResults) {
                    if ($result.Success) {
                        if ($result.Issues) {
                            $allIssues += $result.Issues
                        }
                    }
                    else {
                        $fileName = Split-Path $result.FilePath -Leaf
                        $problemFiles += @{
                            File  = $fileName
                            Error = $result.Error
                        }
                    }
                }
                
                $parallelSuccess = $true
                Write-StatusMessage "✅ Parallel processing completed successfully (job-based)" -Type Success
                Write-Progress -Activity "PSScriptAnalyzer" -Completed
            }
            catch {
                Write-StatusMessage "⚠️  Parallel processing failed: $($_.Exception.Message)" -Type Warning
                Write-StatusMessage "🔄 Falling back to sequential processing..." -Type Info
                $parallelSuccess = $false
                # Reset variables for sequential processing
                $allIssues = @()
                $problemFiles = @()
            }
        }

        # Run sequential processing if parallel failed or wasn't attempted
        if (-not $parallelSuccess) {
            # Provide appropriate messaging
            if (-not $UseParallel) {
                Write-StatusMessage "ℹ️  Using sequential processing (default for reliability)..." -Type Info
            }
            elseif (-not $supportsParallel) {
                Write-StatusMessage "ℹ️  Using sequential processing (PowerShell 5.x)..." -Type Info
            }
            elseif ($fileCount -le 3) {
                Write-StatusMessage "ℹ️  Using sequential processing (small file count)..." -Type Info
            }

            # Reset variables if parallel failed
            $allIssues = @()
            $problemFiles = @()

            # Analyze files individually to avoid path conversion issues with in-place progress
            $currentFile = 0

            foreach ($file in $psFiles) {
                $currentFile++
                $percentComplete = [math]::Round(($currentFile / $fileCount) * 100, 1)
                $fileName = Split-Path $file.Name -Leaf

                # Show progress for each file (standard progress bar)
                Write-Progress -Activity "PSScriptAnalyzer" -Status "Analyzing file $currentFile of $fileCount" -CurrentOperation $fileName -PercentComplete $percentComplete

                # Only show file details in detailed mode to avoid output clutter
                if ($Detailed) {
                    Write-StatusMessage "  [$currentFile/$fileCount] $fileName" -Type Info
                }
                # In non-detailed mode, rely solely on the progress bar for file tracking

                try {
                    $analyzerParams = @{
                        Path = $file.FullName
                    }

                    # Add settings only if file exists
                    if ($settingsPath) {
                        $analyzerParams.Settings = $settingsPath
                    }

                    if ($Fix) {
                        $analyzerParams.Fix = $true
                    }

                    $fileIssues = Invoke-ScriptAnalyzer @analyzerParams
                    if ($fileIssues) {
                        $allIssues += $fileIssues
                    }
                }
                catch {
                    # Track files that had analysis problems with more detail
                    $errorMessage = $_.Exception.Message
                    if ($_.Exception.InnerException) {
                        $errorMessage += " (Inner: $($_.Exception.InnerException.Message))"
                    }
                    
                    $problemFiles += @{
                        File  = $file.Name
                        Error = $errorMessage
                        Path  = $file.FullName
                    }
                    
                    Write-Verbose "Analysis failed for $($file.Name): $errorMessage"
                }
            }

            # Clear the progress bar
            Write-Progress -Activity "PSScriptAnalyzer" -Completed
        }

        # Summary of analysis
        Write-StatusMessage "✅ Completed analysis of $fileCount files" -Type Success

        # Report any files that had analysis problems
        if ($problemFiles.Count -gt 0) {
            Write-StatusMessage "⚠️  $($problemFiles.Count) files had analysis issues:" -Type Warning
            foreach ($problem in $problemFiles) {
                if ($Detailed -and $problem.Path) {
                    Write-StatusMessage "  - $($problem.File) ($($problem.Path)): $($problem.Error)" -Type Warning
                }
                else {
                    Write-StatusMessage "  - $($problem.File): $($problem.Error)" -Type Warning
                }
            }
        }

        $issues = $allIssues
        $validationResults.PSScriptAnalyzer.Issues = $issues.Count
        $validationResults.PSScriptAnalyzer.Details = $issues

        if ($issues.Count -eq 0) {
            Write-StatusMessage "✅ No PSScriptAnalyzer issues found!" -Type Success
            $validationResults.PSScriptAnalyzer.Passed = $true
        }
        else {
            Write-StatusMessage "⚠️  Found $($issues.Count) PSScriptAnalyzer issues" -Type Warning

            # Group issues by severity
            $critical = $issues | Where-Object Severity -eq 'Error'
            $warnings = $issues | Where-Object Severity -eq 'Warning'
            $info = $issues | Where-Object Severity -eq 'Information'

            if ($critical.Count -gt 0) {
                Write-StatusMessage "❌ Critical errors: $($critical.Count)" -Type Error
                # Always show critical errors with file locations for easier debugging
                $critical | ForEach-Object {
                    Write-StatusMessage "  - $($_.RuleName) in $($_.ScriptName):$($_.Line)" -Type Error
                    if ($Detailed -and $_.Message) {
                        Write-StatusMessage "    Message: $($_.Message)" -Type Error
                    }
                }
            }

            if ($warnings.Count -gt 0) {
                Write-StatusMessage "⚠️  Warnings: $($warnings.Count)" -Type Warning
            }

            if ($info.Count -gt 0) {
                Write-StatusMessage "ℹ️  Info: $($info.Count)" -Type Info
            }

            # Fail build only on critical errors
            $validationResults.PSScriptAnalyzer.Passed = ($critical.Count -eq 0)
        }
    }
    catch {
        Write-StatusMessage "❌ PSScriptAnalyzer failed: $($_.Exception.Message)" -Type Error
        $validationResults.PSScriptAnalyzer.Passed = $false
    }

    # Pester tests
    if (-not $SkipTests) {
        Write-StatusMessage "`n🧪 Running Pester tests..." -Type Header
        Write-Progress -Activity "Build Validation" -Status "Running Pester tests..." -PercentComplete 60

        # Set testing environment variables to prevent module updates
        $env:AUTOCERT_TESTING_MODE = $true
        $env:POSHACME_SKIP_UPGRADE_CHECK = $true

        try {
            # Look for tests in multiple possible locations
            $testPaths = @(
                Join-Path (Split-Path $PSScriptRoot -Parent) 'Tests'
                Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Tests'
                Join-Path $PSScriptRoot '..\..\Tests'
            )
            
            $testPath = $null
            foreach ($path in $testPaths) {
                if (Test-Path $path) {
                    $testPath = $path
                    break
                }
            }
            
            if ($testPath) {
                Write-StatusMessage "✅ Found tests at: $testPath" -Type Info
                Write-StatusMessage "Using repository's Posh-ACME module (testing mode)" -Type Info
                
                # Check Pester version and use appropriate configuration
                $pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

                if ($pesterModule.Version -ge [version]'5.0.0') {
                    # Pester v5+ configuration
                    $pesterConfig = New-PesterConfiguration
                    $pesterConfig.Run.Path = $testPath
                    $pesterConfig.Output.Verbosity = if ($Detailed) { 'Detailed' } else { 'Normal' }
                    $pesterConfig.CodeCoverage.Enabled = $true
                    
                    # Get the project root path (two levels up from dev-tools\build)
                    $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
                    $pesterConfig.CodeCoverage.Path = @(
                        Join-Path $projectRoot 'Core\*.ps1'
                        Join-Path $projectRoot 'Public\*.ps1'
                        Join-Path $projectRoot 'Private\*.ps1'
                        Join-Path $projectRoot 'Main.ps1'
                    )

                    $testResults = Invoke-Pester -Configuration $pesterConfig
                }
                else {
                    # Pester v4 configuration
                    # Get the project root path (two levels up from dev-tools\build)
                    $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
                    $invokeParams = @{
                        Path         = $testPath
                        PassThru     = $true
                        CodeCoverage = @(
                            Join-Path $projectRoot 'Core\*.ps1'
                            Join-Path $projectRoot 'Public\*.ps1'
                            Join-Path $projectRoot 'Private\*.ps1'
                            Join-Path $projectRoot 'Main.ps1'
                        )
                    }

                    if ($Detailed) {
                        $invokeParams.Verbose = $true
                    }

                    $testResults = Invoke-Pester @invokeParams
                }

                $validationResults.Tests.TestCount = $testResults.TotalCount
                $validationResults.Tests.FailedCount = $testResults.FailedCount
                $validationResults.Tests.Passed = ($testResults.FailedCount -eq 0)

                if ($testResults.FailedCount -eq 0) {
                    Write-StatusMessage "✅ All $($testResults.TotalCount) tests passed!" -Type Success

                    if ($testResults.CodeCoverage) {
                        if ($pesterModule.Version -ge [version]'5.0.0') {
                            $coverage = [math]::Round($testResults.CodeCoverage.CoveragePercent, 2)
                        }
                        else {
                            $totalLines = ($testResults.CodeCoverage.NumberOfCommandsAnalyzed)
                            $missedLines = ($testResults.CodeCoverage.NumberOfCommandsMissed)
                            $coverage = if ($totalLines -gt 0) { [math]::Round((($totalLines - $missedLines) / $totalLines) * 100, 2) } else { 0 }
                        }
                        Write-StatusMessage "📊 Code coverage: $coverage%" -Type Info
                    }
                }
                else {
                    Write-StatusMessage "❌ $($testResults.FailedCount) of $($testResults.TotalCount) tests failed" -Type Error
                }
            }
            else {
                # Try to find any test files in the project
                $projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
                $testFiles = Get-ChildItem -Path $projectRoot -Recurse -Filter "*.Tests.ps1" -ErrorAction SilentlyContinue
                
                if ($testFiles.Count -gt 0) {
                    Write-StatusMessage "⚠️  Found $($testFiles.Count) test files but no standard test directory" -Type Warning
                    Write-StatusMessage "⚠️  Consider organizing tests in a 'Tests' directory" -Type Warning
                }
                else {
                    Write-StatusMessage "⚠️  No test directory or test files found" -Type Warning
                }
                
                $validationResults.Tests.Passed = $true  # Don't fail build if no tests exist yet
            }
        }
        catch {
            Write-StatusMessage "❌ Pester tests failed: $($_.Exception.Message)" -Type Error
            $validationResults.Tests.Passed = $false
        }
        finally {
            # Clean up testing environment variables
            Remove-Item env:AUTOCERT_TESTING_MODE -ErrorAction SilentlyContinue
            Remove-Item env:POSHACME_SKIP_UPGRADE_CHECK -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-StatusMessage "`n⏭️  Skipping tests as requested" -Type Info
        $validationResults.Tests.Passed = $true
    }

    # Overall validation result
    Write-Progress -Activity "Build Validation" -Status "Generating summary..." -PercentComplete 90
    $validationResults.OverallSuccess = $validationResults.PSScriptAnalyzer.Passed -and $validationResults.Tests.Passed

    Write-StatusMessage "`n📋 Validation Summary:" -Type Header
    Write-StatusMessage "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Type Header
    
    # PSScriptAnalyzer results
    $psaStatus = if ($validationResults.PSScriptAnalyzer.Passed) { '✅ PASS' } else { '❌ FAIL' }
    $psaColor = if ($validationResults.PSScriptAnalyzer.Passed) { 'Success' } else { 'Error' }
    Write-StatusMessage "PSScriptAnalyzer: $psaStatus ($($validationResults.PSScriptAnalyzer.Issues) issues found)" -Type $psaColor

    # Test results
    if (-not $SkipTests) {
        $testStatus = if ($validationResults.Tests.Passed) { '✅ PASS' } else { '❌ FAIL' }
        $testColor = if ($validationResults.Tests.Passed) { 'Success' } else { 'Error' }
        $testSummary = if ($validationResults.Tests.TestCount -gt 0) { 
            "($($validationResults.Tests.FailedCount)/$($validationResults.Tests.TestCount) failed)" 
        }
        else { 
            "(no tests found)" 
        }
        Write-StatusMessage "Tests: $testStatus $testSummary" -Type $testColor
    }
    else {
        Write-StatusMessage "Tests: ⏭️  SKIPPED (by request)" -Type Info
    }
    
    # Runtime statistics
    $runtime = (Get-Date) - $startTime
    Write-StatusMessage "Runtime: $([math]::Round($runtime.TotalSeconds, 1)) seconds" -Type Info
    
    Write-StatusMessage "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -Type Header

    if ($validationResults.OverallSuccess) {
        Write-Progress -Activity "Build Validation" -Status "Completed successfully" -PercentComplete 100
        Write-StatusMessage "`n🎉 Build validation PASSED!" -Type Success
        Write-Progress -Activity "Build Validation" -Completed
        return $true
    }
    else {
        Write-Progress -Activity "Build Validation" -Status "Completed with errors" -PercentComplete 100
        Write-StatusMessage "`n💥 Build validation FAILED!" -Type Error
        
        # Provide actionable feedback
        if (-not $validationResults.PSScriptAnalyzer.Passed) {
            Write-StatusMessage "💡 Run with -Fix parameter to auto-fix some PSScriptAnalyzer issues" -Type Info
            Write-StatusMessage "💡 Run with -Detailed parameter to see more issue details" -Type Info
        }
        
        Write-Progress -Activity "Build Validation" -Completed
        return $false
    }
}

# Run validation and handle exit codes
try {
    $startTime = Get-Date
    $success = Invoke-BuildValidation
    
    if ($success) {
        exit 0
    }
    else {
        exit 1
    }
}
catch {
    Write-StatusMessage "❌ Fatal error during build validation: $($_.Exception.Message)" -Type Error
    Write-Progress -Activity "Build Validation" -Completed
    exit 2
}

