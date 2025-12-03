# Profile script for PowerShell Azure Functions
# This runs once when the Function App starts

# Import common modules for all functions
$commonModulesPath = Join-Path $PSScriptRoot "src\scripts\common"

if (Test-Path $commonModulesPath) {
    Write-Host "Loading common modules from: $commonModulesPath"
    
    $modules = @(
        'TableStorageUtils.psm1',
        'ArcUtils.psm1'
    )
    
    foreach ($module in $modules) {
        $modulePath = Join-Path $commonModulesPath $module
        if (Test-Path $modulePath) {
            try {
                Import-Module $modulePath -Force -Global
                Write-Host "Loaded module: $module"
            }
            catch {
                Write-Warning "Failed to load module $module : $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "Module not found: $modulePath"
        }
    }
}

# Set PowerShell execution policy
Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force

# Configure Azure PowerShell for managed identity
if ($env:AZURE_CLIENT_ID) {
    Write-Host "Azure Functions environment detected with managed identity"
}

Write-Host "PowerShell profile loaded successfully"