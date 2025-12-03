# Deployment Guide - Azure App Patching Solution

## Prerequisites

Before deploying the Azure App Patching solution, ensure you have:

### Azure Prerequisites
- Azure subscription with appropriate permissions
- Azure CLI installed and authenticated
- PowerShell 7.0 or later
- Azure Functions Core Tools v4
- Git for source control

### Required Azure Permissions
Your account needs the following permissions:
- **Contributor** role on the target resource group
- **User Access Administrator** role to assign managed identity permissions
- **Reader** role on subscriptions where Arc machines are located

### Azure Arc Prerequisites
- VMs must be Arc-enabled with Azure Connected Machine agent installed
- Azure Monitor agent installed on Arc machines for software inventory
- Log Analytics workspace configured for InstalledSoftware data collection

## Step 1: Clone and Prepare Repository

```powershell
# Clone the repository
git clone https://github.com/your-org/AzureAppPatching.git
cd AzureAppPatching

# Review configuration files
Get-ChildItem -Recurse -Include "*.json", "*.bicep", "*.ps1" | Select-Object Name, Directory
```

## Step 2: Deploy Azure Infrastructure

### Using Azure CLI

```powershell
# Set deployment parameters
$resourceGroupName = "rg-azapppatching-prod"
$location = "East US"
$environment = "prod"

# Create resource group
az group create --name $resourceGroupName --location $location

# Deploy infrastructure
$deployment = az deployment group create `
    --resource-group $resourceGroupName `
    --template-file "infra/bicep/main.bicep" `
    --parameters environment=$environment `
    --output json | ConvertFrom-Json

# Extract output values
$functionAppName = $deployment.properties.outputs.functionAppName.value
$storageAccountName = $deployment.properties.outputs.storageAccountName.value

Write-Host "Function App: $functionAppName"
Write-Host "Storage Account: $storageAccountName"
```

## Step 3: Deploy Function App Code

```powershell
# Navigate to project root
cd C:\path\to\AzureAppPatching

# Deploy to Azure
func azure functionapp publish $functionAppName --powershell
```

## Step 4: Seed Application Repository

```powershell
# Run the seeding script
./scripts/Seed-ApplicationRepo.ps1 -StorageAccountName $storageAccountName
```

## Step 5: Test Patching Function

### Single VM Patch Example
```powershell
$body = @{
    machineName = "vm-web-01"
    softwareName = "Google Chrome"
    version = "120.0.6099.109"
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "https://$functionAppName.azurewebsites.net/api/patching?code=$functionKey" `
                              -Method POST `
                              -Body $body `
                              -ContentType "application/json"

Write-Host "Status: $($response.Status)"
```

### Batch VM Patch Example
```powershell
$batchBody = @{
    maxConcurrency = 3
    patchJobs = @(
        @{
            machineName = "vm-web-01"
            softwareName = "Google Chrome"
            version = "120.0.6099.109"
        },
        @{
            machineName = "vm-web-02"
            softwareName = "Google Chrome"
            version = "120.0.6099.109"
        },
        @{
            machineName = "vm-web-03"
            softwareName = "Mozilla Firefox"
            version = "121.0"
        }
    )
} | ConvertTo-Json -Depth 3

$response = Invoke-RestMethod -Uri "https://$functionAppName.azurewebsites.net/api/patching?code=$functionKey" `
                              -Method POST `
                              -Body $batchBody `
                              -ContentType "application/json"

Write-Host "Total Jobs: $($response.TotalJobs)"
Write-Host "Successful: $($response.SuccessfulJobs)"
Write-Host "Failed: $($response.FailedJobs)"
```