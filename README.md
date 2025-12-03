# Azure App Patching Solution

Automated patching for third-party applications on Windows VMs using Azure Arc, Azure Functions, and Microsoft Defender for Servers.

## What It Does

This solution automatically installs and updates applications on Azure Arc-enabled Windows virtual machines. It collects software inventory from Microsoft Defender for Servers and executes installation scripts via Azure Arc run commands.

## Architecture

- **Azure Functions**: PowerShell-based functions for inventory collection and patch deployment
- **Azure Arc**: Remote command execution on Windows VMs
- **Microsoft Defender for Servers**: Software inventory data source via Azure Resource Graph
- **Azure Storage**: Table storage for VM inventory and application repository
- **Azure Resource Graph**: Query engine for discovering Arc machines and software inventory

## Current Capabilities

### Supported Applications
- Google Chrome
- Mozilla Firefox  
- Java Runtime Environment
- Extensible framework for additional applications

### Deployment Options
- Single VM patching via HTTP trigger
- Batch patching with configurable concurrency
- Scheduled inventory collection (timer trigger)

### Requirements
- Windows VMs with Azure Arc Connected Machine agent
- Microsoft Defender for Servers enabled for software inventory
- PowerShell 7.4+ runtime environment

## Limitations

- Windows VMs only (Linux support planned - see TODO.md)
- Requires Arc agent connectivity for remote execution
- Limited to applications with silent installation support
- No rollback capability for failed installations

## Getting Started

See the [Deployment Guide](docs/deployment.md) for complete setup instructions, or check out the [Architecture Overview](.github/copilot-instructions.md) to understand how the solution works.

## Contributing

This solution is designed to be extensible. To add support for new applications:
1. Create application-specific PowerShell installation scripts in `src/scripts/`
2. Add application definitions to the Application Repository table
3. Update the patching function routing logic
4. Test with your target environments

See [TODO.md](TODO.md) for planned enhancements and contribution opportunities.
