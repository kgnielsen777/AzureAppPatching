# Azure App Patching - Deployment Guide

## Prerequisites

### Azure Resources
- Azure subscription with appropriate permissions
- Azure Arc-enabled Windows VMs with Defender for Servers enabled
- Resource group for deployment

### Local Development Environment
- PowerShell 7.4+ with Azure PowerShell and SqlServer modules
- Azure Functions Core Tools v4
- Git
- VS Code (recommended) with Azure Functions extension
- SQL Server Management Studio (optional, for database management)

### Required Permissions
- Contributor access to target resource group
- User Access Administrator (for RBAC assignments) 
- Azure Connected Machine Resource Administrator (for Arc operations)
- SQL DB Contributor (for SQL Database operations)

## Step 1: Clone Repository

```powershell
git clone https://github.com/kgnielsen777/AzureAppPatching.git
Set-Location AzureAppPatching
```

## Step 2: Configure Parameters

Edit `infra/bicep/main.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0", 
  "parameters": {
    "namePrefix": {
      "value": "mycompany-apppatching"
    },
    "environment": {
      "value": "prod"
    },
    "location": {
      "value": "Sweden Central"
    },
    "sqlAdminPassword": {
      "value": "YourSecurePassword123!"
    }
  }
}
```

**Important**: Change the `sqlAdminPassword` to a secure password meeting Azure SQL requirements (minimum 8 characters, containing characters from at least 3 of: uppercase, lowercase, numbers, symbols).

## Step 3: Deploy Infrastructure

```powershell
# Login to Azure
Connect-AzAccount

# Set subscription
Set-AzContext -SubscriptionId "your-subscription-id"

# Create resource group
New-AzResourceGroup -Name "rg-apppatching-prod" -Location "Sweden Central"

# Deploy Bicep template
New-AzResourceGroupDeployment `
  -ResourceGroupName "rg-apppatching-prod" `
  -TemplateFile "infra/bicep/main.bicep" `
  -TemplateParameterFile "infra/bicep/main.parameters.json"
```

The deployment creates:
- Azure Function App with system-assigned managed identity
- Azure SQL Server with Basic database for VM inventory and application repository
- Storage Account for function app artifacts
- Required RBAC role assignments for Resource Graph, Arc operations, and SQL Database access

## Step 4: Initialize Database Schema

```powershell
# Get deployment outputs
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
$sqlServerName = $deployment.Outputs.sqlServerName.Value
$sqlDatabaseName = $deployment.Outputs.sqlDatabaseName.Value

# Initialize database schema
.\src\scripts\sql\Initialize-Database.ps1 -ServerName $sqlServerName -DatabaseName $sqlDatabaseName

Write-Host "Database schema initialized successfully"
```

## Step 5: Configure Local Development

```powershell
# Get deployment outputs for local configuration
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
$sqlServerName = $deployment.Outputs.sqlServerName.Value
$sqlDatabaseName = $deployment.Outputs.sqlDatabaseName.Value
$storageAccountName = $deployment.Outputs.storageAccountName.Value

# Update local.settings.json with your values
$localSettings = @{
  IsEncrypted = $false
  Values = @{
    AzureWebJobsStorage = "DefaultEndpointsProtocol=https;AccountName=$storageAccountName;AccountKey=..."
    FUNCTIONS_WORKER_RUNTIME = "powershell"
    FUNCTIONS_WORKER_RUNTIME_VERSION = "7.4"
    SQL_SERVER_NAME = $sqlServerName
    SQL_DATABASE_NAME = $sqlDatabaseName
  }
}

$localSettings | ConvertTo-Json -Depth 3 | Out-File "local.settings.json" -Encoding UTF8

# Test functions locally
func start --powershell
```

## Step 6: Deploy Function App

```powershell
# Get Function App name from deployment output
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
$functionAppName = $deployment.Outputs.functionAppName.Value

# Deploy function code
func azure functionapp publish $functionAppName
```

## Step 7: Seed Application Repository

The initial application repository data is automatically created when initializing the database schema. You can add additional applications using PowerShell:

```powershell
# Import the SQL Database utilities
Import-Module ".\src\scripts\common\SqlDatabaseUtils.psm1" -Force

# Connect with your user account for initial setup
Connect-AzAccount

# Get deployment outputs
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
$sqlServerName = $deployment.Outputs.sqlServerName.Value
$sqlDatabaseName = $deployment.Outputs.sqlDatabaseName.Value

# Add additional Chrome version
Add-ApplicationRepoEntry -ServerName $sqlServerName -DatabaseName $sqlDatabaseName `
                       -SoftwareName "Google Chrome" `
                       -Version "121.0.6167.85" `
                       -InstallCmd "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe /silent /install" `
                       -Vendor "Google"

# Add Firefox ESR version  
Add-ApplicationRepoEntry -ServerName $sqlServerName -DatabaseName $sqlDatabaseName `
                       -SoftwareName "Mozilla Firefox" `
                       -Version "115.7.0esr" `
                       -InstallCmd "https://download.mozilla.org/?product=firefox-esr-latest&os=win64&lang=en-US /S" `
                       -Vendor "Mozilla"

