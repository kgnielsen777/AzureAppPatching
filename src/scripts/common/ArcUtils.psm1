# Common utilities for Azure Arc integration
param()

# Import required modules
Import-Module Az.ResourceGraph -Force
Import-Module Az.Monitor -Force

function Invoke-ResourceGraphQuery {
    <#
    .SYNOPSIS
    Executes an Azure Resource Graph query with retry logic
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Subscriptions,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3,
        
        [Parameter(Mandatory = $false)]
        [int]$RetryDelaySeconds = 5
    )
    
    $retry = 0
    
    while ($retry -le $MaxRetries) {
        try {
            Write-Host "Executing Resource Graph query (attempt $($retry + 1))..."
            
            $searchParams = @{
                Query = $Query
            }
            
            if ($Subscriptions) {
                $searchParams.Subscription = $Subscriptions
            }
            
            $result = Search-AzGraph @searchParams -First 1000
            
            # Handle pagination
            $allResults = @()
            $allResults += $result.Data
            
            while ($result.SkipToken) {
                $searchParams.SkipToken = $result.SkipToken
                $result = Search-AzGraph @searchParams -First 1000
                $allResults += $result.Data
            }
            
            Write-Host "Resource Graph query returned $($allResults.Count) results"
            return $allResults
        }
        catch {
            $retry++
            if ($retry -gt $MaxRetries) {
                Write-Error "Resource Graph query failed after $MaxRetries retries: $($_.Exception.Message)"
                throw
            }
            
            Write-Warning "Resource Graph query failed (attempt $retry), retrying in $RetryDelaySeconds seconds..."
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Get-ArcEnabledMachines {
    <#
    .SYNOPSIS
    Gets all Azure Arc-enabled machines
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$Subscriptions
    )
    
    $query = @"
Resources
| where type == 'microsoft.hybridcompute/machines'
| extend machineName = name, machineId = id, osType = properties.osName, status = properties.status
| project machineName, machineId, osType, status, resourceGroup, location, subscriptionId
"@
    
    return Invoke-ResourceGraphQuery -Query $query -Subscriptions $Subscriptions
}

function Get-InstalledSoftwareFromMonitor {
    <#
    .SYNOPSIS
    Gets installed software inventory from Azure Monitor Log Analytics
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceId,
        
        [Parameter(Mandatory = $false)]
        [int]$HoursBack = 24
    )
    
    try {
        Write-Host "Querying Azure Monitor for software inventory..."
        
        $query = @"
InstalledSoftware
| where TimeGenerated > ago($($HoursBack)h)
| summarize by Computer, SoftwareName, SoftwareVersion, Publisher
| project Computer, SoftwareName, SoftwareVersion, Publisher
"@
        
        $results = Invoke-AzOperationalInsightsQuery -WorkspaceId $WorkspaceId -Query $query
        
        Write-Host "Found $($results.Results.Count) software inventory entries"
        return $results.Results
    }
    catch {
        Write-Error "Failed to query Azure Monitor for software inventory: $($_.Exception.Message)"
        throw
    }
}

function Invoke-ArcRunCommand {
    <#
    .SYNOPSIS
    Executes a run command on an Azure Arc-enabled machine
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$MachineName,
        
        [Parameter(Mandatory = $true)]
        [string]$CommandId,
        
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{},
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300
    )
    
    try {
        Write-Host "Executing run command '$CommandId' on Arc machine '$MachineName'..."
        
        # Create script file content with parameters
        $scriptWithParams = $ScriptContent
        foreach ($param in $Parameters.GetEnumerator()) {
            $scriptWithParams = $scriptWithParams.Replace("`$($($param.Key))", $param.Value)
        }
        
        # Execute the run command using REST API (since Az.ConnectedMachine may not be available)
        $subscriptionId = (Get-AzContext).Subscription.Id
        $resourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.HybridCompute/machines/$MachineName"
        
        $body = @{
            commandId = $CommandId
            script = @($scriptWithParams)
            timeoutInSeconds = $TimeoutSeconds
        } | ConvertTo-Json -Depth 3
        
        $uri = "https://management.azure.com$resourceId/runCommands?api-version=2023-10-03-preview"
        
        $response = Invoke-AzRestMethod -Uri $uri -Method POST -Payload $body
        
        if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 202) {
            $result = $response.Content | ConvertFrom-Json
            Write-Host "Run command executed successfully. Operation ID: $($result.name)"
            return $result
        }
        else {
            throw "Run command failed with status code: $($response.StatusCode). Response: $($response.Content)"
        }
    }
    catch {
        Write-Error "Failed to execute Arc run command: $($_.Exception.Message)"
        throw
    }
}

function Wait-ForArcRunCommand {
    <#
    .SYNOPSIS
    Waits for an Azure Arc run command to complete
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $true)]
        [string]$MachineName,
        
        [Parameter(Mandatory = $true)]
        [string]$OperationId,
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 10
    )
    
    try {
        $subscriptionId = (Get-AzContext).Subscription.Id
        $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.HybridCompute/machines/$MachineName/runCommands/$OperationId?api-version=2023-10-03-preview"
        
        $timeout = (Get-Date).AddMinutes($TimeoutMinutes)
        
        do {
            $response = Invoke-AzRestMethod -Uri $uri -Method GET
            
            if ($response.StatusCode -eq 200) {
                $result = $response.Content | ConvertFrom-Json
                
                if ($result.properties.provisioningState -eq 'Succeeded') {
                    Write-Host "Run command completed successfully"
                    return $result
                }
                elseif ($result.properties.provisioningState -eq 'Failed') {
                    Write-Error "Run command failed: $($result.properties.error.message)"
                    throw "Run command failed"
                }
                
                Write-Host "Run command status: $($result.properties.provisioningState). Waiting..."
                Start-Sleep -Seconds 10
            }
            else {
                throw "Failed to get run command status: $($response.StatusCode)"
            }
        } while ((Get-Date) -lt $timeout)
        
        throw "Run command timed out after $TimeoutMinutes minutes"
    }
    catch {
        Write-Error "Failed to wait for Arc run command: $($_.Exception.Message)"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Invoke-ResourceGraphQuery',
    'Get-ArcEnabledMachines',
    'Get-InstalledSoftwareFromMonitor',
    'Invoke-ArcRunCommand',
    'Wait-ForArcRunCommand'
)