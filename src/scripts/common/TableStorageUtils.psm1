# Common utilities for Table Storage operations with managed identity
param()

# Import required modules
Import-Module Az.Storage -Force
Import-Module Az.Accounts -Force

function Connect-ToAzureWithManagedIdentity {
    <#
    .SYNOPSIS
    Connects to Azure using managed identity
    #>
    try {
        $context = Get-AzContext
        if (-not $context) {
            Write-Host "Connecting to Azure with managed identity..."
            Connect-AzAccount -Identity
        }
        return $true
    }
    catch {
        Write-Error "Failed to connect to Azure with managed identity: $($_.Exception.Message)"
        return $false
    }
}

function Get-StorageContext {
    <#
    .SYNOPSIS
    Gets Azure Storage context using managed identity
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName
    )
    
    try {
        # Connect with managed identity
        if (-not (Connect-ToAzureWithManagedIdentity)) {
            throw "Failed to connect to Azure"
        }
        
        # Get storage context using managed identity
        $ctx = New-AzStorageContext -StorageAccountName $StorageAccountName -UseConnectedAccount
        return $ctx
    }
    catch {
        Write-Error "Failed to get storage context: $($_.Exception.Message)"
        throw
    }
}

function Add-VmInventoryEntry {
    <#
    .SYNOPSIS
    Adds a VM inventory entry to Table Storage
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareVersion,
        
        [datetime]$Date = (Get-Date)
    )
    
    try {
        $ctx = Get-StorageContext -StorageAccountName $StorageAccountName
        $table = Get-AzStorageTable -Name 'VmInventory' -Context $ctx
        
        $partitionKey = $VmName
        $rowKey = "$SoftwareName-$($Date.ToString('yyyyMMddHHmmss'))"
        
        $entity = @{
            PartitionKey = $partitionKey
            RowKey = $rowKey
            VmName = $VmName
            SoftwareName = $SoftwareName
            SoftwareVersion = $SoftwareVersion
            Date = $Date.ToString('o')
        }
        
        Add-AzTableRow -Table $table.CloudTable -Property $entity
        Write-Host "Added inventory entry for $VmName - $SoftwareName $SoftwareVersion"
    }
    catch {
        Write-Error "Failed to add VM inventory entry: $($_.Exception.Message)"
        throw
    }
}

function Add-ApplicationRepoEntry {
    <#
    .SYNOPSIS
    Adds an application repository entry to Table Storage
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareName,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [string]$InstallCmd,
        
        [Parameter(Mandatory = $true)]
        [string]$Vendor
    )
    
    try {
        $ctx = Get-StorageContext -StorageAccountName $StorageAccountName
        $table = Get-AzStorageTable -Name 'ApplicationRepo' -Context $ctx
        
        $partitionKey = $SoftwareName
        $rowKey = $Version
        
        $entity = @{
            PartitionKey = $partitionKey
            RowKey = $rowKey
            SoftwareName = $SoftwareName
            Version = $Version
            InstallCmd = $InstallCmd
            Vendor = $Vendor
        }
        
        Add-AzTableRow -Table $table.CloudTable -Property $entity -UpdateExisting
        Write-Host "Added/Updated application repo entry for $SoftwareName $Version"
    }
    catch {
        Write-Error "Failed to add application repo entry: $($_.Exception.Message)"
        throw
    }
}

function Get-ApplicationRepoEntry {
    <#
    .SYNOPSIS
    Gets an application repository entry from Table Storage
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareName,
        
        [Parameter(Mandatory = $false)]
        [string]$Version
    )
    
    try {
        $ctx = Get-StorageContext -StorageAccountName $StorageAccountName
        $table = Get-AzStorageTable -Name 'ApplicationRepo' -Context $ctx
        
        if ($Version) {
            $entity = Get-AzTableRow -Table $table.CloudTable -PartitionKey $SoftwareName -RowKey $Version
            return $entity
        }
        else {
            $entities = Get-AzTableRow -Table $table.CloudTable -PartitionKey $SoftwareName
            return $entities
        }
    }
    catch {
        Write-Error "Failed to get application repo entry: $($_.Exception.Message)"
        return $null
    }
}

function Clear-OldInventoryEntries {
    <#
    .SYNOPSIS
    Clears inventory entries older than specified days
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,
        
        [Parameter(Mandatory = $false)]
        [int]$DaysToKeep = 7
    )
    
    try {
        $ctx = Get-StorageContext -StorageAccountName $StorageAccountName
        $table = Get-AzStorageTable -Name 'VmInventory' -Context $ctx
        
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $filter = "Date lt datetime'$($cutoffDate.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))'"
        
        $oldEntries = Get-AzTableRow -Table $table.CloudTable -CustomFilter $filter
        
        foreach ($entry in $oldEntries) {
            Remove-AzTableRow -Table $table.CloudTable -Entity $entry
        }
        
        Write-Host "Removed $($oldEntries.Count) old inventory entries"
    }
    catch {
        Write-Error "Failed to clear old inventory entries: $($_.Exception.Message)"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Connect-ToAzureWithManagedIdentity',
    'Get-StorageContext',
    'Add-VmInventoryEntry',
    'Add-ApplicationRepoEntry', 
    'Get-ApplicationRepoEntry',
    'Clear-OldInventoryEntries'
)