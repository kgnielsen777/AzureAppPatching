# Azure Function for deploying patches via Azure Arc run-command
param($Request, $TriggerMetadata)

# Import common modules
$commonPath = Join-Path $PSScriptRoot "..\..\scripts\common"
Import-Module (Join-Path $commonPath "TableStorageUtils.psm1") -Force
Import-Module (Join-Path $commonPath "ArcUtils.psm1") -Force

# Get configuration from environment variables
$storageAccountName = $env:STORAGE_ACCOUNT_NAME

if (-not $storageAccountName) {
    Write-Error "STORAGE_ACCOUNT_NAME environment variable not set"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Body = @{ error = "STORAGE_ACCOUNT_NAME environment variable not set" }
    })
    return
}

try {
    # Parse request body
    $requestBody = $Request.Body | ConvertFrom-Json
    
    # Validate required parameters
    if (-not $requestBody.machineName -or -not $requestBody.softwareName -or -not $requestBody.version) {
        throw "Missing required parameters: machineName, softwareName, version"
    }
    
    $machineName = $requestBody.machineName
    $softwareName = $requestBody.softwareName
    $targetVersion = $requestBody.version
    $resourceGroupName = $requestBody.resourceGroupName
    
    Write-Host "Starting patch deployment for $softwareName $targetVersion on $machineName"
    
    # Connect to Azure with managed identity
    if (-not (Connect-ToAzureWithManagedIdentity)) {
        throw "Failed to connect to Azure with managed identity"
    }
    
    # Get application repository entry
    Write-Host "Looking up application repository entry for $softwareName $targetVersion"
    $appRepoEntry = Get-ApplicationRepoEntry -StorageAccountName $storageAccountName -SoftwareName $softwareName -Version $targetVersion
    
    if (-not $appRepoEntry) {
        throw "No application repository entry found for $softwareName version $targetVersion"
    }
    
    Write-Host "Found application entry: Vendor=$($appRepoEntry.Vendor), InstallCmd=$($appRepoEntry.InstallCmd)"
    
    # Determine script path based on software name
    $scriptPath = switch ($softwareName.ToLower()) {
        "google chrome" { Join-Path $PSScriptRoot "..\..\scripts\chrome\Install-Chrome.ps1" }
        "mozilla firefox" { Join-Path $PSScriptRoot "..\..\scripts\firefox\Install-Firefox.ps1" }
        "java" { Join-Path $PSScriptRoot "..\..\scripts\java\Install-Java.ps1" }
        default { 
            Write-Warning "No specific script found for $softwareName, using generic installer"
            Join-Path $PSScriptRoot "..\..\scripts\common\Install-Generic.ps1"
        }
    }
    
    # Read script content
    if (Test-Path $scriptPath) {
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
        InstallCommand = $appRepoEntry.InstallCmd
        Version = $targetVersion
        SoftwareName = $softwareName
    }
    
    # If resource group not provided, try to determine from Arc machine
    if (-not $resourceGroupName) {
        Write-Host "Looking up resource group for Arc machine $machineName"
        $arcMachines = Get-ArcEnabledMachines
        $targetMachine = $arcMachines | Where-Object { $_.machineName -eq $machineName }
        
        if ($targetMachine) {
            $resourceGroupName = $targetMachine.resourceGroup
            Write-Host "Found machine in resource group: $resourceGroupName"
        }
        else {
            throw "Could not find Arc machine $machineName or determine its resource group"
        }
    }
    
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
    
    # Log the deployment
    $deploymentResult = @{
        MachineName = $machineName
        SoftwareName = $softwareName
        Version = $targetVersion
        Status = "Success"
        CommandId = $commandId
        Timestamp = (Get-Date).ToString('o')
        Output = $completionResult.properties.output
    }
    
    Write-Host "Patch deployment completed successfully: $($deploymentResult | ConvertTo-Json -Compress)"
    
    # Return success response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body = $deploymentResult
    })
}
catch {
    $errorMessage = "Patch deployment failed: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    $errorResult = @{
        MachineName = $machineName
        SoftwareName = $softwareName
        Version = $targetVersion
        Status = "Failed"
        Error = $errorMessage
        Timestamp = (Get-Date).ToString('o')
    }
    
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Body = $errorResult
    })
}