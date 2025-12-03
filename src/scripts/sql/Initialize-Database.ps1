# PowerShell script to initialize Azure SQL Database with schema and sample data
param(
    [Parameter(Mandatory = $true)]
    [string]$ServerName,
    
    [Parameter(Mandatory = $true)]
    [string]$DatabaseName,
    
    [Parameter(Mandatory = $false)]
    [string]$SchemaFilePath = "src\scripts\sql\schema.sql"
)

Write-Host "Initializing Azure SQL Database: $ServerName/$DatabaseName"

try {
    # Import required modules
    Import-Module SqlServer -Force
    Import-Module Az.Accounts -Force
    
    # Connect to Azure with managed identity (or current user context for local dev)
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Connecting to Azure..."
        Connect-AzAccount
    }
    
    # Use Invoke-Sqlcmd which handles Azure AD authentication automatically
    Write-Host "Connecting to SQL Database using Invoke-Sqlcmd..."
    
    # Test connection
    $testQuery = "SELECT 1 as TestConnection"
    $testResult = Invoke-Sqlcmd -ServerInstance "$ServerName.database.windows.net" -Database $DatabaseName -Query $testQuery -AccessToken (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
    if ($testResult.TestConnection -eq 1) {
        Write-Host "Successfully connected to SQL Database"
    }
    else {
        throw "Failed to connect to SQL Database"
    }
    
    # Check if schema file exists
    if (-not (Test-Path $SchemaFilePath)) {
        throw "Schema file not found: $SchemaFilePath"
    }
    
    Write-Host "Reading schema file: $SchemaFilePath"
    $schemaContent = Get-Content -Path $SchemaFilePath -Raw
    
    # Execute the schema script using Invoke-Sqlcmd
    Write-Host "Creating database schema and initial data..."
    
    $accessToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
    
    try {
        Invoke-Sqlcmd -ServerInstance "$ServerName.database.windows.net" -Database $DatabaseName -InputFile $SchemaFilePath -AccessToken $accessToken -QueryTimeout 120
        Write-Host "Schema script executed successfully"
    }
    catch {
        Write-Warning "Failed to execute schema script: $($_.Exception.Message)"
        # Try executing in smaller chunks
        Write-Host "Attempting to execute schema in smaller parts..."
        
        # Split the script into individual statements (separated by GO)
        $statements = $schemaContent -split '\r?\nGO\r?\n' | Where-Object { $_.Trim() -ne '' }
        
        foreach ($statement in $statements) {
            if ($statement.Trim() -ne '') {
                try {
                    Invoke-Sqlcmd -ServerInstance "$ServerName.database.windows.net" -Database $DatabaseName -Query $statement.Trim() -AccessToken $accessToken -QueryTimeout 60
                    Write-Host "Executed statement successfully"
                }
                catch {
                    Write-Warning "Failed to execute statement: $($_.Exception.Message)"
                    Write-Warning "Statement: $($statement.Substring(0, [Math]::Min(100, $statement.Length)))..."
                }
            }
        }
    }
    
    # Verify tables were created
    Write-Host "Verifying database schema..."
    
    $verificationQuery = @"
    SELECT TABLE_NAME, TABLE_TYPE 
    FROM INFORMATION_SCHEMA.TABLES 
    WHERE TABLE_TYPE = 'BASE TABLE'
    ORDER BY TABLE_NAME
"@
    
    $tables = Invoke-Sqlcmd -ServerInstance "$ServerName.database.windows.net" -Database $DatabaseName -Query $verificationQuery -AccessToken $accessToken
    
    Write-Host "Tables created:"
    foreach ($table in $tables) {
        Write-Host "  - $($table.TABLE_NAME)"
    }
    
    # Verify stored procedures were created
    $procedureQuery = @"
    SELECT ROUTINE_NAME 
    FROM INFORMATION_SCHEMA.ROUTINES 
    WHERE ROUTINE_TYPE = 'PROCEDURE'
    ORDER BY ROUTINE_NAME
"@
    
    $procedures = Invoke-Sqlcmd -ServerInstance "$ServerName.database.windows.net" -Database $DatabaseName -Query $procedureQuery -AccessToken $accessToken
    
    Write-Host "Stored procedures created:"
    foreach ($procedure in $procedures) {
        Write-Host "  - $($procedure.ROUTINE_NAME)"
    }
    
    # Verify initial data
    $dataQuery = "SELECT COUNT(*) as Count FROM ApplicationRepo"
    $countResult = Invoke-Sqlcmd -ServerInstance "$ServerName.database.windows.net" -Database $DatabaseName -Query $dataQuery -AccessToken $accessToken
    $count = $countResult.Count
    
    Write-Host "Initial application repository entries: $count"
    
    Write-Host "Database initialization completed successfully!"
    
    return @{
        Status = "Success"
        TablesCreated = $tables.Count
        ProceduresCreated = $procedures.Count
        InitialDataEntries = $count
    }
}
catch {
    Write-Error "Database initialization failed: $($_.Exception.Message)"
    throw
}