# System Update Scripts

Comprehensive cross-platform system update utilities for Linux, macOS, and Windows.

## Overview

The RSR update system provides unified, user-friendly update management across all major platforms with support for:

- **System package managers** (apt, dnf, pacman, brew, winget, etc.)
- **Application stores** (Flatpak, Snap, Mac App Store, Windows Update)
- **Language package managers** (pip, npm, cargo, gem)
- **Firmware updates** (fwupd on Linux)
- **Interactive and scriptable modes**
- **Dry-run capabilities**
- **Security-only updates**

## Quick Start

### Linux

```bash
# Interactive mode
sudo ./scripts/system/updates/system-update.sh

# Check for updates
./scripts/system/updates/system-update.sh --check

# Install all updates (system + extended)
sudo ./scripts/system/updates/system-update.sh --all --flatpak --snap --lang

# Security updates only
sudo ./scripts/system/updates/system-update.sh --security -y
```

### macOS

```bash
# Interactive mode
./scripts/system/updates/system-update-macos.sh

# Check for updates
./scripts/system/updates/system-update-macos.sh --check

# Update everything (Homebrew, casks, App Store, language packages)
./scripts/system/updates/system-update-macos.sh --all --mas --lang -y

# Update only Homebrew
./scripts/system/updates/system-update-macos.sh --no-cask --no-mas -y
```

### Windows (PowerShell)

```powershell
# Interactive mode
.\scripts\system\updates\System-Update.ps1

# Check for updates
.\scripts\system\updates\System-Update.ps1 -Check

# Update everything
.\scripts\system\updates\System-Update.ps1 -All -Force

# Include Windows Update (requires admin)
.\scripts\system\updates\System-Update.ps1 -All -IncludeWindowsUpdate -Force
```

## Features by Platform

### Linux (system-update.sh)

**Core Features:**

- Automatic package manager detection (apt, dnf, yum, pacman, zypper, apk)
- System package updates
- Security-only updates
- Reboot detection and management

**Extended Features:**

- ✅ Flatpak application updates
- ✅ Snap package updates
- ✅ Firmware updates via fwupd
- ✅ Language package managers (pip, npm, cargo, gem)

**Options:**

```bash
-h, --help              Show help message
-v, --verbose           Enable verbose output
-i, --interactive       Run in interactive mode
-c, --check             Check for available updates only
-l, --list              List available updates with details
-a, --all               Install all available updates
--security              Install security updates only
-e, --exclude PKG       Exclude package(s) from update
-y, --yes               Automatic yes to prompts
--reboot-required       Check if reboot is needed
--reboot-if-needed      Auto reboot if needed
-d, --dry-run           Show what would be updated
--flatpak               Include Flatpak updates
--snap                  Include Snap updates
--firmware              Include firmware updates (fwupd)
--lang                  Include language package managers
--lang-only MANAGER     Only update specific language manager
```

### macOS (system-update-macos.sh)

**Core Features:**

- Homebrew formula updates
- Homebrew Cask (application) updates
- Mac App Store updates (requires mas-cli)
- macOS system updates (softwareupdate)

**Extended Features:**

- ✅ Language package managers (pip, npm, cargo, gem)
- ✅ Automatic cleanup after updates
- ✅ Application version tracking

**Options:**

```bash
-h, --help              Show help message
-v, --verbose           Enable verbose output
-i, --interactive       Run in interactive mode
-c, --check             Check for available updates only
-l, --list              List available updates
-a, --all               Update everything
-y, --yes               Automatic yes to prompts
-d, --dry-run           Show what would be updated
--no-brew               Skip Homebrew formulae updates
--no-cask               Skip Homebrew Cask updates
--no-mas                Skip Mac App Store updates
--system                Include macOS system updates
--lang                  Include language package managers
--lang-manager MGR      Specify language manager
```

**Requirements:**

- Homebrew: <https://brew.sh>
- mas-cli (optional): `brew install mas`

### Windows (System-Update.ps1)

**Core Features:**

- winget package updates
- Chocolatey package updates
- Scoop package updates (planned)
- Windows Update (via PSWindowsUpdate module)

**Extended Features:**

- ✅ Language package managers (pip, npm, cargo, gem)
- ✅ Reboot detection and management
- ✅ Administrator privilege detection

**Options:**

```powershell
-Check                  Check for available updates only
-List                   List all available updates
-All                    Update all sources
-DryRun                 Show what would be updated
-Force                  Skip confirmation prompts
-IncludeWindowsUpdate   Include Windows Update
-NoWinget               Skip winget updates
-NoChoco                Skip Chocolatey updates
-IncludeLanguage        Include language package managers
-LanguageManager <mgr>  Specific language manager
```

