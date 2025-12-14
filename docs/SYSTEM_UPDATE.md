# RSR System Update - Comprehensive Cross-Platform Update Tool

## Overview

RSR System Update provides a unified, user-friendly interface for updating system packages across Linux, macOS, and Windows platforms. It goes beyond basic package managers to include app stores, firmware updates, and language-specific package managers.

## Features

### Cross-Platform Support

- **Linux**: apt, dnf/yum, pacman, zypper, apk + Flatpak + Snap + firmware (fwupd)
- **macOS**: Homebrew formulas + Homebrew casks + Mac App Store (mas-cli)
- **Windows**: winget + Chocolatey + Scoop + Windows Update (PSWindowsUpdate)

### Extended Update Sources

All platforms support updating:

- **Language Package Managers**: pip (Python), npm (Node.js), cargo (Rust), gem (Ruby)
- **System Packages**: Distribution-specific package managers
- **Application Stores**: Mac App Store, Windows Store (via winget)
- **Firmware** (Linux): fwupd for firmware updates

### User-Friendly Features

- ✅ **Interactive Mode**: Menu-driven interface for easy operation
- ✅ **Dry Run Mode**: Preview updates before applying
- ✅ **Security Updates**: Install security patches only
- ✅ **Selective Updates**: Choose which package sources to update
- ✅ **Exclude Packages**: Skip specific packages from updates
- ✅ **Reboot Detection**: Automatic detection of reboot requirements (Linux)
- ✅ **Progress Tracking**: Clear feedback on update status

## Quick Start

### Linux

```bash
# Interactive mode (recommended for first use)
./scripts/system/updates/system-update.sh

# Check for updates
./scripts/system/updates/system-update.sh --check

# Install all updates including Flatpak, Snap, and language packages
sudo ./scripts/system/updates/system-update.sh --all --flatpak --snap --lang -y

# Security updates only
sudo ./scripts/system/updates/system-update.sh --security -y

# Dry run to see what would be updated
./scripts/system/updates/system-update.sh --all --flatpak --dry-run
```

### macOS

```bash
# Interactive mode
./scripts/system/updates/system-update-macos.sh

# Update Homebrew packages and casks
./scripts/system/updates/system-update-macos.sh --all -y

# Include Mac App Store updates
./scripts/system/updates/system-update-macos.sh --all --mas -y

# Update language packages only
./scripts/system/updates/system-update-macos.sh --lang -y

# Update specific language manager
./scripts/system/updates/system-update-macos.sh --lang-only npm -y
```

### Windows

```powershell
# Interactive mode
.\scripts\system\updates\System-Update.ps1 -Interactive

# Check for updates
.\scripts\system\updates\System-Update.ps1 -Check -IncludeWinget -IncludeChoco

# Install all updates
.\scripts\system\updates\System-Update.ps1 -All -Force

# Include Windows Update (requires admin)
.\scripts\system\updates\System-Update.ps1 -All -IncludeWindowsUpdate -Force

# Security updates only
.\scripts\system\updates\System-Update.ps1 -All -Security -IncludeWindowsUpdate

# Update language packages
.\scripts\system\updates\System-Update.ps1 -IncludeLanguage -Force
```

## Detailed Usage

### Linux (system-update.sh)

#### Options

```
-h, --help              Show help message
-v, --verbose           Enable verbose output
-i, --interactive       Run in interactive mode (default when no args)
--no-interactive        Disable interactive mode
-c, --check             Check for available updates only
-l, --list              List available updates with details
-a, --all               Install all available updates
--security              Install security updates only
-e, --exclude PKG       Exclude package(s) from update (repeatable)
--changelog             Show changelog for updates
-y, --yes               Automatic yes to prompts
--reboot-required       Check if reboot is needed
--reboot-if-needed      Auto reboot if needed (requires --yes)
-d, --dry-run           Show what would be updated
--json                  Output in JSON format
--flatpak               Include Flatpak updates
--snap                  Include Snap updates
--firmware              Include firmware updates (fwupd)
--lang                  Include language package managers
--lang-only MANAGER     Only update specific language manager (pip,npm,cargo,gem)
```

#### Examples

```bash
# Comprehensive update (everything)
sudo ./scripts/system/updates/system-update.sh -a --flatpak --snap --firmware --lang -y

# Security patches only
sudo ./scripts/system/updates/system-update.sh --security -y

# Update Python packages only
./scripts/system/updates/system-update.sh --lang-only pip -y

# Check and list updates
./scripts/system/updates/system-update.sh -l --flatpak --snap

# Dry run with excluded packages
./scripts/system/updates/system-update.sh -a --exclude nginx --exclude postgresql -d

# Interactive mode (menu-driven)
./scripts/system/updates/system-update.sh
```

