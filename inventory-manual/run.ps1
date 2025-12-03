# Azure Function to manually trigger VM inventory collection via HTTP
param($Request, $TriggerMetadata)

# Import common modules
$commonPath = Join-Path $PSScriptRoot "..\src\scripts\common"
Import-Module (Join-Path $commonPath "SqlDatabaseUtils.psm1") -Force
Import-Module (Join-Path $commonPath "ArcUtils.psm1") -Force

# Get configuration from environment variables
$sqlServerName = $env:SQL_SERVER_NAME
$sqlDatabaseName = $env:SQL_DATABASE_NAME

if (-not $sqlServerName -or -not $sqlDatabaseName) {
    Write-Error "SQL_SERVER_NAME or SQL_DATABASE_NAME environment variables not set"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Body = @{ error = "Configuration error: Missing SQL database settings" }
    })
    return
}

try {
    Write-Host "Starting manual VM inventory collection..."
    
    # Connect to Azure with managed identity
    if (-not (Connect-ToAzureWithManagedIdentity)) {
        throw "Failed to connect to Azure with managed identity"
    }
    
    # Get all Arc-enabled machines (Windows only for now)
    Write-Host "Discovering Arc-enabled Windows machines..."
    $arcMachines = Get-ArcEnabledMachines -WindowsOnly $true
    Write-Host "Found $($arcMachines.Count) Arc-enabled Windows machines"
    
    # Get installed software from Defender for Servers
    Write-Host "Querying software inventory from Defender for Servers..."
    $softwareInventory = Get-InstalledSoftwareFromDefender
    Write-Host "Found $($softwareInventory.Count) software inventory entries"
    
    # Process and store inventory data
    $processedCount = 0
    $currentDate = Get-Date
    
    foreach ($software in $softwareInventory) {
        try {
            # Find matching Arc machine
            $arcMachine = $arcMachines | Where-Object { $_.machineName -eq $software.Computer }
            
            if ($arcMachine) {
                # Store inventory entry in SQL Database
                Add-VmInventoryEntry -ServerName $sqlServerName `
                                   -DatabaseName $sqlDatabaseName `
                                   -VmName $software.Computer `
                                   -SoftwareName $software.SoftwareName `
                                   -SoftwareVersion $software.SoftwareVersion `
                                   -Publisher $software.Publisher `
                                   -Date $currentDate
                
                $processedCount++
                
                # Log progress every 100 entries
                if ($processedCount % 100 -eq 0) {
                    Write-Host "Processed $processedCount inventory entries..."
                }
            }
            else {
                Write-Warning "No Arc machine found for computer: $($software.Computer)"
            }
        }
        catch {
            Write-Warning "Failed to process inventory entry for $($software.Computer) - $($software.SoftwareName): $($_.Exception.Message)"
        }
    }
    
    Write-Host "Successfully processed $processedCount inventory entries"
    
    # TODO: Clean up old inventory entries (keep last 30 days) - need to verify stored procedure exists
    # Clear-OldInventoryEntries -ServerName $sqlServerName -DatabaseName $sqlDatabaseName -DaysToKeep 30
    
    # Log summary
    $summary = @{
        Status = "Success"
        ArcMachinesFound = $arcMachines.Count
        SoftwareEntriesFound = $softwareInventory.Count
        EntriesProcessed = $processedCount
        Timestamp = $currentDate.ToString('o')
        Message = "Manual inventory collection completed successfully"
    }
    
    Write-Host "Manual inventory collection completed: $($summary | ConvertTo-Json -Compress)"
    
    # Return success response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body = $summary
    })
}
catch {
    $errorMessage = "Manual inventory collection failed: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Body = @{ error = $errorMessage; timestamp = (Get-Date).ToString('o') }
    })
}