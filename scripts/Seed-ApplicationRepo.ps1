# Sample script to seed the Application Repository with common applications
# Run this after deployment to populate the system with patchable applications

param(
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName
)

# Import the Table Storage utilities
Import-Module "$PSScriptRoot\src\scripts\common\TableStorageUtils.psm1" -Force

try {
    # Connect to Azure (assumes you're already authenticated)
    Write-Host "Connecting to Azure with managed identity or user account..."
    
    # Chrome entries
    Write-Host "Adding Google Chrome versions..."
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Google Chrome" `
                           -Version "120.0.6099.109" `
                           -InstallCmd "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe /silent /install" `
                           -Vendor "Google"
    
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Google Chrome" `
                           -Version "121.0.6167.85" `
                           -InstallCmd "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe /silent /install" `
                           -Vendor "Google"
    
    # Firefox entries
    Write-Host "Adding Mozilla Firefox versions..."
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Mozilla Firefox" `
                           -Version "121.0" `
                           -InstallCmd "https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US /S" `
                           -Vendor "Mozilla"
    
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Mozilla Firefox ESR" `
                           -Version "115.6.0" `
                           -InstallCmd "https://download.mozilla.org/?product=firefox-esr-latest&os=win64&lang=en-US /S" `
                           -Vendor "Mozilla"
    
    # Java entries
    Write-Host "Adding Java Runtime versions..."
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Java 8 Update 391" `
                           -Version "8.0.3910.13" `
                           -InstallCmd "https://javadl.oracle.com/webapps/download/AutoDL?BundleId=248240_478a62b7d4e34b78b671c754eaaf38ab /s" `
                           -Vendor "Oracle"
    
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Java" `
                           -Version "21.0.1" `
                           -InstallCmd "https://download.oracle.com/java/21/latest/jdk-21_windows-x64_bin.exe /s" `
                           -Vendor "Oracle"
    
    # Adobe Reader entries  
    Write-Host "Adding Adobe Acrobat Reader versions..."
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Adobe Acrobat Reader DC" `
                           -Version "23.008.20470" `
                           -InstallCmd "https://ardownload2.adobe.com/pub/adobe/reader/win/AcrobatDC/2300820470/AcroRdrDC2300820470_en_US.exe /sAll /rs /msi EULA_ACCEPT=YES" `
                           -Vendor "Adobe"
    
    # 7-Zip entries
    Write-Host "Adding 7-Zip versions..."
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "7-Zip" `
                           -Version "23.01" `
                           -InstallCmd "https://www.7-zip.org/a/7z2301-x64.exe /S" `
                           -Vendor "Igor Pavlov"
    
    # VLC Media Player entries
    Write-Host "Adding VLC Media Player versions..."
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "VLC media player" `
                           -Version "3.0.20" `
                           -InstallCmd "https://get.videolan.org/vlc/3.0.20/win64/vlc-3.0.20-win64.exe /L=1033 /S" `
                           -Vendor "VideoLAN"
    
    # Notepad++ entries
    Write-Host "Adding Notepad++ versions..."
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Notepad++" `
                           -Version "8.6" `
                           -InstallCmd "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6/npp.8.6.Installer.x64.exe /S" `
                           -Vendor "Don Ho"
    
    # Visual Studio Code entries
    Write-Host "Adding Visual Studio Code versions..."
    Add-ApplicationRepoEntry -StorageAccountName $StorageAccountName `
                           -SoftwareName "Microsoft Visual Studio Code" `
                           -Version "1.85.1" `
                           -InstallCmd "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64 /VERYSILENT /NORESTART /MERGETASKS=!runcode" `
                           -Vendor "Microsoft"
    
    Write-Host "Application repository seeding completed successfully!"
    Write-Host "Added applications:"
    Write-Host "- Google Chrome (multiple versions)"
    Write-Host "- Mozilla Firefox & ESR"  
    Write-Host "- Java Runtime (multiple versions)"
    Write-Host "- Adobe Acrobat Reader DC"
    Write-Host "- 7-Zip"
    Write-Host "- VLC Media Player" 
    Write-Host "- Notepad++"
    Write-Host "- Visual Studio Code"
}
catch {
    Write-Error "Failed to seed application repository: $($_.Exception.Message)"
    throw
}