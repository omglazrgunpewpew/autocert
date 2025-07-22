    # PSScriptAnalyzer validation
    Write-StatusMessage "`n🔍 Running PSScriptAnalyzer..." -Type Header
    Write-Progress -Activity "Build Validation" -Status "Preparing PSScriptAnalyzer..." -PercentComplete 20

    try {
        $settingsPath = Join-Path $PSScriptRoot '..\tools\PSScriptAnalyzerSettings.psd1'
        
        # Check if settings file exists
        if (-not (Test-Path $settingsPath)) {
            Write-StatusMessage "⚠️  PSScriptAnalyzer settings file not found at $settingsPath" -Type Warning
            $settingsPath = $null
        }
        
        # Get the project root path (two levels up from dev-tools\build)
        $rootPath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
        
        # Get all PowerShell files to analyze (exclude certain directories)
        $excludePaths = @('Modules\Posh-ACME', '.git', 'bin', 'obj')
        $psFiles = Get-ChildItem -Path $rootPath -Recurse -Include '*.ps1', '*.psm1', '*.psd1' |
        Where-Object { 
            $exclude = $false
            foreach ($excludePath in $excludePaths) {
                if ($_.FullName -like "*$excludePath*") {
                    $exclude = $true
                    break
                }
            }
            -not $exclude
        }
        
        Write-StatusMessage "Analyzing $($psFiles.Count) PowerShell files..." -Type Info
        
        # Initialize variables for both parallel and sequential paths
        $allIssues = @()
        $problemFiles = @()
        $parallelSuccess = $false
        
        # Check PowerShell version for parallel support
        $supportsParallel = $PSVersionTable.PSVersion.Major -ge 7
        $fileCount = $psFiles.Count
        
        if ($supportsParallel -and $fileCount -gt 3) {
            Write-StatusMessage "⚡ Using parallel processing (PowerShell 7+) for faster analysis..." -Type Info
            Write-Progress -Activity "PSScriptAnalyzer" -Status "Running parallel analysis..." -PercentComplete 0
            
            try {
                # Use parallel processing for better performance
                $results = $psFiles | ForEach-Object -Parallel {
                    $file = $_
                    $settingsPath = $using:settingsPath
                    $Fix = $using:Fix
                    
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
                        return @{
                            Success = $true
                            Issues = $fileIssues
                            File = $file.Name
                        }
                    }
                    catch {
                        return @{
                            Success = $false
                            Error = $_.Exception.Message
                            File = $file.Name
                        }
                    }
                } -ThrottleLimit 4  # Limit concurrent threads to avoid overwhelming system
                
                Write-Progress -Activity "PSScriptAnalyzer" -Status "Processing results..." -PercentComplete 90
                
                # Process results
                foreach ($result in $results) {
                    if ($result.Success) {
                        if ($result.Issues) {
                            $allIssues += $result.Issues
                        }
                    } else {
                        $problemFiles += @{
                            File = $result.File
                            Error = $result.Error
                        }
                    }
                }
                
                Write-Progress -Activity "PSScriptAnalyzer" -Completed
                $parallelSuccess = $true
            }
            catch {
                Write-StatusMessage "⚠️  Parallel processing failed: $($_.Exception.Message)" -Type Warning
                Write-StatusMessage "🔄 Falling back to sequential processing..." -Type Info
                $parallelSuccess = $false
            }
        }
        
        # Run sequential processing if parallel failed or wasn't attempted
        if (-not $parallelSuccess) {
            # Provide appropriate messaging
            if (-not $supportsParallel) {
                Write-StatusMessage "ℹ️  Using sequential processing (PowerShell 5.x)..." -Type Info
            } elseif ($fileCount -le 3) {
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
                
                # Show in-place console update instead of new lines (unless in detailed mode)
                if ($Detailed) {
                    Write-StatusMessage "  [$currentFile/$fileCount] $fileName" -Type Info
                } else {
                    # Update same line with carriage return for clean output
                    $progressText = "Analyzing [$currentFile/$fileCount]: $fileName".PadRight(80)
                    Write-Host -Object "`r$progressText" -NoNewline -ForegroundColor Cyan
                }
                
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
                    # Track files that had analysis problems
                    $problemFiles += @{
                        File = $file.Name
                        Error = $_.Exception.Message
                    }
                }
            }
            
            # Clear the in-place progress line and progress bar
            if (-not $Detailed) {
                Write-Host -Object ("`r" + (" " * 80) + "`r") -NoNewline  # Clear the line
            }
            Write-Progress -Activity "PSScriptAnalyzer" -Completed
        }
        
        # Summary of analysis
        Write-StatusMessage "✅ Completed analysis of $fileCount files" -Type Success
        
        # Report any files that had analysis problems
        if ($problemFiles.Count -gt 0) {
            Write-StatusMessage "⚠️  $($problemFiles.Count) files had analysis issues:" -Type Warning
            foreach ($problem in $problemFiles) {
                Write-StatusMessage "  - $($problem.File): $($problem.Error)" -Type Warning
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
                Write-StatusMessage "❌ Critical: $($critical.Count)" -Type Error
                if ($Detailed) {
                    foreach ($issue in $critical) {
                        Write-StatusMessage "  - $($issue.ScriptName):$($issue.Line) $($issue.Message)" -Type Error
                    }
                }
            }

            if ($warnings.Count -gt 0) {
                Write-StatusMessage "⚠️  Warnings: $($warnings.Count)" -Type Warning
                if ($Detailed) {
                    foreach ($issue in $warnings) {
                        Write-StatusMessage "  - $($issue.ScriptName):$($issue.Line) $($issue.Message)" -Type Warning
                    }
                }
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