Write-Host "Additional application repository entries added successfully"
```

## Step 8: Verify Deployment

### Check Function Status

```powershell
# List functions
Get-AzWebAppFunction -ResourceGroupName "rg-apppatching-prod" -Name $functionAppName | 
  Select-Object Name, @{Name='Status'; Expression={-not $_.Config.disabled}} | 
  Format-Table

# Check function logs (use Azure portal or Application Insights)
Write-Host "View logs at: https://portal.azure.com/#resource/subscriptions/$((Get-AzContext).Subscription.Id)/resourceGroups/rg-apppatching-prod/providers/Microsoft.Web/sites/$functionAppName/logs"
```

### Test Inventory Function

The inventory function runs automatically every 6 hours. To trigger manually:

```powershell
# Get the function app details
$functionApp = Get-AzWebApp -ResourceGroupName "rg-apppatching-prod" -Name $functionAppName
$masterKey = (Invoke-AzResourceAction -ResourceId "$($functionApp.Id)/host/default/listKeys" -Action "POST" -Force).masterKey

# Trigger inventory function
$uri = "https://$($functionApp.DefaultHostName)/admin/functions/inventory"
$headers = @{
  'Content-Type' = 'application/json'
  'x-functions-key' = $masterKey
}
Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body '{}'
```

### Test Patching Function

```powershell
# Get function URL
$patchFunction = Get-AzWebAppFunction -ResourceGroupName "rg-apppatching-prod" -Name $functionAppName -FunctionName "patching"
$patchUrl = $patchFunction.InvokeUrlTemplate

# Test patch deployment (replace with actual VM details)
$body = @{
  machineName = "your-vm-name"
  softwareName = "Google Chrome"
  version = "120.0.6099.109"
  resourceGroupName = "your-vm-resource-group"
} | ConvertTo-Json

Invoke-RestMethod -Uri $patchUrl -Method POST -ContentType "application/json" -Body $body
```

## Step 9: Monitor Operations

### Application Insights

```powershell
# Get Application Insights resource (if created)
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
if ($deployment.Outputs.applicationInsightsName) {
  $aiName = $deployment.Outputs.applicationInsightsName.Value
  $subscriptionId = (Get-AzContext).Subscription.Id
  Write-Host "Application Insights: https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/rg-apppatching-prod/providers/Microsoft.Insights/components/$aiName"
} else {
  Write-Host "Application Insights not configured in current deployment"
}
```

### SQL Database Data

```powershell
# Check inventory data
Import-Module ".\src\scripts\common\SqlDatabaseUtils.psm1" -Force
Connect-AzAccount

$deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
$sqlServerName = $deployment.Outputs.sqlServerName.Value
$sqlDatabaseName = $deployment.Outputs.sqlDatabaseName.Value

# Connect to SQL Database
$connection = Get-SqlConnection -ServerName $sqlServerName -DatabaseName $sqlDatabaseName

# Get recent inventory entries
$query = @"
SELECT TOP 100 VmName, SoftwareName, SoftwareVersion, Publisher, Date, CreatedAt
FROM VmInventory 
WHERE Date > DATEADD(HOUR, -6, GETUTCDATE())
ORDER BY Date DESC
"@

$recentEntries = Invoke-SqlCommand -Connection $connection -Query $query
$connection.Close()

$recentEntries | Format-Table VmName, SoftwareName, SoftwareVersion, Date

# Check application repository
$connection = Get-SqlConnection -ServerName $sqlServerName -DatabaseName $sqlDatabaseName
$appRepoQuery = "SELECT SoftwareName, Version, Vendor, OSPlatform FROM ApplicationRepo WHERE IsActive = 1"
$appEntries = Invoke-SqlCommand -Connection $connection -Query $appRepoQuery
$connection.Close()

$appEntries | Format-Table
```

## Troubleshooting

### Common Issues

**Function App Identity Issues**
```powershell
# Verify managed identity is assigned
$functionApp = Get-AzWebApp -ResourceGroupName "rg-apppatching-prod" -Name $functionAppName
Write-Host "Managed Identity Principal ID: $($functionApp.Identity.PrincipalId)"
Write-Host "Identity Type: $($functionApp.Identity.Type)"

# Check RBAC assignments
Get-AzRoleAssignment -ObjectId $functionApp.Identity.PrincipalId | 
  Select-Object DisplayName, RoleDefinitionName, Scope | 
  Format-Table
```

**SQL Database Access Issues**
```powershell
# Test SQL Database connectivity
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
$sqlServerName = $deployment.Outputs.sqlServerName.Value
$sqlDatabaseName = $deployment.Outputs.sqlDatabaseName.Value