**Requirements:**

- winget (Windows 10 1809+)
- Chocolatey (optional): <https://chocolatey.org/install>
- PSWindowsUpdate module (optional): `Install-Module PSWindowsUpdate`

## Usage Examples

### Interactive Mode

All scripts support interactive mode with guided menus:

```bash
# Linux
sudo ./scripts/system/updates/system-update.sh

# macOS
./scripts/system/updates/system-update-macos.sh

# Windows
.\scripts\system\updates\System-Update.ps1
```

The interactive mode will:

1. Check for available updates across all sources
2. Display update counts by category
3. Offer menu-driven update options
4. Prompt for confirmation before applying changes
5. Support dry-run mode

### Automated Updates

#### Linux - Full System Update

```bash
# Update everything with language packages
sudo ./scripts/system/updates/system-update.sh \
    --all \
    --flatpak \
    --snap \
    --firmware \
    --lang \
    -y
```

#### Linux - Security Updates Only

```bash
# Security updates for critical systems
sudo ./scripts/system/updates/system-update.sh \
    --security \
    --reboot-if-needed \
    -y
```

#### macOS - Developer Workstation

```bash
# Update Homebrew, casks, and development tools
./scripts/system/updates/system-update-macos.sh \
    --all \
    --lang \
    --lang-manager pip,npm,cargo \
    -y
```

#### Windows - Comprehensive Update

```powershell
# Update all sources including Windows Update
.\scripts\system\updates\System-Update.ps1 `
    -All `
    -IncludeWindowsUpdate `
    -IncludeLanguage `
    -Force
```

### Dry Run Mode

Test what would be updated without making changes:

```bash
# Linux
sudo ./scripts/system/updates/system-update.sh --all --flatpak --snap --dry-run

# macOS
./scripts/system/updates/system-update-macos.sh --all --dry-run

# Windows
.\scripts\system\updates\System-Update.ps1 -All -DryRun
```

### Check Only Mode

Check for available updates without installing:

```bash
# Linux
./scripts/system/updates/system-update.sh --check

# macOS
./scripts/system/updates/system-update-macos.sh --check

# Windows
.\scripts\system\updates\System-Update.ps1 -Check
```

### Language Package Managers

Update only language-specific package managers:

```bash
# Linux - Update all detected language managers
./scripts/system/updates/system-update.sh --lang

# Linux - Update specific language managers
./scripts/system/updates/system-update.sh --lang-only pip --lang-only npm

# macOS - Update language packages
./scripts/system/updates/system-update-macos.sh --lang --lang-manager pip,npm,cargo,gem

# Windows - Update language packages
.\scripts\system\updates\System-Update.ps1 -IncludeLanguage -LanguageManager pip,npm
```

## Best Practices

### For Servers

1. **Use security-only updates** for production systems
2. **Enable automatic reboot detection** but manual reboot
3. **Exclude critical packages** if needed
4. **Run during maintenance windows**

```bash
# Server update example
sudo ./scripts/system/updates/system-update.sh \
    --security \
    --reboot-required \
    --exclude nginx \
    --exclude postgresql \
    -y
```

### For Workstations

1. **Use comprehensive updates** to stay current
2. **Include language package managers** for development
3. **Use interactive mode** for review before updates
4. **Enable dry-run** for first-time updates

```bash
# Workstation update example (macOS)
./scripts/system/updates/system-update-macos.sh \
    --all \
    --mas \
    --lang \
    -i
```

### For CI/CD

1. **Use non-interactive mode** with `-y` or `--force`
2. **Enable verbose logging** with `-v`
3. **Check exit codes** for automation
4. **Use dry-run** for testing pipeline changes

```bash
# CI/CD update example
sudo ./scripts/system/updates/system-update.sh \
    --all \
    --flatpak \
    -y \
    -v || echo "Update failed with code $?"
```

## Exit Codes

### Linux

- `0` - Updates completed successfully
- `1` - General error
- `2` - Invalid arguments
- `3` - Permission denied (need root)
- `4` - Package manager locked
- `5` - Insufficient disk space
- `6` - Update failed
- `7` - Reboot required (after successful update)
- `100` - No updates available

### macOS & Windows

- `0` - Success
- `1` - Error
- `2` - Invalid arguments
- `100` - No updates available

## Integration with RSR

These scripts integrate with the RSR library and can be called via the unified entry point:

```bash
# Via rsr wrapper (future feature)
rsr update --all --lang

# Direct execution
./scripts/system/updates/system-update.sh --all
```

