# Chrome installation script for Azure Arc run-command
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallCommand,
    
    [Parameter(Mandatory = $true)]
    [string]$Version,
    
    [Parameter(Mandatory = $false)]
    [string]$SoftwareName = "Google Chrome"
)

function Get-ChromeInstallPaths {
    # Common Chrome installation paths
    return @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "${env:LOCALAPPDATA}\Google\Chrome\Application\chrome.exe"
    )
}

function Get-InstalledChromeVersion {
    $chromePaths = Get-ChromeInstallPaths
    
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            try {
                $version = (Get-ItemProperty $path).VersionInfo.ProductVersion
                return @{
                    Path = $path
                    Version = $version
                    InstallationType = if ($path -like "*Program Files*") { "System" } else { "User" }
                }
            }
            catch {
                Write-Warning "Failed to get version from $path : $($_.Exception.Message)"
            }
        }
    }
    
    return $null
}

function Test-ChromeVersionComparison {
    param(
        [string]$CurrentVersion,
        [string]$TargetVersion
    )
    
    try {
        $current = [Version]$CurrentVersion
        $target = [Version]$TargetVersion
        
        return $target -gt $current
    }
    catch {
        Write-Warning "Failed to compare versions: $($_.Exception.Message)"
        return $true  # Assume update needed if version comparison fails
    }
}

try {
    Write-Host "Starting Chrome installation/update process..."
    Write-Host "Target Version: $Version"
    Write-Host "Install Command: $InstallCommand"
    
    # Check current Chrome installation
    $currentInstall = Get-InstalledChromeVersion
    
    if ($currentInstall) {
        Write-Host "Current Chrome installation found:"
        Write-Host "  Path: $($currentInstall.Path)"
        Write-Host "  Version: $($currentInstall.Version)"
        Write-Host "  Type: $($currentInstall.InstallationType)"
        
        # Check if update is needed
        $updateNeeded = Test-ChromeVersionComparison -CurrentVersion $currentInstall.Version -TargetVersion $Version
        
        if (-not $updateNeeded) {
            Write-Host "Chrome version $($currentInstall.Version) is already at or newer than target version $Version"
            return @{
                Status = "Success"
                Message = "Chrome is already up to date"
                CurrentVersion = $currentInstall.Version
                TargetVersion = $Version
            }
        }
        
        Write-Host "Update needed from version $($currentInstall.Version) to $Version"
    }
    else {
        Write-Host "No existing Chrome installation found, proceeding with fresh installation"
    }
    
    # Create temporary directory for download
    $tempDir = Join-Path $env:TEMP "ChromeInstall_$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    Write-Host "Created temporary directory: $tempDir"
    
    try {
        # Parse the install command to extract download URL if needed
        if ($InstallCommand -match "http[s]?://[^\s]+") {
            $downloadUrl = $Matches[0]
            $installerPath = Join-Path $tempDir "ChromeSetup.exe"
            
            Write-Host "Downloading Chrome installer from: $downloadUrl"
            
            # Download the installer
            try {
                Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
                Write-Host "Download completed successfully"
            }
            catch {
                throw "Failed to download Chrome installer: $($_.Exception.Message)"
            }
            
            # Verify the download
            if (-not (Test-Path $installerPath)) {
                throw "Downloaded installer not found at $installerPath"
            }
            
            $fileSize = (Get-Item $installerPath).Length
            Write-Host "Downloaded file size: $([math]::Round($fileSize / 1MB, 2)) MB"
            
            # Update install command to use local installer
            $InstallCommand = "`"$installerPath`" /silent /install"
        }
        
        # Execute the installation
        Write-Host "Executing installation command: $InstallCommand"
        
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/c $InstallCommand"
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        
        # Wait for completion with timeout
        $timeoutMinutes = 10
        if (-not $process.WaitForExit($timeoutMinutes * 60 * 1000)) {
            $process.Kill()
            throw "Installation timed out after $timeoutMinutes minutes"
        }
        
        $exitCode = $process.ExitCode
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        
        Write-Host "Installation process completed with exit code: $exitCode"
        
        if ($stdout) {
            Write-Host "STDOUT: $stdout"
        }
        
        if ($stderr) {
            Write-Host "STDERR: $stderr"
        }
        
        # Check installation result
        if ($exitCode -eq 0) {
            # Verify installation
            Start-Sleep -Seconds 5  # Give Chrome a moment to complete installation
            
            $newInstall = Get-InstalledChromeVersion
            
            if ($newInstall) {
                Write-Host "Installation verification successful"
                Write-Host "Installed Chrome version: $($newInstall.Version)"
                
                return @{
                    Status = "Success"
                    Message = "Chrome installation/update completed successfully"
                    PreviousVersion = if ($currentInstall) { $currentInstall.Version } else { "None" }
                    NewVersion = $newInstall.Version
                    TargetVersion = $Version
                    InstallationType = $newInstall.InstallationType
                    ExitCode = $exitCode
                }
            }
            else {
                throw "Installation appeared to succeed but Chrome executable not found"
            }
        }
        else {
            throw "Installation failed with exit code $exitCode. STDERR: $stderr"
        }
    }
    finally {
        # Cleanup temporary directory
        if (Test-Path $tempDir) {
            try {
                Remove-Item $tempDir -Recurse -Force
                Write-Host "Cleaned up temporary directory: $tempDir"
            }
            catch {
                Write-Warning "Failed to cleanup temporary directory: $($_.Exception.Message)"
            }
        }
    }
}
catch {
    $errorMessage = "Chrome installation failed: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    return @{
        Status = "Failed"
        Message = $errorMessage
        TargetVersion = $Version
        Error = $_.Exception.Message
    }
}