# Azure Function for deploying patches via Azure Arc run-command
param($Request, $TriggerMetadata)

# Import common modules
$commonPath = Join-Path $PSScriptRoot "..\scripts\common"
Import-Module (Join-Path $commonPath "SqlDatabaseUtils.psm1") -Force
Import-Module (Join-Path $commonPath "ArcUtils.psm1") -Force

# Get configuration from environment variables
$sqlServerName = $env:SQL_SERVER_NAME
$sqlDatabaseName = $env:SQL_DATABASE_NAME

if (-not $sqlServerName -or -not $sqlDatabaseName) {
    Write-Error "SQL_SERVER_NAME or SQL_DATABASE_NAME environment variables not set"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Body = @{ error = "SQL_SERVER_NAME or SQL_DATABASE_NAME environment variables not set" }
    })
    return
}

try {
    # Parse request body
    $requestBody = $Request.Body | ConvertFrom-Json
    
    # Support both single VM and batch patching
    $patchJobs = @()
    
    if ($requestBody.patchJobs) {
        # Batch mode - array of patch jobs
        $patchJobs = $requestBody.patchJobs
        Write-Host "Batch patching mode: $($patchJobs.Count) patch jobs requested"
    }
    elseif ($requestBody.machineName -and $requestBody.softwareName -and $requestBody.version) {
        # Single mode - individual patch job
        $patchJobs = @(@{
            machineName = $requestBody.machineName
            softwareName = $requestBody.softwareName
            version = $requestBody.version
            resourceGroupName = $requestBody.resourceGroupName
        })
        Write-Host "Single patching mode: 1 patch job requested"
    }
    else {
        throw "Invalid request format. Use either single mode (machineName, softwareName, version) or batch mode (patchJobs array)"
    }
    
    $results = @()
    $maxConcurrency = if ($requestBody.maxConcurrency) { $requestBody.maxConcurrency } else { 5 }
    
    Write-Host "Starting patch deployment for $($patchJobs.Count) job(s)"
    
    # Connect to Azure with managed identity
    if (-not (Connect-ToAzureWithManagedIdentity)) {
        throw "Failed to connect to Azure with managed identity"
    }
    
    # Process patch jobs in batches to respect concurrency limits
    $processedJobs = 0
    
    for ($i = 0; $i -lt $patchJobs.Count; $i += $maxConcurrency) {
        $batch = $patchJobs[$i..([Math]::Min($i + $maxConcurrency - 1, $patchJobs.Count - 1))]
        Write-Host "Processing batch $([Math]::Floor($i / $maxConcurrency) + 1) with $($batch.Count) jobs"
        
        $batchResults = @()
        
        foreach ($job in $batch) {
            try {
                $result = Invoke-PatchJob -Job $job -SqlServerName $sqlServerName -SqlDatabaseName $sqlDatabaseName
                $batchResults += $result
            }
            catch {
                $errorResult = @{
                    MachineName = $job.machineName
                    SoftwareName = $job.softwareName
                    Version = $job.version
                    Status = "Failed"
                    Error = $_.Exception.Message
                    Timestamp = (Get-Date).ToString('o')
                }
                $batchResults += $errorResult
                Write-Warning "Failed to process job for $($job.machineName) - $($job.softwareName): $($_.Exception.Message)"
            }
        }
        
        $results += $batchResults
        $processedJobs += $batch.Count
        
        Write-Host "Completed batch. Progress: $processedJobs/$($patchJobs.Count)"
        
        # Small delay between batches to avoid overwhelming Arc endpoints
        if ($i + $maxConcurrency -lt $patchJobs.Count) {
            Start-Sleep -Seconds 2
        }
    }
    
    # Prepare summary response
    $summary = @{
        TotalJobs = $patchJobs.Count
        SuccessfulJobs = ($results | Where-Object { $_.Status -eq "Success" }).Count
        FailedJobs = ($results | Where-Object { $_.Status -eq "Failed" }).Count
        Results = $results
        Timestamp = (Get-Date).ToString('o')
        ProcessingMode = if ($patchJobs.Count -eq 1) { "Single" } else { "Batch" }
    }
    
    Write-Host "Patch deployment completed. Success: $($summary.SuccessfulJobs), Failed: $($summary.FailedJobs)"
    
    # Return response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body = $summary
    })
}
catch {
    $errorMessage = "Patch deployment failed: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    $errorResult = @{
        Status = "Failed"
        Error = $errorMessage
        Timestamp = (Get-Date).ToString('o')
        TotalJobs = if ($patchJobs) { $patchJobs.Count } else { 0 }
    }
    
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Body = $errorResult
    })
}

