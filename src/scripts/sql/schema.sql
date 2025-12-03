-- Azure App Patching Database Schema
-- This script creates the database schema for VM inventory and application repository

-- Create VmInventory table
CREATE TABLE VmInventory (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    VmName NVARCHAR(255) NOT NULL,
    SoftwareName NVARCHAR(255) NOT NULL,
    SoftwareVersion NVARCHAR(100) NOT NULL,
    Publisher NVARCHAR(255) NULL,
    Date DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    
    -- Create index for efficient querying
    INDEX IX_VmInventory_VmName_Date (VmName, Date DESC),
    INDEX IX_VmInventory_SoftwareName (SoftwareName),
    
    -- Ensure uniqueness per VM, software, and date
    CONSTRAINT UK_VmInventory_VmSoftwareDate UNIQUE (VmName, SoftwareName, Date)
);

-- Create ApplicationRepo table
CREATE TABLE ApplicationRepo (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    SoftwareName NVARCHAR(255) NOT NULL,
    Version NVARCHAR(100) NOT NULL,
    InstallCmd NVARCHAR(2000) NOT NULL,
    Vendor NVARCHAR(255) NOT NULL,
    OSPlatform NVARCHAR(50) NOT NULL DEFAULT 'Windows',
    Architecture NVARCHAR(50) NULL DEFAULT 'x64',
    CreatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    UpdatedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    IsActive BIT NOT NULL DEFAULT 1,
    
    -- Create indexes for efficient querying
    INDEX IX_ApplicationRepo_SoftwareName_OSPlatform (SoftwareName, OSPlatform),
    INDEX IX_ApplicationRepo_Vendor (Vendor),
    
    -- Ensure uniqueness per software, version, and platform
    CONSTRAINT UK_ApplicationRepo_SoftwareVersionPlatform UNIQUE (SoftwareName, Version, OSPlatform, Architecture)
);

-- Create PatchJobs table for tracking patch deployment history
CREATE TABLE PatchJobs (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    JobId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    VmName NVARCHAR(255) NOT NULL,
    SoftwareName NVARCHAR(255) NOT NULL,
    TargetVersion NVARCHAR(100) NOT NULL,
    PreviousVersion NVARCHAR(100) NULL,
    Status NVARCHAR(50) NOT NULL DEFAULT 'Pending', -- Pending, Running, Succeeded, Failed
    StartedAt DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
    CompletedAt DATETIME2 NULL,
    ErrorMessage NVARCHAR(MAX) NULL,
    ExecutionLog NVARCHAR(MAX) NULL,
    
    -- Create indexes for efficient querying
    INDEX IX_PatchJobs_VmName_Status (VmName, Status),
    INDEX IX_PatchJobs_StartedAt (StartedAt DESC),
    INDEX IX_PatchJobs_JobId (JobId)
);

-- Insert initial application repository data
INSERT INTO ApplicationRepo (SoftwareName, Version, InstallCmd, Vendor, OSPlatform, Architecture) VALUES
('Google Chrome', '120.0.6099.109', 'https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe /silent /install', 'Google', 'Windows', 'x64'),
('Mozilla Firefox', '121.0', 'https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US /S', 'Mozilla', 'Windows', 'x64'),
('Java Runtime Environment', '21.0.1', 'https://download.oracle.com/java/21/latest/jdk-21_windows-x64_bin.exe /s', 'Oracle', 'Windows', 'x64');
GO

-- Create stored procedures for common operations

-- Procedure to add VM inventory entry
CREATE PROCEDURE sp_AddVmInventoryEntry
    @VmName NVARCHAR(255),
    @SoftwareName NVARCHAR(255),
    @SoftwareVersion NVARCHAR(100),
    @Publisher NVARCHAR(255) = NULL,
    @Date DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @Date IS NULL
        SET @Date = GETUTCDATE();
    
    -- Use MERGE to handle duplicate entries
    MERGE VmInventory AS target
    USING (SELECT @VmName AS VmName, @SoftwareName AS SoftwareName, @Date AS Date) AS source
    ON target.VmName = source.VmName AND target.SoftwareName = source.SoftwareName AND target.Date = source.Date
    WHEN MATCHED THEN
        UPDATE SET SoftwareVersion = @SoftwareVersion, Publisher = @Publisher, CreatedAt = GETUTCDATE()
    WHEN NOT MATCHED THEN
        INSERT (VmName, SoftwareName, SoftwareVersion, Publisher, Date)
        VALUES (@VmName, @SoftwareName, @SoftwareVersion, @Publisher, @Date);
END;
GO

-- Procedure to get application repository entry
CREATE PROCEDURE sp_GetApplicationRepoEntry
    @SoftwareName NVARCHAR(255),
    @OSPlatform NVARCHAR(50) = 'Windows'
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT TOP 1 Id, SoftwareName, Version, InstallCmd, Vendor, OSPlatform, Architecture
    FROM ApplicationRepo
    WHERE SoftwareName = @SoftwareName 
      AND OSPlatform = @OSPlatform 
      AND IsActive = 1
    ORDER BY CreatedAt DESC;
END;
GO

-- Procedure to log patch job
CREATE PROCEDURE sp_LogPatchJob
    @JobId UNIQUEIDENTIFIER = NULL,
    @VmName NVARCHAR(255),
    @SoftwareName NVARCHAR(255),
    @TargetVersion NVARCHAR(100),
    @PreviousVersion NVARCHAR(100) = NULL,
    @Status NVARCHAR(50) = 'Pending',
    @ErrorMessage NVARCHAR(MAX) = NULL,
    @ExecutionLog NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF @JobId IS NULL
        SET @JobId = NEWID();
    
    IF EXISTS (SELECT 1 FROM PatchJobs WHERE JobId = @JobId)
    BEGIN
        -- Update existing job
        UPDATE PatchJobs
        SET Status = @Status,
            ErrorMessage = @ErrorMessage,
            ExecutionLog = @ExecutionLog,
            CompletedAt = CASE WHEN @Status IN ('Succeeded', 'Failed') THEN GETUTCDATE() ELSE CompletedAt END
        WHERE JobId = @JobId;
    END
    ELSE
    BEGIN
        -- Insert new job
        INSERT INTO PatchJobs (JobId, VmName, SoftwareName, TargetVersion, PreviousVersion, Status, ErrorMessage, ExecutionLog)
        VALUES (@JobId, @VmName, @SoftwareName, @TargetVersion, @PreviousVersion, @Status, @ErrorMessage, @ExecutionLog);
    END;
    
    SELECT @JobId AS JobId;
END;
GO

-- Procedure to clean up old inventory entries (keep last 30 days)
CREATE PROCEDURE sp_CleanupOldInventoryEntries
    @DaysToKeep INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @CutoffDate DATETIME2 = DATEADD(DAY, -@DaysToKeep, GETUTCDATE());
    
    DELETE FROM VmInventory
    WHERE Date < @CutoffDate;
    
    SELECT @@ROWCOUNT AS DeletedRows;
END;
GO