try {
    $connection = Get-SqlConnection -ServerName $sqlServerName -DatabaseName $sqlDatabaseName
    Write-Host "SQL Database Status: Connected"
    
    # Check tables exist
    $tablesQuery = "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'"
    $tables = Invoke-SqlCommand -Connection $connection -Query $tablesQuery
    Write-Host "Tables found: $($tables.Rows.Count)"
    $tables | Format-Table TABLE_NAME
    
    $connection.Close()
}
catch {
    Write-Error "Failed to connect to SQL Database: $($_.Exception.Message)"
}
```

**Arc Connectivity Issues**
```powershell
# List Arc machines
Get-AzConnectedMachine | 
  Select-Object Name, Status, Location | 
  Format-Table

# Test Arc machine connectivity
Get-AzConnectedMachineExtension -MachineName "your-vm-name" -ResourceGroupName "your-vm-resource-group" | 
  Select-Object Name, ProvisioningState, TypeHandlerVersion | 
  Format-Table
```

### Debug Function Execution

```powershell
# View function logs (redirect to Azure portal)
$subscriptionId = (Get-AzContext).Subscription.Id
Write-Host "Stream logs at: https://portal.azure.com/#resource/subscriptions/$subscriptionId/resourceGroups/rg-apppatching-prod/providers/Microsoft.Web/sites/$functionAppName/logs"

# Get function details
Get-AzWebAppFunction -ResourceGroupName "rg-apppatching-prod" -Name $functionAppName -FunctionName "inventory" | 
  Select-Object Name, Config | 
  Format-List
```

## Production Considerations

### Security Hardening

1. **Network Security**
   - Configure private endpoints for storage and function app
   - Restrict function app to VNet integration only
   - Use Azure Firewall for outbound filtering

2. **Access Control**
   - Use Azure AD authentication for function HTTP triggers
   - Implement least-privilege RBAC assignments
   - Regular audit of permissions

3. **Monitoring**
   - Set up Application Insights alerts for failures
   - Configure Log Analytics alerts for security events
   - Monitor Arc agent connectivity

### Scaling Considerations

1. **Function App Plan**
   - Consider Premium plan for larger environments (>1000 VMs)
   - Configure auto-scaling rules based on queue depth
   - Monitor consumption and adjust timeout values

2. **Table Storage Performance**
   - Partition inventory data by VM name for optimal performance
   - Use batch operations for bulk operations
   - Monitor storage transaction limits

3. **Arc Run Command Limits**
   - Maximum 5 concurrent operations per VM
   - Implement queuing for large-scale deployments
   - Add retry logic with exponential backoff

## Maintenance

### Regular Tasks

1. **Update Application Repository**
   ```powershell
   # Add new application versions monthly
   $deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
   $sqlServerName = $deployment.Outputs.sqlServerName.Value
   $sqlDatabaseName = $deployment.Outputs.sqlDatabaseName.Value
   
   Add-ApplicationRepoEntry -ServerName $sqlServerName -DatabaseName $sqlDatabaseName `
                          -SoftwareName "Google Chrome" `
                          -Version "121.0.6100.88" `
                          -InstallCmd "..." `
                          -Vendor "Google"
   ```

2. **Monitor Database Growth**
   ```powershell
   # Check SQL Database size metrics
   $connection = Get-SqlConnection -ServerName $sqlServerName -DatabaseName $sqlDatabaseName
   
   $sizeQuery = @"
   SELECT 
       t.TABLE_NAME,
       p.rows,
       CAST(ROUND(((SUM(a.total_pages) * 8) / 1024.00), 2) AS NUMERIC(36, 2)) AS TotalSpaceMB
   FROM sys.tables t
   INNER JOIN sys.indexes i ON t.OBJECT_ID = i.object_id
   INNER JOIN sys.partitions p ON i.object_id = p.OBJECT_ID AND i.index_id = p.index_id
   INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
   LEFT OUTER JOIN sys.schemas s ON t.schema_id = s.schema_id
   WHERE t.NAME NOT LIKE 'dt%' AND t.is_ms_shipped = 0 AND i.OBJECT_ID > 255
   GROUP BY t.Name, p.Rows
   ORDER BY TotalSpaceMB DESC
"@
   
   $dbSize = Invoke-SqlCommand -Connection $connection -Query $sizeQuery
   $connection.Close()
   $dbSize | Format-Table
   ```

3. **Review Function Performance**
   ```powershell
   # Check function execution metrics
   $subscriptionId = (Get-AzContext).Subscription.Id
   $resourceId = "/subscriptions/$subscriptionId/resourceGroups/rg-apppatching-prod/providers/Microsoft.Web/sites/$functionAppName"
   $startTime = (Get-Date).AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ssZ')
   
   Get-AzMetric -ResourceId $resourceId -MetricName "FunctionExecutionCount" -StartTime $startTime | 
     Select-Object Name, @{Name='ExecutionCount'; Expression={$_.Data.Total}} | 
     Format-Table
   ```

## Next Steps

1. **Extend Application Support**: Add more applications to the repository
2. **Automation**: Create scheduled patch deployment workflows  
3. **Reporting**: Build dashboards for patch compliance reporting
4. **Integration**: Connect with existing ITSM tools for approval workflows