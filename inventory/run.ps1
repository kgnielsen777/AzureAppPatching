# Azure Function to collect VM inventory via Resource Graph and store in SQL Database (Scheduled)
param($Timer)

# Import shared inventory module
$commonPath = Join-Path $PSScriptRoot "..\src\scripts\common"
Import-Module (Join-Path $commonPath "InventoryCore.psm1") -Force

# Get configuration from environment variables
$sqlServerName = $env:SQL_SERVER_NAME
$sqlDatabaseName = $env:SQL_DATABASE_NAME

try {
    # Validate configuration
    Test-InventoryConfiguration -SqlServerName $sqlServerName -SqlDatabaseName $sqlDatabaseName
    
    # Execute inventory collection with scheduled function settings
    $summary = Invoke-InventoryCollection -SqlServerName $sqlServerName `
                                        -SqlDatabaseName $sqlDatabaseName `
                                        -EnableCleanup $true `
                                        -EnableDebugLogging $false `
                                        -CleanupDays 30
    
    # Return response
    Push-OutputBinding -Name Response -Value (New-InventoryHttpResponse -Summary $summary)
}
catch {
    $errorMessage = "Scheduled inventory collection failed: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    $errorSummary = @{
        Status = "Error"
        Error = $errorMessage
        Timestamp = (Get-Date).ToString('o')
        TriggerType = "Scheduled"
    }
    
    Push-OutputBinding -Name Response -Value (New-InventoryHttpResponse -Summary $errorSummary)
}