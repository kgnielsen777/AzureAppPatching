// Table Storage entity models for Azure App Patching
using System;
using Microsoft.Azure.Cosmos.Table;

namespace AzureAppPatching.Models
{
    /// <summary>
    /// VM Inventory entity for Table Storage
    /// PartitionKey: VmName, RowKey: SoftwareName-Date
    /// </summary>
    public class VmInventoryEntity : TableEntity
    {
        public VmInventoryEntity() { }

        public VmInventoryEntity(string vmName, string softwareName, DateTime date)
        {
            PartitionKey = vmName;
            RowKey = $"{softwareName}-{date:yyyyMMddHHmmss}";
            VmName = vmName;
            SoftwareName = softwareName;
            Date = date;
        }

        public DateTime Date { get; set; }
        public string VmName { get; set; }
        public string SoftwareName { get; set; }
        public string SoftwareVersion { get; set; }
        public string Publisher { get; set; }
        public string OsType { get; set; }
        public string ResourceGroup { get; set; }
        public string SubscriptionId { get; set; }
        public DateTime LastSeen { get; set; }
        public string ArcMachineId { get; set; }
        public string Location { get; set; }
        public string Status { get; set; }
    }

    /// <summary>
    /// Application Repository entity for Table Storage  
    /// PartitionKey: SoftwareName, RowKey: Version
    /// </summary>
    public class ApplicationRepoEntity : TableEntity
    {
        public ApplicationRepoEntity() { }

        public ApplicationRepoEntity(string softwareName, string version)
        {
            PartitionKey = softwareName;
            RowKey = version;
            SoftwareName = softwareName;
            Version = version;
        }

        public string SoftwareName { get; set; }
        public string Version { get; set; }
        public string InstallCmd { get; set; }
        public string Vendor { get; set; }
        public string DownloadUrl { get; set; }
        public string InstallationType { get; set; } // System, User, Both
        public string SilentArgs { get; set; }
        public string Architecture { get; set; } // x86, x64, ARM64, Any
        public string MinOsVersion { get; set; }
        public string MaxOsVersion { get; set; }
        public bool RequiresElevation { get; set; }
        public string ChecksumSha256 { get; set; }
        public long FileSizeBytes { get; set; }
        public DateTime ReleaseDate { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime ModifiedDate { get; set; }
        public string Notes { get; set; }
        public bool IsActive { get; set; } = true;
        public int Priority { get; set; } = 0; // Higher priority versions installed first
        public string ScriptPath { get; set; } // Relative path to installation script
        public string UninstallCmd { get; set; }
        public string RegistryKeys { get; set; } // JSON array of registry keys to check
        public string Dependencies { get; set; } // JSON array of required software
    }

    /// <summary>
    /// Patch Deployment History entity for Table Storage
    /// PartitionKey: VmName, RowKey: DeploymentId
    /// </summary>
    public class PatchDeploymentEntity : TableEntity
    {
        public PatchDeploymentEntity() { }

        public PatchDeploymentEntity(string vmName, string deploymentId)
        {
            PartitionKey = vmName;
            RowKey = deploymentId;
            VmName = vmName;
            DeploymentId = deploymentId;
        }

        public string VmName { get; set; }
        public string DeploymentId { get; set; }
        public string SoftwareName { get; set; }
        public string FromVersion { get; set; }
        public string ToVersion { get; set; }
        public string Status { get; set; } // Pending, InProgress, Success, Failed
        public DateTime StartTime { get; set; }
        public DateTime? EndTime { get; set; }
        public string CommandId { get; set; }
        public string ResourceGroup { get; set; }
        public string ErrorMessage { get; set; }
        public string Output { get; set; }
        public int ExitCode { get; set; }
        public string InitiatedBy { get; set; } // User or System
        public string ArcOperationId { get; set; }
        public int RetryCount { get; set; } = 0;
        public DateTime? LastRetry { get; set; }
        public string InstallCmd { get; set; }
        public string ScriptPath { get; set; }
        public TimeSpan Duration => EndTime.HasValue ? EndTime.Value - StartTime : TimeSpan.Zero;
    }

    /// <summary>
    /// Patch Schedule entity for Table Storage
    /// PartitionKey: SoftwareName, RowKey: ScheduleId
    /// </summary>
    public class PatchScheduleEntity : TableEntity
    {
        public PatchScheduleEntity() { }

        public PatchScheduleEntity(string softwareName, string scheduleId)
        {
            PartitionKey = softwareName;
            RowKey = scheduleId;
            SoftwareName = softwareName;
            ScheduleId = scheduleId;
        }

        public string SoftwareName { get; set; }
        public string ScheduleId { get; set; }
        public string ScheduleName { get; set; }
        public string CronExpression { get; set; }
        public string TargetVersion { get; set; } // "Latest" or specific version
        public string VmFilter { get; set; } // JSON filter criteria
        public bool IsEnabled { get; set; } = true;
        public DateTime CreatedDate { get; set; }
        public DateTime ModifiedDate { get; set; }
        public string CreatedBy { get; set; }
        public DateTime? LastRun { get; set; }
        public DateTime? NextRun { get; set; }
        public string MaintenanceWindow { get; set; } // JSON with allowed time ranges
        public int MaxConcurrent { get; set; } = 5; // Max concurrent deployments
        public bool RequireApproval { get; set; } = false;
        public string NotificationEmails { get; set; } // JSON array of emails
        public string PreDeploymentScript { get; set; }
        public string PostDeploymentScript { get; set; }
        public int TimeoutMinutes { get; set; } = 30;
        public bool RollbackOnFailure { get; set; } = false;
    }
}