## Supported Platforms

### Linux

- ✅ Debian/Ubuntu (apt)
- ✅ RHEL/CentOS/Fedora (dnf/yum)
- ✅ Arch Linux (pacman)
- ✅ openSUSE (zypper)
- ✅ Alpine (apk)

### macOS

- ✅ macOS 10.12+ (Sierra and later)
- ✅ Apple Silicon and Intel

### Windows

- ✅ Windows 10 1809+
- ✅ Windows 11
- ✅ Windows Server 2019+

## Troubleshooting

### Linux: Package Manager Locked

```bash
# Check for running package managers
ps aux | grep -E 'apt|dnf|yum|pacman'

# Remove stale lock files (if safe)
sudo rm /var/lib/dpkg/lock*  # Debian/Ubuntu
```

### macOS: Homebrew Issues

```bash
# Update Homebrew itself
brew update

# Fix permissions
sudo chown -R $(whoami) $(brew --prefix)/*

# Reinstall mas-cli if needed
brew reinstall mas
```

### Windows: Module Not Found

```powershell
# Install PSWindowsUpdate
Install-Module PSWindowsUpdate -Force -Scope CurrentUser

# Check winget availability
winget --version

# Install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
```

## Advanced Configuration

### Environment Variables

```bash
# Linux
export RSR_UPDATE_AUTO_YES=1        # Skip confirmations
export RSR_UPDATE_INCLUDE_LANG=1    # Always include language packages
export RSR_UPDATE_DRY_RUN=1         # Always run in dry-run mode

# macOS
export HOMEBREW_NO_AUTO_UPDATE=1    # Disable auto-update during brew commands
```

### Automation with Cron (Linux/macOS)

```bash
# Daily security updates at 2 AM
0 2 * * * /path/to/system-update.sh --security -y >> /var/log/system-update.log 2>&1

# Weekly full update on Sundays at 3 AM
0 3 * * 0 /path/to/system-update.sh --all --flatpak --snap --lang -y >> /var/log/system-update.log 2>&1
```

### Task Scheduler (Windows)

Create a scheduled task to run updates automatically:

```powershell
# Create scheduled task for weekly updates
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-File C:\path\to\System-Update.ps1 -All -Force'
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "SystemUpdate" -Description "Weekly system updates"
```

## Auto-Update Manager

The RSR update system includes a comprehensive auto-update manager that installs, configures, and manages automated system updates across all platforms.

### Features

- **Interactive setup wizard**: User-friendly guided configuration
- **Cross-platform support**: Linux (systemd/cron), macOS (launchd), Windows (Task Scheduler)
- **Native tool integration**: Uses `unattended-upgrades` on Debian/Ubuntu, `dnf-automatic` on RHEL/Fedora
- **Flexible scheduling**: Daily, weekly, or monthly updates
- **Security-focused**: Security-only update option
- **Reboot management**: Configure automatic reboot behavior
- **Notifications**: Email alerts on update failures

### Quick Start

The easiest way to get started is to run the script without arguments for **interactive mode**:

```bash
# Interactive setup wizard (recommended)
sudo ./scripts/system/updates/auto-update-manager.sh

# Or explicitly with -i flag
sudo ./scripts/system/updates/auto-update-manager.sh -i install
```

```powershell
# Windows - Interactive setup wizard
.\scripts\system\updates\Auto-Update-Manager.ps1

# Or explicitly with -Interactive flag
.\scripts\system\updates\Auto-Update-Manager.ps1 -Interactive install
```

The interactive wizard will guide you through:
1. Choosing update schedule (daily/weekly/monthly)
2. Setting the update time
3. Selecting security-only or full updates
4. Configuring language package managers
5. Setting reboot behavior
6. Enabling notifications

#### Command-line Mode

For scripting or automation, use command-line arguments:

```bash
# Linux - Install daily automatic updates
sudo ./scripts/system/updates/auto-update-manager.sh install

# Linux - Install weekly security-only updates
sudo ./scripts/system/updates/auto-update-manager.sh install \
    --schedule weekly --time 03:00 --day sun --security-only

# macOS - Install for current user
./scripts/system/updates/auto-update-manager.sh install --user

# Check status
./scripts/system/updates/auto-update-manager.sh status

# View logs
./scripts/system/updates/auto-update-manager.sh logs
```

```powershell
# Windows - Install daily automatic updates
.\scripts\system\updates\Auto-Update-Manager.ps1 install

# Windows - Install weekly updates
.\scripts\system\updates\Auto-Update-Manager.ps1 install -Schedule weekly -DayOfWeek Sunday -Time "03:00"

# Check status
.\scripts\system\updates\Auto-Update-Manager.ps1 status
```