### macOS (system-update-macos.sh)

#### Options

```
-h, --help              Show help message
-v, --verbose           Enable verbose output
-i, --interactive       Run in interactive mode (default when no args)
--no-interactive        Disable interactive mode
-c, --check             Check for available updates only
-l, --list              List available updates with details
-a, --all               Install all available updates
-e, --exclude PKG       Exclude package(s) from update (repeatable)
-y, --yes               Automatic yes to prompts
-d, --dry-run           Show what would be updated
--json                  Output in JSON format
--no-brew               Skip Homebrew formula updates
--no-casks              Skip Homebrew cask updates
--mas                   Include Mac App Store updates (requires mas-cli)
--lang                  Include language package managers
--lang-only MANAGER     Only update specific language manager (pip,npm,cargo,gem)
--no-cleanup            Skip Homebrew cleanup after updates
```

#### Examples

```bash
# Update everything including App Store
./scripts/system/updates/system-update-macos.sh -a --mas -y

# Update Homebrew casks only
./scripts/system/updates/system-update-macos.sh -a --no-brew -y

# Update language packages
./scripts/system/updates/system-update-macos.sh --lang -y

# Update npm packages only
./scripts/system/updates/system-update-macos.sh --lang-only npm -y

# Check for updates
./scripts/system/updates/system-update-macos.sh -c --mas

# Dry run
./scripts/system/updates/system-update-macos.sh -a --mas -d

# Interactive mode
./scripts/system/updates/system-update-macos.sh
```

### Windows (System-Update.ps1)

#### Parameters

```
-Check                  Check for available updates only
-List                   List all available updates with details
-All                    Install all available updates from all sources
-Security               Install only security updates
-Exclude                Exclude specific packages from update
-IncludeWinget          Include winget package updates (default: true)
-IncludeChoco           Include Chocolatey package updates
-IncludeScoop           Include Scoop package updates
-IncludeWindowsUpdate   Include Windows Update
-IncludeLanguage        Include language package manager updates
-LanguageOnly           Update only specific language managers (pip, npm, cargo, gem)
-Force                  Skip confirmation prompts
-DryRun                 Show what would be updated without making changes
-Interactive            Run in interactive mode with menu selection
```

#### Examples

```powershell
# Check for all updates
.\scripts\system\updates\System-Update.ps1 -Check -IncludeWinget -IncludeChoco -IncludeWindowsUpdate

# Update all package managers
.\scripts\system\updates\System-Update.ps1 -All -IncludeWinget -IncludeChoco -Force

# Include Windows Update (requires admin)
.\scripts\system\updates\System-Update.ps1 -All -IncludeWindowsUpdate -Force

# Security updates only (Windows Update)
.\scripts\system\updates\System-Update.ps1 -All -Security -IncludeWindowsUpdate

# Update language packages
.\scripts\system\updates\System-Update.ps1 -IncludeLanguage -Force

# Update Python packages only
.\scripts\system\updates\System-Update.ps1 -LanguageOnly pip -Force

# Dry run
.\scripts\system\updates\System-Update.ps1 -All -DryRun

# Interactive mode (menu-driven)
.\scripts\system\updates\System-Update.ps1 -Interactive
```

## Requirements

### Linux

- **Required**: One of: apt, dnf/yum, pacman, zypper, or apk package manager
- **Optional**:
  - `flatpak` for Flatpak updates
  - `snap` for Snap updates
  - `fwupdmgr` for firmware updates
  - `pip3` or `pip` for Python package updates
  - `npm` for Node.js package updates
  - `cargo-update` for Rust package updates
  - `gem` for Ruby package updates

### macOS

- **Required**:
  - Homebrew (`brew`)
- **Optional**:
  - `mas-cli` for Mac App Store updates: `brew install mas`
  - `pip3` or `pip` for Python package updates
  - `npm` for Node.js package updates
  - `cargo-update` for Rust package updates
  - `gem` for Ruby package updates

### Windows

- **Required**:
  - PowerShell 5.1+
- **Optional**:
  - `winget` (Windows 10 1809+)
  - `choco` (Chocolatey)
  - `scoop`
  - `PSWindowsUpdate` module for Windows Update
  - `pip` or `pip3` for Python package updates
  - `npm` for Node.js package updates
  - `cargo-update` for Rust package updates
  - `gem` for Ruby package updates

