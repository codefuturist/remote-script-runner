# System Update - Quick Reference Guide

## TL;DR - Just Update Everything

```bash
# Linux (Ubuntu/Debian)
sudo ./scripts/system/updates/system-update.sh --all --flatpak --snap --lang -y

# macOS
./scripts/system/updates/system-update-macos.sh --all --mas --lang -y

# Windows (PowerShell, Run as Administrator)
.\scripts\system\updates\System-Update.ps1 -All -IncludeWindowsUpdate -Force
```

## Common Use Cases

### 1. Check What Needs Updating (Safe, No Changes)
```bash
# Linux
./scripts/system/updates/system-update.sh --check

# macOS
./scripts/system/updates/system-update-macos.sh --check

# Windows
.\scripts\system\updates\System-Update.ps1 -Check
```

### 2. Interactive Mode (Guided Menus)
```bash
# Linux (will prompt for sudo when needed)
./scripts/system/updates/system-update.sh

# macOS
./scripts/system/updates/system-update-macos.sh

# Windows
.\scripts\system\updates\System-Update.ps1
```

### 3. Security Updates Only (Production Servers)
```bash
# Linux
sudo ./scripts/system/updates/system-update.sh --security -y

# macOS (system packages only, no App Store)
./scripts/system/updates/system-update-macos.sh --no-cask --no-mas -y

# Windows (requires PSWindowsUpdate module)
.\scripts\system\updates\System-Update.ps1 -IncludeWindowsUpdate -Force
```

### 4. Developer Workstation (Everything)
```bash
# Linux
sudo ./scripts/system/updates/system-update.sh \
    --all --flatpak --snap --lang --firmware -y

# macOS
./scripts/system/updates/system-update-macos.sh \
    --all --mas --lang --lang-manager pip,npm,cargo,gem -y

# Windows
.\scripts\system\updates\System-Update.ps1 `
    -All -IncludeLanguage -LanguageManager pip,npm,cargo -Force
```

### 5. Dry Run (See What Would Change)
```bash
# Linux
sudo ./scripts/system/updates/system-update.sh --all --flatpak --dry-run

# macOS
./scripts/system/updates/system-update-macos.sh --all --dry-run

# Windows
.\scripts\system\updates\System-Update.ps1 -All -DryRun
```

## What Gets Updated?

### Linux (`system-update.sh`)
| Category | What's Included | Flag |
|----------|----------------|------|
| System Packages | apt/dnf/pacman/zypper/apk | default |
| Flatpak Apps | All Flatpak applications | `--flatpak` |
| Snap Packages | All Snap packages | `--snap` |
| Firmware | Device firmware via fwupd | `--firmware` |
| Python | pip/pip3 packages | `--lang` or `--lang-only pip` |
| Node.js | Global npm packages | `--lang` or `--lang-only npm` |
| Rust | cargo packages (needs cargo-update) | `--lang` or `--lang-only cargo` |
| Ruby | RubyGems | `--lang` or `--lang-only gem` |

### macOS (`system-update-macos.sh`)
| Category | What's Included | Flag |
|----------|----------------|------|
| Homebrew Formulas | Command-line tools/libraries | default |
| Homebrew Casks | Desktop applications | default |
| Mac App Store | Apps from App Store (needs mas-cli) | `--mas` |
| macOS System | System updates (needs sudo) | `--system` |
| Language Packages | pip, npm, cargo, gem | `--lang` |

### Windows (`System-Update.ps1`)
| Category | What's Included | Flag |
|----------|----------------|------|
| winget | Windows Package Manager | default |
| Chocolatey | Chocolatey packages (needs admin) | default |
| Windows Update | KB updates (needs PSWindowsUpdate) | `-IncludeWindowsUpdate` |
| Language Packages | pip, npm, cargo, gem | `-IncludeLanguage` |

## Prerequisites by Platform

### Linux
- **Required**: Nothing! Works out of the box
- **Optional**: 
  - `flatpak` - For Flatpak updates
  - `snap` - For Snap updates
  - `fwupdmgr` - For firmware updates
  - `pip3`, `npm`, `cargo`, `gem` - For language packages

### macOS
- **Required**: [Homebrew](https://brew.sh)
- **Optional**:
  - `mas-cli` - For App Store: `brew install mas`
  - `pip3`, `npm`, `cargo`, `gem` - For language packages

### Windows
- **Required**: Windows 10 1809+ or Windows 11
- **Optional**:
  - `winget` - Usually pre-installed on Windows 11
  - [Chocolatey](https://chocolatey.org/install) - Package manager
  - `PSWindowsUpdate` module - For Windows Update: `Install-Module PSWindowsUpdate`

## One-Liner Installations

### Install mas-cli (macOS)
```bash
brew install mas
```

### Install PSWindowsUpdate (Windows)
```powershell
Install-Module PSWindowsUpdate -Force -Scope CurrentUser
```

### Install cargo-update (All platforms with Rust)
```bash
cargo install cargo-update
```

## Automation Examples

### Linux Cron Job (Daily Security Updates)
```bash
# Add to /etc/cron.d/system-update
0 2 * * * root /path/to/system-update.sh --security -y >> /var/log/system-update.log 2>&1
```

### macOS LaunchAgent (Weekly Updates)
Create `~/Library/LaunchAgents/com.rsr.update.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.rsr.update</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/system-update-macos.sh</string>
        <string>--all</string>
        <string>-y</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>0</integer>
        <key>Hour</key>
        <integer>3</integer>
    </dict>
</dict>
</plist>
```

Load with: `launchctl load ~/Library/LaunchAgents/com.rsr.update.plist`

### Windows Scheduled Task
```powershell
$action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
    -Argument '-File C:\path\to\System-Update.ps1 -All -Force'
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
Register-ScheduledTask -Action $action -Trigger $trigger `
    -TaskName "RSR System Update" -RunLevel Highest
```

## Troubleshooting

### "Package manager is locked"
```bash
# Wait for other package operations to complete, or:
sudo rm /var/lib/dpkg/lock*  # Debian/Ubuntu
```

### "Homebrew not found"
```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### "winget: command not found"
- Update Windows to latest version
- Install App Installer from Microsoft Store

### "Permission denied"
- Linux: Run with `sudo`
- Windows: Run PowerShell as Administrator
- macOS: Usually no sudo needed except for `--system`

## Tips & Tricks

1. **Always dry-run first** on production: `--dry-run` or `-DryRun`
2. **Use `--check`** to see what's available before updating
3. **Exclude critical packages**: `--exclude nginx --exclude postgresql`
4. **Check reboot requirements**: `--reboot-required` (Linux)
5. **Update language packages separately** if you want more control

## Need Help?

```bash
# Show full help
./scripts/system/updates/system-update.sh --help
./scripts/system/updates/system-update-macos.sh --help
.\scripts\system\updates\System-Update.ps1 -?

# View detailed documentation
cat scripts/system/updates/README.md
```

## Version
Script Version: 1.0.0  
Last Updated: 2025-12-11