### Commands

| Command | Description |
|---------|-------------|
| `install` | Install and configure automatic updates |
| `remove` | Remove automatic update configuration |
| `status` | Show current configuration and status |
| `enable` | Enable scheduled updates |
| `disable` | Disable updates (keep configuration) |
| `run-now` | Trigger an immediate update |
| `logs` | Show update history and logs |
| `config` | Show current configuration |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-i, --interactive` | Run in interactive mode with guided setup | auto |
| `--schedule` | Update frequency: daily, weekly, monthly | daily |
| `--time` | Time to run (HH:MM) | 02:00 |
| `--day` | Day for weekly (0-6 or sun-sat) | 0 (Sunday) |
| `--security-only` | Only install security updates | false |
| `--reboot` | Reboot mode: never, if-needed, always | never |
| `--include-lang` | Include pip, npm, cargo, gem | false |
| `--use-native` | Use unattended-upgrades/dnf-automatic | false |
| `--notify` | Notification method: email, none | none |
| `--email` | Email for notifications | - |
| `--user` | User-level install (no root) | false |

### Platform-Specific Behavior

#### Debian/Ubuntu

With `--use-native`:
- Installs and configures `unattended-upgrades`
- Modifies `/etc/apt/apt.conf.d/50unattended-upgrades`
- Enables `apt-daily-upgrade.timer`

Without `--use-native`:
- Creates systemd timer with RSR's `system-update.sh`
- More control over what gets updated

#### RHEL/Fedora/CentOS

With `--use-native`:
- Installs and configures `dnf-automatic`
- Modifies `/etc/dnf/automatic.conf`
- Enables `dnf-automatic.timer`

#### Arch Linux / openSUSE / Alpine

- Uses systemd timer (or cron on Alpine) with RSR's update script
- Full control over update behavior

#### macOS

- Creates launchd plist
- Uses RSR's `system-update-macos.sh`
- Supports user-level installation

#### Windows

- Creates Windows Task Scheduler task
- Uses RSR's `System-Update.ps1`
- Supports user-level installation

### Configuration Files

| Platform | System Config | User Config |
|----------|--------------|-------------|
| Linux | `/etc/rsr/auto-update.conf` | `~/.config/rsr/auto-update.conf` |
| macOS | `/Library/LaunchDaemons/com.rsr.auto-update.plist` | `~/Library/LaunchAgents/com.rsr.auto-update.plist` |
| Windows | `%PROGRAMDATA%\rsr\auto-update.json` | `%APPDATA%\rsr\auto-update.json` |

### Log Files

| Platform | Location |
|----------|----------|
| Linux | `/var/log/rsr/auto-update.log` |
| macOS | `/var/log/rsr/auto-update.log` or `~/.local/state/rsr/logs/auto-update.log` |
| Windows | `%PROGRAMDATA%\rsr\logs\auto-update.log` |

### Examples

#### Server: Security Updates Only

```bash
# Daily security updates at 2am, email on failure
sudo ./auto-update-manager.sh install \
    --schedule daily \
    --time 02:00 \
    --security-only \
    --reboot if-needed \
    --email admin@example.com \
    --use-native
```

#### Workstation: Weekly Full Updates

```bash
# Weekly updates on Sunday at 3am including dev tools
sudo ./auto-update-manager.sh install \
    --schedule weekly \
    --time 03:00 \
    --day sun \
    --include-lang
```

#### macOS: User-Level Updates

```bash
# Daily Homebrew updates for current user
./auto-update-manager.sh install \
    --user \
    --schedule daily \
    --time 09:00
```

#### Windows: Comprehensive Updates

```powershell
# Weekly updates including Windows Update
.\Auto-Update-Manager.ps1 install `
    -Schedule weekly `
    -DayOfWeek Sunday `
    -Time "03:00" `
    -UseWindowsUpdate `
    -IncludeLanguage
```

## Contributing

To extend the update scripts:

1. Follow the existing code structure
2. Add new package managers to the detection logic
3. Implement check, list, and update functions
4. Add comprehensive error handling
5. Update documentation
6. Test across supported platforms

## License

Part of the Remote Script Runner (RSR) project.

## Support

For issues, questions, or contributions:

- GitHub Issues: [remote-script-runner/issues](https://github.com/codefuturist/remote-script-runner/issues)
- Documentation: [RSR Docs](https://scripts.pandia.io/docs)