## Installation

### RSR Library Integration

The update scripts integrate with the RSR library for enhanced functionality:

```bash
# Load RSR library in your scripts
source /path/to/rsr-lib.sh

# Use Update-RSRSystem function in PowerShell
Import-Module RSR
Update-RSRSystem -IncludeLanguage
```

### PowerShell Module Function

```powershell
# Available in RSR.Packages module
Import-Module RSR

# Update system packages
Update-RSRSystem

# Include language managers
Update-RSRSystem -IncludeLanguage

# Check only
Update-RSRSystem -CheckOnly

# Dry run
Update-RSRSystem -DryRun
```

## Best Practices

### 1. Run Updates Regularly

```bash
# Weekly update routine
./scripts/system/updates/system-update.sh -a --flatpak --snap --lang -y

# Or use cron/systemd timer (Linux)
# 0 2 * * 0 /path/to/system-update.sh -a --flatpak --snap --lang -y
```

### 2. Use Dry Run First

Always test updates with `--dry-run` or `-d` flag before applying:

```bash
./scripts/system/updates/system-update.sh -a --flatpak --dry-run
```

### 3. Backup Before Major Updates

Create system snapshots before running updates on production systems.

### 4. Review Security Updates

Check security updates separately:

```bash
./scripts/system/updates/system-update.sh --security -l
```

### 5. Exclude Critical Packages

Use `--exclude` for packages that require manual testing:

```bash
./scripts/system/updates/system-update.sh -a --exclude docker --exclude kubernetes -y
```

## Interactive Mode

All scripts support interactive mode with a menu-driven interface:

### Linux/macOS

- Run without arguments or with `-i` flag
- Menu options for viewing, installing, or customizing updates
- Guided workflow with confirmations

### Windows

- Use `-Interactive` parameter
- Numbered menu for easy selection
- Supports custom update combinations

## Exit Codes

### Common Exit Codes

- `0` - Updates completed successfully
- `1` - General error
- `2` - Invalid arguments
- `3` - Permission denied (need root/admin)
- `4` - Package manager locked
- `5` - Insufficient disk space
- `6` - Update failed
- `7` - Reboot required (after successful update)
- `100` - No updates available

## Troubleshooting

### Linux

**Package manager is locked**

```bash
# Wait for other package operations to complete
# Or manually remove lock files (caution!)
sudo rm /var/lib/dpkg/lock*  # Debian/Ubuntu
```

**Insufficient disk space**

```bash
# Check disk space
df -h

# Clean package cache
sudo apt-get clean  # Debian/Ubuntu
sudo dnf clean all  # Fedora/RHEL
```

### macOS

**Homebrew not found**

```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**mas-cli not working**

```bash
# Install or reinstall mas
brew install mas
```

### Windows

**winget not available**

```powershell
# Update Windows or install App Installer from Microsoft Store
winget --version
```

**PSWindowsUpdate module missing**

```powershell
# Install as administrator
Install-Module -Name PSWindowsUpdate -Force
Import-Module PSWindowsUpdate
```

## Advanced Usage

### Scripting and Automation

#### Linux Cron Example

```bash
# /etc/cron.d/system-update
0 3 * * 1 root /path/to/system-update.sh -a --flatpak --snap -y > /var/log/system-update.log 2>&1
```

#### Windows Task Scheduler

```powershell
# Create scheduled task
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-File "C:\path\to\System-Update.ps1" -All -Force'
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 3am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "System Update" -Description "Weekly system updates"
```

### JSON Output

For integration with monitoring systems:

```bash
./scripts/system/updates/system-update.sh -l --json
```

## Security Considerations

1. **Privileged Access**: System updates typically require root/administrator privileges
2. **Package Verification**: Updates are fetched from official repositories only
3. **Reboot Requirements**: System may require reboot after kernel/critical updates
4. **Backup**: Always maintain backups before system updates
5. **Testing**: Test updates in non-production environments first

## Contributing

Contributions welcome! Please follow these guidelines:

1. Test on target platform (Linux/macOS/Windows)
2. Follow existing code style and conventions
3. Update documentation for new features
4. Add examples for new options

## License

See main RSR project license.

## Support

For issues, questions, or contributions:

- GitHub Issues: [remote-script-runner/issues](https://github.com/codefuturist/remote-script-runner/issues)
- Documentation: See individual script help (`--help`)

---

**Last Updated**: 2025-12-11
**Version**: 1.0.0