function Invoke-PatchJob {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Job,
        
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$SqlDatabaseName
    )
    
    $machineName = $Job.machineName
    $softwareName = $Job.softwareName
    $targetVersion = $Job.version
    $resourceGroupName = $Job.resourceGroupName
    
    Write-Host "Processing patch job for $softwareName $targetVersion on $machineName"
    
    # Create patch job entry
    $jobId = New-PatchJob -ServerName $SqlServerName -DatabaseName $SqlDatabaseName `
                         -VmName $machineName -SoftwareName $softwareName `
                         -TargetVersion $targetVersion
    
    Write-Host "Created patch job with ID: $jobId"
    
    try {
        # Get application repository entry
        Write-Host "Looking up application repository entry for $softwareName"
        $appRepoEntry = Get-ApplicationRepoEntry -ServerName $SqlServerName -DatabaseName $SqlDatabaseName -SoftwareName $softwareName
        
        if (-not $appRepoEntry -or $appRepoEntry.Rows.Count -eq 0) {
            throw "No application repository entry found for $softwareName"
        }
        
        $repoRow = $appRepoEntry.Rows[0]
        Write-Host "Found application entry: Vendor=$($repoRow.Vendor), InstallCmd=$($repoRow.InstallCmd), Version=$($repoRow.Version)"
    
    # Determine script path based on software name
    $scriptPath = switch ($softwareName.ToLower()) {
        "google chrome" { Join-Path $PSScriptRoot "..\..\scripts\chrome\Install-Chrome.ps1" }
        "mozilla firefox" { Join-Path $PSScriptRoot "..\..\scripts\firefox\Install-Firefox.ps1" }
        "java" { Join-Path $PSScriptRoot "..\..\scripts\java\Install-Java.ps1" }
        default { 
            Write-Warning "No specific script found for $softwareName, using generic installer"
            $null  # Will use generic script content below
        }
    }
    
    # Read script content
    if ($scriptPath -and (Test-Path $scriptPath)) {
        $scriptContent = Get-Content -Path $scriptPath -Raw
    }
    else {
        # Create generic installation script
        $scriptContent = @"
param(
    [Parameter(Mandatory=`$true)]
    [string]`$InstallCommand,
    
    [Parameter(Mandatory=`$true)]
    [string]`$Version,
    
    [Parameter(Mandatory=`$false)]
    [string]`$SoftwareName
)

try {
    Write-Host "Installing `$SoftwareName version `$Version..."
    Write-Host "Command: `$InstallCommand"
    
    `$result = Invoke-Expression `$InstallCommand
    
    if (`$LASTEXITCODE -eq 0) {
        Write-Host "Installation completed successfully"
        return @{ Status = "Success"; Message = "Installation completed" }
    }
    else {
        throw "Installation failed with exit code `$LASTEXITCODE"
    }
}
catch {
    Write-Error "Installation failed: `$(`$_.Exception.Message)"
    throw
}
"@
    }
    
        # Prepare parameters for the script
        $scriptParameters = @{
            InstallCommand = $repoRow.InstallCmd
            Version = $targetVersion
            SoftwareName = $softwareName
        }
    
    # If resource group not provided, try to determine from Arc machine
    if (-not $resourceGroupName) {
        Write-Host "Looking up resource group for Arc Windows machine $machineName"
        # TODO: Add Linux machine support for patching operations
        $arcMachines = Get-ArcEnabledMachines -WindowsOnly $true
        $targetMachine = $arcMachines | Where-Object { $_.machineName -eq $machineName }
        
        if ($targetMachine) {
            $resourceGroupName = $targetMachine.resourceGroup
            Write-Host "Found machine in resource group: $resourceGroupName"
        }
        else {
            throw "Could not find Arc machine $machineName or determine its resource group"
        }
    }
    
        # Update patch job status to Running
        Update-PatchJob -ServerName $SqlServerName -DatabaseName $SqlDatabaseName `
                       -JobId $jobId -Status "Running"
        
        # Execute the installation via Arc run-command
        Write-Host "Executing installation command on $machineName via Arc run-command..."
        
        $commandId = "patch-$($softwareName.Replace(' ', '').ToLower())-$(Get-Date -Format 'yyyyMMddHHmmss')"
        
        $runCommandResult = Invoke-ArcRunCommand -ResourceGroupName $resourceGroupName `
                                               -MachineName $machineName `
                                               -CommandId $commandId `
                                               -ScriptContent $scriptContent `
                                               -Parameters $scriptParameters `
                                               -TimeoutSeconds 600
        
        # Wait for completion
        Write-Host "Waiting for installation to complete..."
        $completionResult = Wait-ForArcRunCommand -ResourceGroupName $resourceGroupName `
                                                 -MachineName $machineName `
                                                 -OperationId $runCommandResult.name `
                                                 -TimeoutMinutes 15
        
        # Update patch job status to Success
        Update-PatchJob -ServerName $SqlServerName -DatabaseName $SqlDatabaseName `
                       -JobId $jobId -Status "Succeeded" `
                       -ExecutionLog $completionResult.properties.output
        
        # Return the deployment result
        return @{
            JobId = $jobId
            MachineName = $machineName
            SoftwareName = $softwareName
            Version = $targetVersion
            Status = "Success"
            CommandId = $commandId
            Timestamp = (Get-Date).ToString('o')
            Output = $completionResult.properties.output
            ResourceGroup = $resourceGroupName
        }
    }
    catch {
        # Update patch job status to Failed
        Update-PatchJob -ServerName $SqlServerName -DatabaseName $SqlDatabaseName `
                       -JobId $jobId -Status "Failed" `
                       -ErrorMessage $_.Exception.Message
        
        throw
    }
}