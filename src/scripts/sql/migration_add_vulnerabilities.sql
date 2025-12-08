-- Migration script to add numberOfKnownVulnerabilities field to VmInventory table
-- Run this script against your Azure SQL Database

-- Step 1: Add the new column to VmInventory table
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
               WHERE TABLE_NAME = 'VmInventory' AND COLUMN_NAME = 'numberOfKnownVulnerabilities')
BEGIN
    ALTER TABLE VmInventory
    ADD numberOfKnownVulnerabilities INT NOT NULL DEFAULT 0;
    
    PRINT 'Added numberOfKnownVulnerabilities column to VmInventory table';
END
ELSE
BEGIN
    PRINT 'numberOfKnownVulnerabilities column already exists in VmInventory table';
END
GO

-- Step 2: Drop and recreate the stored procedure to include the new parameter
IF OBJECT_ID('sp_AddVmInventoryEntry', 'P') IS NOT NULL
    DROP PROCEDURE sp_AddVmInventoryEntry;
GO

CREATE PROCEDURE sp_AddVmInventoryEntry
    @VmName NVARCHAR(255),
    @SoftwareName NVARCHAR(255),
    @SoftwareVersion NVARCHAR(100),
    @Publisher NVARCHAR(255) = NULL,
    @Date DATETIME2 = NULL,
    @numberOfKnownVulnerabilities INT = 0
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
        UPDATE SET SoftwareVersion = @SoftwareVersion, 
                   Publisher = @Publisher, 
                   numberOfKnownVulnerabilities = @numberOfKnownVulnerabilities,
                   CreatedAt = GETUTCDATE()
    WHEN NOT MATCHED THEN
        INSERT (VmName, SoftwareName, SoftwareVersion, Publisher, Date, numberOfKnownVulnerabilities)
        VALUES (@VmName, @SoftwareName, @SoftwareVersion, @Publisher, @Date, @numberOfKnownVulnerabilities);
END;
GO

PRINT 'Migration completed successfully - numberOfKnownVulnerabilities support added';