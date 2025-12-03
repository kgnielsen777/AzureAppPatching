-- Insert initial application repository data
INSERT INTO ApplicationRepo (SoftwareName, Version, InstallCmd, Vendor, OSPlatform, Architecture)
VALUES 
    ('Google Chrome', '120.0.6099.109', 'https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe /silent /install', 'Google', 'Windows', 'x64'),
    ('Mozilla Firefox', '121.0', 'https://download.mozilla.org/?product=firefox-latest&os=win64&lang=en-US /S', 'Mozilla', 'Windows', 'x64'),
    ('Java Runtime Environment', '21.0.1', 'https://javadl.oracle.com/webapps/download/AutoDL?BundleId=249551_b8004d52b88b4c63bfcf94c97e5c1001 /s INSTALL_SILENT=1', 'Oracle', 'Windows', 'x64');