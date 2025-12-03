# Common utilities for SQL Database operations with managed identity
param()

# Import required modules
Import-Module Az.Sql -Force
Import-Module Az.Accounts -Force
Import-Module SqlServer -Force

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

function Get-SqlAccessToken {
    <#
    .SYNOPSIS
    Gets SQL Database access token for managed identity authentication
    #>
    try {
        # Connect with managed identity
        if (-not (Connect-ToAzureWithManagedIdentity)) {
            throw "Failed to connect to Azure"
        }
        
        # Get access token for SQL Database
        $accessToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token
        return $accessToken
    }
    catch {
        Write-Error "Failed to get SQL access token: $($_.Exception.Message)"
        throw
    }
}

function Invoke-SqlCommand {
    <#
    .SYNOPSIS
    Executes SQL command and returns results using managed identity
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$Parameters = @{}
    )
    
    try {
        $accessToken = Get-SqlAccessToken
        
        # Build parameterized query by replacing @parameters with properly formatted values
        $finalQuery = $Query
        foreach ($param in $Parameters.GetEnumerator()) {
            $paramName = "@$($param.Key)"
            if ($param.Value -eq $null -or $param.Value -eq '') {
                $paramValue = 'NULL'
            } else {
                # Escape single quotes and wrap strings in quotes
                $escapedValue = $param.Value.ToString().Replace("'", "''")
                $paramValue = "'$escapedValue'"
            }
            $finalQuery = $finalQuery.Replace($paramName, $paramValue)
        }
        
        # Execute query
        $result = Invoke-Sqlcmd -ServerInstance "$ServerName.database.windows.net" -Database $DatabaseName -Query $finalQuery -AccessToken $accessToken
        return $result
    }
    catch {
        Write-Error "Failed to execute SQL command: $($_.Exception.Message)"
        throw
    }
}

function Add-VmInventoryEntry {
    <#
    .SYNOPSIS
    Adds a VM inventory entry to SQL Database
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareVersion,
        
        [Parameter(Mandatory = $false)]
        [string]$Publisher = $null,
        
        [datetime]$Date = (Get-Date)
    )
    
    try {
        $query = "EXEC sp_AddVmInventoryEntry @VmName, @SoftwareName, @SoftwareVersion, @Publisher, @Date"
        
        $parameters = @{
            VmName = $VmName
            SoftwareName = $SoftwareName
            SoftwareVersion = $SoftwareVersion
            Publisher = $Publisher
            Date = $Date.ToString('yyyy-MM-dd HH:mm:ss')
        }
        
        Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Query $query -Parameters $parameters | Out-Null
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
    Adds an application repository entry to SQL Database
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareName,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [string]$InstallCmd,
        
        [Parameter(Mandatory = $true)]
        [string]$Vendor,
        
        [Parameter(Mandatory = $false)]
        [string]$OSPlatform = 'Windows',
        
        [Parameter(Mandatory = $false)]
        [string]$Architecture = 'x64'
    )
    
    try {
        $query = @"
        IF EXISTS (SELECT 1 FROM ApplicationRepo WHERE SoftwareName = @SoftwareName AND Version = @Version AND OSPlatform = @OSPlatform AND Architecture = @Architecture)
            UPDATE ApplicationRepo SET InstallCmd = @InstallCmd, Vendor = @Vendor, UpdatedAt = GETUTCDATE() 
            WHERE SoftwareName = @SoftwareName AND Version = @Version AND OSPlatform = @OSPlatform AND Architecture = @Architecture
        ELSE
            INSERT INTO ApplicationRepo (SoftwareName, Version, InstallCmd, Vendor, OSPlatform, Architecture) 
            VALUES (@SoftwareName, @Version, @InstallCmd, @Vendor, @OSPlatform, @Architecture)
"@
        
        $parameters = @{
            SoftwareName = $SoftwareName
            Version = $Version
            InstallCmd = $InstallCmd
            Vendor = $Vendor
            OSPlatform = $OSPlatform
            Architecture = $Architecture
        }
        
        Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Query $query -Parameters $parameters | Out-Null
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
    Gets an application repository entry from SQL Database
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareName,
        
        [Parameter(Mandatory = $false)]
        [string]$OSPlatform = 'Windows'
    )
    
    try {
        $query = "EXEC sp_GetApplicationRepoEntry @SoftwareName, @OSPlatform"
        
        $parameters = @{
            SoftwareName = $SoftwareName
            OSPlatform = $OSPlatform
        }
        
        $result = Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Query $query -Parameters $parameters
        return $result
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
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $false)]
        [int]$DaysToKeep = 30
    )
    
    try {
        $query = "EXEC sp_CleanupOldInventoryEntries @DaysToKeep"
        
        $parameters = @{
            DaysToKeep = $DaysToKeep
        }
        
        $result = Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Query $query -Parameters $parameters
        Write-Host "Removed $($result.DeletedRows) old inventory entries"
    }
    catch {
        Write-Error "Failed to clear old inventory entries: $($_.Exception.Message)"
        throw
    }
}

function New-PatchJob {
    <#
    .SYNOPSIS
    Creates a new patch job entry
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        
        [Parameter(Mandatory = $true)]
        [string]$SoftwareName,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetVersion,
        
        [Parameter(Mandatory = $false)]
        [string]$PreviousVersion = $null
    )
    
    try {
        $query = "EXEC sp_LogPatchJob NULL, @VmName, @SoftwareName, @TargetVersion, @PreviousVersion"
        
        $parameters = @{
            VmName = $VmName
            SoftwareName = $SoftwareName
            TargetVersion = $TargetVersion
            PreviousVersion = $PreviousVersion
        }
        
        $result = Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Query $query -Parameters $parameters
        if ($result -and $result.JobId) {
            return $result.JobId
        }
        return $result
    }
    catch {
        Write-Error "Failed to create patch job: $($_.Exception.Message)"
        throw
    }
}

function Update-PatchJob {
    <#
    .SYNOPSIS
    Updates an existing patch job
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServerName,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        
        [Parameter(Mandatory = $true)]
        [guid]$JobId,
        
        [Parameter(Mandatory = $true)]
        [string]$Status,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = $null,
        
        [Parameter(Mandatory = $false)]
        [string]$ExecutionLog = $null
    )
    
    try {
        $query = "EXEC sp_LogPatchJob @JobId, NULL, NULL, NULL, NULL, @Status, @ErrorMessage, @ExecutionLog"
        
        $parameters = @{
            JobId = $JobId.ToString()
            Status = $Status
            ErrorMessage = $ErrorMessage
            ExecutionLog = $ExecutionLog
        }
        
        Invoke-SqlCommand -ServerName $ServerName -DatabaseName $DatabaseName -Query $query -Parameters $parameters | Out-Null
        Write-Host "Updated patch job $JobId with status: $Status"
    }
    catch {
        Write-Error "Failed to update patch job: $($_.Exception.Message)"
        throw
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Connect-ToAzureWithManagedIdentity',
    'Get-SqlAccessToken',
    'Invoke-SqlCommand',
    'Add-VmInventoryEntry',
    'Add-ApplicationRepoEntry', 
    'Get-ApplicationRepoEntry',
    'Clear-OldInventoryEntries',
    'New-PatchJob',
    'Update-PatchJob'
)