# Sample Patch Job Configurations

## Single VM Patching

### Example 1: Patch Chrome on Single VM
```json
{
  "machineName": "vm-web-01",
  "softwareName": "Google Chrome",
  "version": "120.0.6099.109",
  "resourceGroupName": "rg-production-vms"
}
```

### Example 2: Patch Firefox (Auto-detect Resource Group)
```json
{
  "machineName": "vm-dev-02",
  "softwareName": "Mozilla Firefox", 
  "version": "121.0"
}
```

## Batch VM Patching

### Example 1: Patch Multiple VMs with Chrome
```json
{
  "maxConcurrency": 3,
  "patchJobs": [
    {
      "machineName": "vm-web-01",
      "softwareName": "Google Chrome",
      "version": "120.0.6099.109",
      "resourceGroupName": "rg-production-vms"
    },
    {
      "machineName": "vm-web-02", 
      "softwareName": "Google Chrome",
      "version": "120.0.6099.109",
      "resourceGroupName": "rg-production-vms"
    },
    {
      "machineName": "vm-web-03",
      "softwareName": "Google Chrome", 
      "version": "120.0.6099.109",
      "resourceGroupName": "rg-production-vms"
    }
  ]
}
```

### Example 2: Mixed Application Patching
```json
{
  "maxConcurrency": 5,
  "patchJobs": [
    {
      "machineName": "vm-office-01",
      "softwareName": "Google Chrome",
      "version": "120.0.6099.109"
    },
    {
      "machineName": "vm-office-01",
      "softwareName": "Mozilla Firefox",
      "version": "121.0"
    },
    {
      "machineName": "vm-office-02", 
      "softwareName": "Google Chrome",
      "version": "120.0.6099.109"
    },
    {
      "machineName": "vm-dev-01",
      "softwareName": "Java",
      "version": "21.0.1"
    },
    {
      "machineName": "vm-dev-02",
      "softwareName": "Visual Studio Code", 
      "version": "1.85.1"
    }
  ]
}
```

### Example 3: Department-wide Patching
```json
{
  "maxConcurrency": 10,
  "patchJobs": [
    {
      "machineName": "vm-hr-01",
      "softwareName": "Adobe Acrobat Reader DC",
      "version": "23.008.20470"
    },
    {
      "machineName": "vm-hr-02",
      "softwareName": "Adobe Acrobat Reader DC", 
      "version": "23.008.20470"
    },
    {
      "machineName": "vm-hr-03",
      "softwareName": "Adobe Acrobat Reader DC",
      "version": "23.008.20470"
    },
    {
      "machineName": "vm-finance-01",
      "softwareName": "7-Zip",
      "version": "23.01"
    },
    {
      "machineName": "vm-finance-02",
      "softwareName": "7-Zip",
      "version": "23.01" 
    }
  ]
}
```

## PowerShell Script Examples

### Single VM Patching
```powershell
# Patch Chrome on single VM
$body = @{
    machineName = "vm-web-01"
    softwareName = "Google Chrome"  
    version = "120.0.6099.109"
    resourceGroupName = "rg-production-vms"
} | ConvertTo-Json

$response = Invoke-RestMethod -Uri "https://your-function-app.azurewebsites.net/api/patching?code=your-function-key" `
                              -Method POST `
                              -Body $body `
                              -ContentType "application/json"

Write-Host "Patch Status: $($response.Status)"
```

### Batch VM Patching
```powershell
# Generate patch jobs for Chrome across multiple VMs
$vmList = @("vm-web-01", "vm-web-02", "vm-web-03", "vm-web-04", "vm-web-05")

$patchJobs = $vmList | ForEach-Object {
    @{
        machineName = $_
        softwareName = "Google Chrome"
        version = "120.0.6099.109"
        resourceGroupName = "rg-production-vms"
    }
}

$body = @{
    maxConcurrency = 3
    patchJobs = $patchJobs
} | ConvertTo-Json -Depth 3

$response = Invoke-RestMethod -Uri "https://your-function-app.azurewebsites.net/api/patching?code=your-function-key" `
                              -Method POST `
                              -Body $body `
                              -ContentType "application/json"

Write-Host "Total Jobs: $($response.TotalJobs)"
Write-Host "Successful: $($response.SuccessfulJobs)" 
Write-Host "Failed: $($response.FailedJobs)"

# Show detailed results
$response.Results | Format-Table MachineName, SoftwareName, Status, Timestamp
```

### Query and Patch Based on Inventory
```powershell
# Get inventory for specific software and patch outdated versions
$inventoryResponse = Invoke-RestMethod -Uri "https://your-function-app.azurewebsites.net/api/inventory?code=your-function-key"

# Filter for Chrome installations that need updating
$chromeVMs = $inventoryResponse.Results | Where-Object { 
    $_.SoftwareName -eq "Google Chrome" -and 
    [Version]$_.SoftwareVersion -lt [Version]"120.0.6099.109"
}

if ($chromeVMs.Count -gt 0) {
    $patchJobs = $chromeVMs | ForEach-Object {
        @{
            machineName = $_.VmName
            softwareName = "Google Chrome"  
            version = "120.0.6099.109"
        }
    }
    
    $patchBody = @{
        maxConcurrency = 5
        patchJobs = $patchJobs
    } | ConvertTo-Json -Depth 3
    
    Write-Host "Patching $($patchJobs.Count) VMs with outdated Chrome versions..."
    
    $patchResponse = Invoke-RestMethod -Uri "https://your-function-app.azurewebsites.net/api/patching?code=your-function-key" `
                                      -Method POST `
                                      -Body $patchBody `
                                      -ContentType "application/json"
    
    Write-Host "Patch deployment initiated. Check results for status."
}
```

## Configuration Parameters

### Request Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `machineName` | string | Yes (single mode) | Name of the Arc-enabled VM |
| `softwareName` | string | Yes (single mode) | Name of software to patch |
| `version` | string | Yes (single mode) | Target version to install |
| `resourceGroupName` | string | No | Resource group containing the VM (auto-detected if not provided) |
| `patchJobs` | array | Yes (batch mode) | Array of patch job objects |
| `maxConcurrency` | integer | No | Maximum concurrent patch operations (default: 5) |

### Response Format

#### Single Mode Response
```json
{
  "MachineName": "vm-web-01",
  "SoftwareName": "Google Chrome", 
  "Version": "120.0.6099.109",
  "Status": "Success",
  "CommandId": "patch-googlechrome-20251203143022",
  "Timestamp": "2025-12-03T14:32:15.123Z",
  "Output": "Installation completed successfully",
  "ResourceGroup": "rg-production-vms"
}
```

#### Batch Mode Response
```json
{
  "TotalJobs": 5,
  "SuccessfulJobs": 4, 
  "FailedJobs": 1,
  "ProcessingMode": "Batch",
  "Timestamp": "2025-12-03T14:35:22.456Z",
  "Results": [
    {
      "MachineName": "vm-web-01",
      "SoftwareName": "Google Chrome",
      "Status": "Success",
      "...": "..."
    }
  ]
}
```