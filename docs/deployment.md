# Azure App Patching - Deployment Guide

## Prerequisites

### Azure Resources
- Azure subscription with appropriate permissions
- Azure Arc-enabled Windows VMs
- Azure Monitor Log Analytics workspace with software inventory data
- Resource group for deployment

### Local Development Environment
- Azure CLI 2.50+ 
- Azure Functions Core Tools v4
- PowerShell 7.4+
- Git
- VS Code (recommended) with Azure Functions extension

### Required Permissions
- Contributor access to target resource group
- User Access Administrator (for RBAC assignments) 
- Azure Connected Machine Resource Administrator (for Arc operations)

## Step 1: Clone Repository

```bash
git clone https://github.com/kgnielsen777/AzureAppPatching.git
cd AzureAppPatching
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
      "value": "East US 2"
    }
  }
}
```

## Step 3: Deploy Infrastructure

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Create resource group
az group create --name "rg-apppatching-prod" --location "East US 2"

# Deploy Bicep template
az deployment group create \
  --resource-group "rg-apppatching-prod" \
  --template-file infra/bicep/main.bicep \
  --parameters @infra/bicep/main.parameters.json
```

The deployment creates:
- Azure Function App with system-assigned managed identity
- Storage Account with Table Storage (VmInventory, ApplicationRepo tables)
- Application Insights for monitoring
- Log Analytics Workspace
- Required RBAC role assignments

## Step 4: Configure Local Development

```bash
# Update local.settings.json with your values
cat > local.settings.json << EOF
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "DefaultEndpointsProtocol=https;AccountName=yoursa;AccountKey=...",
    "FUNCTIONS_WORKER_RUNTIME": "powershell", 
    "FUNCTIONS_WORKER_RUNTIME_VERSION": "7.4",
    "STORAGE_ACCOUNT_NAME": "your-storage-account-name",
    "LOG_ANALYTICS_WORKSPACE_ID": "your-workspace-id"
  }
}
EOF

# Test functions locally
func start --powershell
```

## Step 5: Deploy Function App

```bash
# Get Function App name from deployment output
FUNCTION_APP_NAME=$(az deployment group show \
  --resource-group "rg-apppatching-prod" \
  --name "main" \
  --query "properties.outputs.functionAppName.value" -o tsv)

# Deploy function code
func azure functionapp publish $FUNCTION_APP_NAME
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

```bash
# List functions
az functionapp function list \
  --name $FUNCTION_APP_NAME \
  --resource-group "rg-apppatching-prod" \
  --query "[].{Name:name, Status:config.disabled}" -o table

# Check function logs
az functionapp logs tail \
  --name $FUNCTION_APP_NAME \
  --resource-group "rg-apppatching-prod"
```

### Test Inventory Function

The inventory function runs automatically every 6 hours. To trigger manually:

```bash
# Get the master key
MASTER_KEY=$(az functionapp keys list \
  --name $FUNCTION_APP_NAME \
  --resource-group "rg-apppatching-prod" \
  --query "masterKey" -o tsv)

# Trigger inventory function
curl -X POST "https://$FUNCTION_APP_NAME.azurewebsites.net/admin/functions/inventory" \
  -H "Content-Type: application/json" \
  -H "x-functions-key: $MASTER_KEY" \
  -d '{}'
```

### Test Patching Function

```bash
# Get function URL
PATCH_URL=$(az functionapp function show \
  --name $FUNCTION_APP_NAME \
  --resource-group "rg-apppatching-prod" \
  --function-name patching \
  --query "invokeUrlTemplate" -o tsv)

# Test patch deployment (replace with actual VM details)
curl -X POST "$PATCH_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "machineName": "your-vm-name",
    "softwareName": "Google Chrome", 
    "version": "120.0.6099.109",
    "resourceGroupName": "your-vm-resource-group"
  }'
```

## Step 8: Monitor Operations

### Application Insights

```bash
# Get Application Insights resource
AI_NAME=$(az deployment group show \
  --resource-group "rg-apppatching-prod" \
  --name "main" \
  --query "properties.outputs.applicationInsightsName.value" -o tsv)

# View in portal
echo "Application Insights: https://portal.azure.com/#resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-apppatching-prod/providers/Microsoft.Insights/components/$AI_NAME"
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
```bash
# Verify managed identity is assigned
az functionapp identity show \
  --name $FUNCTION_APP_NAME \
  --resource-group "rg-apppatching-prod"

# Check RBAC assignments
az role assignment list \
  --assignee $(az functionapp identity show --name $FUNCTION_APP_NAME --resource-group "rg-apppatching-prod" --query principalId -o tsv) \
  --all
```

**Storage Access Issues**
```bash
# Test storage connectivity
az storage account show \
  --name "your-storage-account-name" \
  --resource-group "rg-apppatching-prod"

# Check table existence
az storage table list \
  --account-name "your-storage-account-name" \
  --auth-mode login
```

**Arc Connectivity Issues**
```bash
# List Arc machines
az connectedmachine list \
  --query "[].{Name:name, Status:status, Location:location}" -o table

# Test Arc machine connectivity
az connectedmachine extension list \
  --machine-name "your-vm-name" \
  --resource-group "your-vm-resource-group"
```

### Debug Function Execution

```bash
# Stream function logs
az functionapp logs tail \
  --name $FUNCTION_APP_NAME \
  --resource-group "rg-apppatching-prod"

# Get function execution history
az functionapp function show \
  --name $FUNCTION_APP_NAME \
  --resource-group "rg-apppatching-prod" \
  --function-name inventory
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
   ```bash
   # Check table storage metrics
   az monitor metrics list \
     --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-apppatching-prod/providers/Microsoft.Storage/storageAccounts/your-storage-account-name" \
     --metric "TableCount" \
     --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
   ```

3. **Review Function Performance**
   ```bash
   # Check function execution metrics
   az monitor metrics list \
     --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/rg-apppatching-prod/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME" \
     --metric "FunctionExecutionCount" \
     --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)
   ```

## Next Steps

1. **Extend Application Support**: Add more applications to the repository
2. **Automation**: Create scheduled patch deployment workflows  
3. **Reporting**: Build dashboards for patch compliance reporting
4. **Integration**: Connect with existing ITSM tools for approval workflows