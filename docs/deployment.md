# Azure App Patching - Deployment Guide

## Prerequisites

### Azure Resources
- Azure subscription with appropriate permissions
- Azure Arc-enabled Windows VMs with Defender for Servers enabled
- Resource group for deployment

### Local Development Environment
- PowerShell 7.4+ with Azure PowerShell module
- Azure Functions Core Tools v4
- Git
- VS Code (recommended) with Azure Functions extension

### Required Permissions
- Contributor access to target resource group
- User Access Administrator (for RBAC assignments) 
- Azure Connected Machine Resource Administrator (for Arc operations)

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
    }
  }
}
```

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
- Storage Account with Table Storage (VmInventory, ApplicationRepo tables)
- Required RBAC role assignments for Resource Graph and Arc operations

## Step 4: Configure Local Development

```powershell
# Update local.settings.json with your values
$localSettings = @{
  IsEncrypted = $false
  Values = @{
    AzureWebJobsStorage = "DefaultEndpointsProtocol=https;AccountName=yoursa;AccountKey=..."
    FUNCTIONS_WORKER_RUNTIME = "powershell"
    FUNCTIONS_WORKER_RUNTIME_VERSION = "7.4"
    STORAGE_ACCOUNT_NAME = "your-storage-account-name"
  }
}

$localSettings | ConvertTo-Json -Depth 3 | Out-File "local.settings.json" -Encoding UTF8

# Test functions locally
func start --powershell
```

## Step 5: Deploy Function App

```powershell
# Get Function App name from deployment output
$deployment = Get-AzResourceGroupDeployment -ResourceGroupName "rg-apppatching-prod" -Name "main"
$functionAppName = $deployment.Outputs.functionAppName.Value

# Deploy function code
func azure functionapp publish $functionAppName
```

## Step 6: Seed Application Repository

Run this PowerShell script to add initial application definitions:

```powershell
# Import the Table Storage utilities
Import-Module ".\src\scripts\common\TableStorageUtils.psm1" -Force

# Connect with your user account for initial setup
Connect-AzAccount

# Set variables
$storageAccountName = "your-storage-account-name"

# Add Chrome entry
Add-ApplicationRepoEntry -StorageAccountName $storageAccountName `
                       -SoftwareName "Google Chrome" `
                       -Version "120.0.6099.109" `
                       -InstallCmd "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe /silent /install" `
                       -Vendor "Google"

# Add Firefox entry  
Add-ApplicationRepoEntry -StorageAccountName $storageAccountName `
                       -SoftwareName "Mozilla Firefox" `
                       -Version "121.0" `
                       -InstallCmd "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US /S" `
                       -Vendor "Mozilla"

Write-Host "Application repository seeded successfully"
```

## Step 7: Verify Deployment

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

## Step 8: Monitor Operations

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

### Table Storage Data

```powershell
# Check inventory data
Import-Module ".\src\scripts\common\TableStorageUtils.psm1" -Force
Connect-AzAccount

$ctx = Get-StorageContext -StorageAccountName "your-storage-account-name"
$inventoryTable = Get-AzStorageTable -Name 'VmInventory' -Context $ctx

# Get recent inventory entries
$recentEntries = Get-AzTableRow -Table $inventoryTable.CloudTable | 
                 Where-Object { [DateTime]$_.Date -gt (Get-Date).AddHours(-6) } |
                 Select-Object VmName, SoftwareName, SoftwareVersion, Date

$recentEntries | Format-Table
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

**Storage Access Issues**
```powershell
# Test storage connectivity
$storageAccount = Get-AzStorageAccount -ResourceGroupName "rg-apppatching-prod" -Name "your-storage-account-name"
Write-Host "Storage Account Status: $($storageAccount.ProvisioningState)"
Write-Host "Primary Endpoint: $($storageAccount.PrimaryEndpoints.Table)"

# Check table existence
$ctx = $storageAccount.Context
Get-AzStorageTable -Context $ctx | Select-Object Name | Format-Table
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
   Add-ApplicationRepoEntry -StorageAccountName $storageAccountName `
                          -SoftwareName "Google Chrome" `
                          -Version "121.0.6100.88" `
                          -InstallCmd "..." `
                          -Vendor "Google"
   ```

2. **Monitor Storage Growth**
   ```powershell
   # Check table storage metrics
   $subscriptionId = (Get-AzContext).Subscription.Id
   $resourceId = "/subscriptions/$subscriptionId/resourceGroups/rg-apppatching-prod/providers/Microsoft.Storage/storageAccounts/your-storage-account-name"
   $startTime = (Get-Date).AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ssZ')
   
   Get-AzMetric -ResourceId $resourceId -MetricName "TableCount" -StartTime $startTime | 
     Select-Object Name, @{Name='Value'; Expression={$_.Data.Average}} | 
     Format-Table
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