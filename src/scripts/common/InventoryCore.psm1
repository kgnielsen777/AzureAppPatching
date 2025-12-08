# Core inventory collection functionality shared between scheduled and manual functions
param()

# Import required modules
Import-Module (Join-Path $PSScriptRoot "SqlDatabaseUtils.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "ArcUtils.psm1") -Force

function Invoke-InventoryCollection {
    <#
    .SYNOPSIS
    Core inventory collection logic shared between scheduled and manual functions
    
    .PARAMETER SqlServerName
    SQL Server name for storing inventory data
    
    .PARAMETER SqlDatabaseName
    SQL Database name for storing inventory data
    
    .PARAMETER EnableCleanup
    Whether to clean up old inventory entries (default: true for scheduled, false for manual)
    
    .PARAMETER EnableDebugLogging
    Whether to enable detailed debug logging (default: false for scheduled, true for manual)
    
    .PARAMETER CleanupDays
    Number of days to keep inventory entries (default: 30)
    
    .OUTPUTS
    Returns a hashtable with collection results and statistics
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$SqlDatabaseName,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableCleanup = $true,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableDebugLogging = $false,
        
        [Parameter(Mandatory = $false)]
        [int]$CleanupDays = 30
    )
    
    try {
        Write-Host "Starting VM inventory collection..."
        
        # Connect to Azure with managed identity
        if (-not (Connect-ToAzureWithManagedIdentity)) {
            throw "Failed to connect to Azure with managed identity"
        }
        
        # Get all Arc-enabled machines (Windows only for now)
        Write-Host "Discovering Arc-enabled Windows machines..."
        $arcMachines = Get-ArcEnabledMachines -WindowsOnly $true
        Write-Host "Found $($arcMachines.Count) Arc-enabled Windows machines"
        # TODO: Add Linux Arc machine support for inventory collection
        
        # Get installed software from Defender for Servers
        Write-Host "Querying software inventory from Defender for Servers..."
        $softwareInventory = Get-InstalledSoftwareFromDefender
        Write-Host "Found $($softwareInventory.Count) software inventory entries"
        
        # Debug logging if enabled
        if ($EnableDebugLogging) {
            Write-Host "Arc machines found: $($arcMachines | ForEach-Object { $_.machineName } | Sort-Object)"
            $uniqueComputers = $softwareInventory | Select-Object -ExpandProperty Computer -Unique | Sort-Object
            Write-Host "Software inventory computers: $($uniqueComputers -join ', ')"
        }
        
        # Process and store inventory data
        $processedCount = 0
        $skippedCount = 0
        $currentDate = Get-Date
        
        foreach ($software in $softwareInventory) {
            try {
                # Find matching Arc machine with case-insensitive comparison
                # This ensures consistency between scheduled and manual functions
                $arcMachine = $arcMachines | Where-Object { $_.machineName -ieq $software.Computer }
                
                if ($arcMachine) {
                    # Ensure vulnerability count is not null
                    $vulnCount = if ($software.numberOfKnownVulnerabilities -eq $null -or $software.numberOfKnownVulnerabilities -eq '') { 0 } else { [int]$software.numberOfKnownVulnerabilities }
                    
                    # Store inventory entry in SQL Database
                    Add-VmInventoryEntry -ServerName $SqlServerName `
                                       -DatabaseName $SqlDatabaseName `
                                       -VmName $software.Computer `
                                       -SoftwareName $software.SoftwareName `
                                       -SoftwareVersion $software.SoftwareVersion `
                                       -Publisher $software.Publisher `
                                       -numberOfKnownVulnerabilities $vulnCount `
                                       -Date $currentDate
                    
                    $processedCount++
                    
                    # Log progress every 100 entries
                    if ($processedCount % 100 -eq 0) {
                        Write-Host "Processed $processedCount inventory entries..."
                    }
                }
                else {
                    $skippedCount++
                    if ($EnableDebugLogging) {
                        Write-Warning "No Arc machine found for computer: '$($software.Computer)' (Software: $($software.SoftwareName))"
                    } else {
                        Write-Warning "No Arc machine found for computer: $($software.Computer)"
                    }
                }
            }
            catch {
                Write-Warning "Failed to process inventory entry for $($software.Computer) - $($software.SoftwareName): $($_.Exception.Message)"
            }
        }
        
        Write-Host "Successfully processed $processedCount inventory entries"
        if ($skippedCount -gt 0) {
            Write-Host "Skipped $skippedCount entries (no matching Arc machine)"
        }
        
        # Clean up old inventory entries if enabled
        if ($EnableCleanup) {
            Write-Host "Cleaning up old inventory entries..."
            try {
                Clear-OldInventoryEntries -ServerName $SqlServerName -DatabaseName $SqlDatabaseName -DaysToKeep $CleanupDays
                Write-Host "Cleanup completed successfully"
            }
            catch {
                Write-Warning "Cleanup failed (non-critical): $($_.Exception.Message)"
            }
        }
        
        # Prepare summary results
        $summary = @{
            Status = "Success"
            ArcMachinesFound = $arcMachines.Count
            SoftwareEntriesFound = $softwareInventory.Count
            EntriesProcessed = $processedCount
            EntriesSkipped = $skippedCount
            CleanupPerformed = $EnableCleanup
            Timestamp = $currentDate.ToString('o')
            Message = "Inventory collection completed successfully"
        }
        
        Write-Host "Inventory collection completed: $($summary | ConvertTo-Json -Compress)"
        return $summary
    }
    catch {
        $errorMessage = "Inventory collection failed: $($_.Exception.Message)"
        Write-Error $errorMessage
        
        # Return error summary
        return @{
            Status = "Error"
            Error = $errorMessage
            Timestamp = (Get-Date).ToString('o')
        }
    }
}

function New-InventoryHttpResponse {
    <#
    .SYNOPSIS
    Creates standardized HTTP response for inventory operations
    
    .PARAMETER Summary
    The summary hashtable returned by Invoke-InventoryCollection
    
    .OUTPUTS
    Returns HttpResponseContext for Azure Functions
    #>
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Summary
    )
    
    if ($Summary.Status -eq "Success") {
        return [HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            Body = $Summary
        }
    }
    else {
        return [HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::InternalServerError
            Body = $Summary
        }
    }
}

function Test-InventoryConfiguration {
    <#
    .SYNOPSIS
    Validates inventory configuration parameters
    
    .PARAMETER SqlServerName
    SQL Server name to validate
    
    .PARAMETER SqlDatabaseName  
    SQL Database name to validate
    
    .OUTPUTS
    Returns $true if configuration is valid, throws error otherwise
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$SqlDatabaseName
    )
    
    if (-not $SqlServerName -or -not $SqlDatabaseName) {
        throw "Configuration error: SQL_SERVER_NAME or SQL_DATABASE_NAME environment variables not set"
    }
    
    return $true
}

# Export functions
Export-ModuleMember -Function @(
    'Invoke-InventoryCollection',
    'New-InventoryHttpResponse', 
    'Test-InventoryConfiguration'
)