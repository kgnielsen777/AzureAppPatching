# GitHub Copilot Instructions for AzureAppPatching

## Project Overview
This project implements automated patching solutions for 3rd party applications (starting with Google Chrome) using Azure Functions, Azure Arc, and Azure Storage. The system provides inventory tracking and patch management for hybrid and multi-cloud environments.

## Architecture Overview
- **Azure Functions**: Serverless compute for inventory collection and patch deployment
- **Azure Arc**: Hybrid management plane for executing commands on remote VMs
- **Azure Storage Account**: Centralized storage for patches and metadata using Table Storage
- **Azure Resource Graph**: Query engine for discovering Arc-enabled resources
- **PowerShell/Azure CLI**: Primary automation scripting languages

## Project Structure
```
/
├── .github/
│   ├── workflows/           # CI/CD pipelines for function deployment
│   └── copilot-instructions.md
├── src/
│   ├── functions/
│   │   ├── inventory/       # Azure Function for VM inventory collection
│   │   └── patching/        # Azure Function for patch deployment
│   ├── scripts/
│   │   ├── chrome/          # Chrome-specific installation scripts
│   │   ├── firefox/         # Firefox-specific scripts
│   │   ├── java/            # Java runtime scripts
│   │   └── common/          # Shared PowerShell modules and utilities
│   └── models/              # Data models for Table Storage entities
├── infra/
│   ├── bicep/              # Azure infrastructure (Functions, Storage, Arc)
│   └── arm-templates/       # Alternative ARM templates
├── patches/
│   ├── chrome/             # Chrome browser patches and installers
│   ├── firefox/            # Firefox patches and installers
│   ├── java/               # Java runtime patches
│   └── templates/          # Generic patch deployment templates
├── config/
│   ├── function-settings/   # Function app configuration
│   └── arc-policies/       # Azure Arc governance policies
└── docs/
    ├── architecture.md
    └── deployment.md
```

## Data Schema (Table Storage)

### VM Inventory Table
```csharp
public class VmInventoryEntity : TableEntity
{
    public DateTime Date { get; set; }
    public string VmName { get; set; }
    public string SoftwareName { get; set; }
    public string SoftwareVersion { get; set; }
    // PartitionKey: VmName, RowKey: SoftwareName-Date
}
```

### Application Repository Table
```csharp
public class ApplicationRepoEntity : TableEntity
{
    public string SoftwareName { get; set; }
    public string Version { get; set; }
    public string InstallCmd { get; set; }
    public string Vendor { get; set; }
    // PartitionKey: SoftwareName, RowKey: Version
}
```

## Development Guidelines

### Azure Functions Patterns
- Use PowerShell runtime for Azure Arc integration and Windows compatibility
- Implement timer triggers for scheduled inventory scans
- Use HTTP triggers for on-demand patch deployment
- Enable system-assigned managed identity for authentication to Azure services
- Use managed identity for Table Storage, Resource Graph, and Arc authentication
- Avoid connection strings - leverage managed identity with Azure PowerShell modules

### Azure Arc Integration
- Use Azure Resource Graph to query installed applications across Arc-enabled VMs
- Leverage `Microsoft.HybridCompute/machines/extensions` for software inventory data
- Implement `az connectedmachine run-command` for patch deployment only
- Use system-assigned managed identity for Arc resource access and authentication
- Grant Function App managed identity appropriate RBAC roles for Arc operations
- Implement retry logic for Resource Graph query pagination

### Table Storage Operations
- Use system-assigned managed identity for Storage Account authentication
- Grant Function App managed identity 'Storage Table Data Contributor' role
- Use Azure PowerShell cmdlets with managed identity authentication
- Use batch operations for bulk inventory updates
- Implement proper partition key strategies for performance
- Use continuation tokens for large result sets
- Handle transient storage exceptions with exponential backoff

### Application-Specific Patching Patterns
- **Chrome**: Detect installation paths (`%ProgramFiles%`, `%ProgramFiles(x86)%`, `%LocalAppData%`), use `--silent --force-update` flags
- **Firefox**: Handle ESR vs regular versions, use `-ms` for silent installs
- **Java**: Manage multiple JRE/JDK versions, use `/s` for silent mode
- **Generic Pattern**: Implement pluggable detection and installation modules per application
- Create standardized interfaces for version comparison and installation commands
- Use Application Repo table to store app-specific installation parameters

## Key Commands and Workflows

