# Feature Request: Linux Support for Azure App Patching

## Category
Linux Support

## Problem Statement
The Azure App Patching solution currently only supports Windows VMs with Arc agents. Many organizations have hybrid environments with both Windows and Linux machines that need centralized patch management. Without Linux support, administrators must use separate tools and processes for patching Linux systems, increasing operational complexity and reducing visibility into the overall patch status across their infrastructure.

## Proposed Solution
Extend the Azure App Patching solution to support Linux Arc-enabled VMs by:

1. **Inventory Collection Enhancement**
   - Update `Get-InstalledSoftwareFromDefender` to include Linux platforms in Resource Graph queries
   - Test and validate Defender for Servers software inventory data quality on Linux systems
   - Support multiple package managers (apt, yum, dnf, zypper, pacman)

2. **Linux Installation Scripts**
   - Create Linux-specific installation scripts in `src/scripts/` directory:
     - `src/scripts/chrome/Install-Chrome-Linux.sh`
     - `src/scripts/firefox/Install-Firefox-Linux.sh` 
     - `src/scripts/java/Install-Java-Linux.sh`
   - Support different Linux distributions (Ubuntu, RHEL, SUSE, Debian, CentOS)
   - Handle different package formats (deb, rpm, snap, flatpak, AppImage)

3. **Application Repository Updates**
   - Extend Table Storage schema to include OS platform field
   - Add Linux application entries with distribution-specific install commands
   - Support for package manager detection and appropriate command generation

4. **Arc Run Command Enhancements**
   - Update `Invoke-ArcRunCommand` to detect target OS (Windows/Linux)
   - Use appropriate shell execution (PowerShell vs Bash)
   - Handle Linux privilege escalation requirements (sudo)

5. **Function Logic Updates**
   - Modify patching function to route to appropriate scripts based on OS
   - Update inventory function to process both Windows and Linux software inventory
   - Add OS-specific error handling and logging

## Alternatives Considered
- **Separate Linux-only solution**: Would duplicate infrastructure and increase maintenance overhead
- **Third-party integration**: Would introduce additional dependencies and complexity
- **Manual Linux patching**: Current approach that lacks centralization and automation

## Use Case
As a system administrator managing hybrid Windows/Linux infrastructure, I want to patch applications on both Windows and Linux Arc-enabled VMs from a single centralized solution so that I can:
- Reduce operational overhead of managing multiple patching tools
- Have unified visibility into patch status across all platforms
- Maintain consistent patching workflows and approval processes
- Ensure compliance requirements are met across all systems

## Priority
Medium - Would improve workflow

## Impact Areas
- [x] New dependencies required (bash scripting, Linux package manager knowledge)
- [x] Documentation updates needed (Linux-specific setup and troubleshooting)
- [x] Testing strategy changes (Linux test environments and validation)
- [x] Infrastructure changes required (Arc agent testing on various Linux distributions)

## Technical Considerations

### Challenges
1. **Package Manager Diversity**: Different Linux distributions use different package managers with varying syntax
2. **Privilege Escalation**: Most Linux package installations require sudo/root access
3. **Distribution Differences**: Package names and versions vary significantly between distributions
4. **Dependency Management**: Linux package managers handle dependencies differently than Windows installers

### Implementation Approach
1. **Phase 1**: Start with Ubuntu/Debian support (apt package manager)
2. **Phase 2**: Add RHEL/CentOS support (yum/dnf package manager) 
3. **Phase 3**: Expand to SUSE (zypper) and Arch (pacman)
4. **Phase 4**: Add distribution auto-detection and package manager selection

### Testing Requirements
- Linux Arc VMs across different distributions in test environment
- Validation of Defender for Servers software inventory on Linux
- Integration testing for bash script execution via Arc run commands
- Package manager compatibility testing across distributions

This feature would significantly expand the solution's applicability and provide true hybrid patch management capabilities.