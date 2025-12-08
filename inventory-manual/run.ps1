# Azure Function to manually trigger VM inventory collection via HTTP
param($Request, $TriggerMetadata)

# Import shared inventory module
$commonPath = Join-Path $PSScriptRoot "..\src\scripts\common"
Import-Module (Join-Path $commonPath "InventoryCore.psm1") -Force

# Get configuration from environment variables
$sqlServerName = $env:SQL_SERVER_NAME
$sqlDatabaseName = $env:SQL_DATABASE_NAME

try {
    # Validate configuration
    Test-InventoryConfiguration -SqlServerName $sqlServerName -SqlDatabaseName $sqlDatabaseName
    
    # Execute inventory collection with manual function settings  
    $summary = Invoke-InventoryCollection -SqlServerName $sqlServerName `
                                        -SqlDatabaseName $sqlDatabaseName `
                                        -EnableCleanup $false `
                                        -EnableDebugLogging $true `
                                        -CleanupDays 30
    
    # Add trigger type to summary
    $summary.TriggerType = "Manual"
    
    # Return response
    Push-OutputBinding -Name Response -Value (New-InventoryHttpResponse -Summary $summary)
}
catch {
    $errorMessage = "Manual inventory collection failed: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    $errorSummary = @{
        Status = "Error"
        Error = $errorMessage
        Timestamp = (Get-Date).ToString('o')
        TriggerType = "Manual"
    }
    
    Push-OutputBinding -Name Response -Value (New-InventoryHttpResponse -Summary $errorSummary)
}