### Local Development
```powershell
# Test functions locally (use your user identity for local dev)
func start --powershell

# Deploy infrastructure with managed identity enabled
az deployment group create --resource-group rg-patching --template-file infra/bicep/main.bicep

# Deploy function app
func azure functionapp publish func-app-patching

# Assign required RBAC roles to Function App managed identity
az role assignment create --assignee $(az functionapp identity show --resource-group rg-patching --name func-app-patching --query principalId -o tsv) --role "Storage Table Data Contributor" --scope /subscriptions/{subscription-id}/resourceGroups/rg-patching/providers/Microsoft.Storage/storageAccounts/{storage-account}

az role assignment create --assignee $(az functionapp identity show --resource-group rg-patching --name func-app-patching --query principalId -o tsv) --role "Azure Connected Machine Resource Manager" --scope /subscriptions/{subscription-id}

az role assignment create --assignee $(az functionapp identity show --resource-group rg-patching --name func-app-patching --query principalId -o tsv) --role "Reader" --scope /subscriptions/{subscription-id}

# Test Arc connectivity
az connectedmachine list --query "[].{Name:name, Status:status, Location:location}"
```

### Inventory Collection
```powershell
# Query all Arc-enabled machines and their installed software
az graph query --graph-query "
Resources
| where type == 'microsoft.hybridcompute/machines'
| extend machineName = name, machineId = id, osType = properties.osName
| join kind=leftouter (
    Resources
    | where type == 'microsoft.hybridcompute/machines/extensions'
    | where properties.publisher == 'Microsoft.Azure.Monitor'
    | extend machineName = split(id, '/')[8]
    | project machineName, softwareInventory = properties.settings.workspaceId
) on machineName
| project machineName, machineId, osType, resourceGroup = split(id, '/')[4]"

# Query ALL software inventory from Azure Monitor workspace
az monitor log-analytics query --workspace {workspace-id} --analytics-query "
InstalledSoftware
| where TimeGenerated > ago(24h)
| summarize by Computer, SoftwareName, SoftwareVersion, Publisher
| project Computer, SoftwareName, SoftwareVersion, Publisher"
```

### Patch Deployment
```powershell
# Deploy Chrome update to specific VM
az connectedmachine run-command create --resource-group rg-patching --machine-name vm-01 --command-id patch-chrome --script-path scripts/chrome/Install-Chrome.ps1 --parameters version=120.0.6099.109

# Deploy Firefox update
az connectedmachine run-command create --resource-group rg-patching --machine-name vm-01 --command-id patch-firefox --script-path scripts/firefox/Install-Firefox.ps1 --parameters version=121.0

# Deploy Java runtime update
az connectedmachine run-command create --resource-group rg-patching --machine-name vm-01 --command-id patch-java --script-path scripts/java/Install-Java.ps1 --parameters version=21.0.1
```

## Integration Points
- **Azure Resource Graph**: Discover and query Arc-enabled VMs across subscriptions
- **Azure Arc Connected Machine**: Execute remote commands and collect inventory
- **Azure Storage Account**: Store patches, logs, and Table Storage for data persistence
- **Azure Functions**: Serverless execution of inventory and patching workflows with system-assigned managed identity
- **Azure RBAC**: Role-based access control for managed identity permissions across services
- **Azure Key Vault**: Optional secure storage for non-Azure secrets (if needed)

## Application Patching Workflow
1. **Inventory Function**: Queries Azure Resource Graph and Monitor workspace for all installed software
2. **Data Processing**: Stores ALL discovered applications and versions (no filtering at inventory stage)
3. **Storage**: Stores complete inventory results in VM Inventory Table Storage
4. **Version Check**: Compares installed versions against Application Repo table for supported applications only
5. **Patching**: Downloads and installs application updates via Arc run-command using app-specific scripts
6. **Verification**: Re-queries Resource Graph to confirm successful installation across all target applications

## Error Handling Patterns
- Implement exponential backoff for Azure Resource Graph queries
- Handle Arc agent offline scenarios gracefully
- Retry failed patch deployments with different strategies per application
- Log all operations to Application Insights for debugging and monitoring
- Use dead letter queues for failed patch operations

## Prerequisites for Development
- Azure CLI installed and authenticated
- Azure Functions Core Tools v4
- PowerShell 7+ 
- Azure Arc test VMs available for integration testing
- Azure Monitor workspace configured for software inventory collection

## Testing Strategy
- Unit tests for PowerShell modules using Pester
- Integration tests with Azure Arc test VMs
- Table Storage operations testing with Azure Storage Emulator
- Function app testing with local Azure Functions runtime

When implementing features, prioritize Azure-native serverless patterns, secure Arc authentication, and robust error handling for hybrid connectivity scenarios.