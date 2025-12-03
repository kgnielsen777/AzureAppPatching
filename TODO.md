# Azure App Patching - TODO List

## High Priority

### Linux Support for Arc-Enabled VMs
**Status**: Not Started  
**Priority**: Medium  
**Estimated Effort**: Large  

Currently, the Azure App Patching solution only supports Windows-based Arc-enabled VMs. Linux support would require:

#### Inventory Collection
- [ ] Update `Get-InstalledSoftwareFromDefender` to include Linux platforms
- [ ] Test Defender for Servers software inventory data quality on Linux
- [ ] Verify package manager detection (apt, yum, dnf, zypper, etc.)

#### Patching Scripts
- [ ] Create Linux-specific installation scripts in `src/scripts/`
  - [ ] `src/scripts/chrome/Install-Chrome-Linux.sh`
  - [ ] `src/scripts/firefox/Install-Firefox-Linux.sh`
  - [ ] Support for different Linux distributions (Ubuntu, RHEL, SUSE, etc.)
- [ ] Add package manager detection logic
- [ ] Handle different package formats (deb, rpm, snap, flatpak)

#### Application Repository
- [ ] Extend Table Storage schema to include OS platform
- [ ] Add Linux application entries with appropriate install commands
- [ ] Support for distribution-specific packages

#### Arc Run Commands
- [ ] Test PowerShell Core vs Bash script execution on Linux Arc VMs
- [ ] Update `Invoke-ArcRunCommand` to detect target OS and use appropriate shell
- [ ] Handle Linux-specific privileges (sudo requirements)

#### Configuration & Security
- [ ] Update Bicep templates to support mixed OS environments
- [ ] Test managed identity authentication from Linux Arc VMs
- [ ] Verify RBAC permissions work across Windows and Linux machines

#### Testing
- [ ] Set up Linux Arc VMs in test environment
- [ ] Create integration tests for Linux patching workflows
- [ ] Validate software inventory collection from Linux machines

## Medium Priority

### Enhanced Error Handling
- [ ] Add retry logic for network failures during patch downloads
- [ ] Implement rollback capability for failed patches
- [ ] Add patch verification and success confirmation

### Monitoring & Observability
- [ ] Add custom metrics for patch success/failure rates
- [ ] Implement Application Insights integration for detailed logging
- [ ] Create dashboards for patch management visibility

### Additional Applications
- [ ] Add support for Microsoft Office patching
- [ ] Implement .NET runtime updates
- [ ] Support for Visual Studio Code updates

## Low Priority

### Advanced Features
- [ ] Scheduled patching windows with maintenance mode
- [ ] Patch approval workflows before deployment
- [ ] Integration with Azure Update Management
- [ ] Support for custom application repositories

### Performance Optimizations  
- [ ] Implement parallel patch deployment
- [ ] Add caching for frequently downloaded patches
- [ ] Optimize Resource Graph query performance

---

## Notes

### Linux Challenges
1. **Package Manager Diversity**: Different Linux distributions use different package managers
2. **Privilege Escalation**: Most Linux package installations require sudo/root
3. **Distribution Differences**: Package names and versions vary between distributions
4. **Dependency Management**: Linux package managers handle dependencies differently

### Implementation Strategy for Linux
1. Start with Ubuntu/Debian support (apt package manager)
2. Add RHEL/CentOS support (yum/dnf package manager)
3. Detect distribution and package manager automatically
4. Use shell scripts instead of PowerShell for Linux operations

### Current Windows-Only Filters
- `ArcUtils.psm1`: `Get-ArcEnabledMachines -WindowsOnly $true`
- `ArcUtils.psm1`: `Get-InstalledSoftwareFromDefender` filters `OSPlatform == "Windows"`
- All patching scripts assume Windows PowerShell execution