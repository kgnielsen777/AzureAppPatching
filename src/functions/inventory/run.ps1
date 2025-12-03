# Azure Function to collect VM inventory via Resource Graph and store in Table Storage
param($Timer)

# Import common modules
$commonPath = Join-Path $PSScriptRoot "..\..\scripts\common"
Import-Module (Join-Path $commonPath "TableStorageUtils.psm1") -Force
Import-Module (Join-Path $commonPath "ArcUtils.psm1") -Force

# Get configuration from environment variables
$storageAccountName = $env:STORAGE_ACCOUNT_NAME

if (-not $storageAccountName) {
    Write-Error "STORAGE_ACCOUNT_NAME environment variable not set"
    exit 1
}

try {
    Write-Host "Starting VM inventory collection..."
    
    # Connect to Azure with managed identity
    if (-not (Connect-ToAzureWithManagedIdentity)) {
        throw "Failed to connect to Azure with managed identity"
    }
    
    # Get all Arc-enabled machines
    Write-Host "Discovering Arc-enabled machines..."
    $arcMachines = Get-ArcEnabledMachines
    Write-Host "Found $($arcMachines.Count) Arc-enabled machines"
    
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
                # Store inventory entry in Table Storage
                Add-VmInventoryEntry -StorageAccountName $storageAccountName `
                                   -VmName $software.Computer `
                                   -SoftwareName $software.SoftwareName `
                                   -SoftwareVersion $software.SoftwareVersion `
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
    
    # Clean up old inventory entries (keep last 7 days)
    Write-Host "Cleaning up old inventory entries..."
    Clear-OldInventoryEntries -StorageAccountName $storageAccountName -DaysToKeep 7
    
    # Log summary
    $summary = @{
        ArcMachinesFound = $arcMachines.Count
        SoftwareEntriesFound = $softwareInventory.Count
        EntriesProcessed = $processedCount
        Timestamp = $currentDate.ToString('o')
    }
    
    Write-Host "Inventory collection completed successfully: $($summary | ConvertTo-Json -Compress)"
    
    # Return success response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        Body = $summary
    })
}
catch {
    $errorMessage = "Inventory collection failed: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    # Return error response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        Body = @{ error = $errorMessage }
    })
}