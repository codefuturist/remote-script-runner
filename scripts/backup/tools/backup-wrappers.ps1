<#
.SYNOPSIS
    Manage config-driven backup wrappers (resticprofile, kopia) on Windows

.DESCRIPTION
    Unified management for config-driven backup solutions on Windows:
    - resticprofile (cross-platform, enterprise-grade)
    - kopia (native config with GUI)
    - autorestic (via WSL or native binary)

.PARAMETER Command
    Action: status, install, init, run, check, list, restore, schedule, config, docs

.PARAMETER Wrapper
    Wrapper name: resticprofile, kopia, autorestic

.PARAMETER WithUI
    Install GUI/UI package where available (kopia-ui, vorta for borg, etc.)

.EXAMPLE
    .\backup-wrappers.ps1 status

.EXAMPLE
    .\backup-wrappers.ps1 install resticprofile

.EXAMPLE
    .\backup-wrappers.ps1 install kopia -WithUI

.EXAMPLE
    .\backup-wrappers.ps1 run resticprofile -Profile home

.NOTES
    Version: 1.0.0
    Author:  RSR Team
    License: MIT
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'install', 'init', 'run', 'check', 'list', 'restore', 'schedule', 'config', 'docs')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [ValidateSet('resticprofile', 'kopia', 'autorestic', 'rustic', '')]
    [string]$Wrapper = '',

    [Parameter()]
    [Alias('p')]
    [string]$Profile = '',

    [Parameter()]
    [Alias('l')]
    [string]$Location = '',

    [Parameter()]
    [Alias('a')]
    [switch]$All,

    [Parameter()]
    [Alias('d')]
    [switch]$DryRun,

    [Parameter()]
    [Alias('v')]
    [switch]$VerboseOutput,

    [Parameter()]
    [Alias('q')]
    [switch]$Quiet,

    [Parameter()]
    [Alias('ui', 'gui')]
    [switch]$WithUI,

    [Parameter()]
    [switch]$Help
)

# =============================================================================
# Configuration
# =============================================================================

$Script:Name = 'Backup Wrappers'
$Script:Version = '1.0.0'

# Supported wrappers with UI information
$Script:Wrappers = @{
    'resticprofile' = @{
        Backend = 'restic'
        Description = 'Enterprise restic profiles (YAML)'
        Url = 'https://creativeprojects.github.io/resticprofile/'
        HasUI = $false
        UIPackage = $null
        UIDescription = $null
    }
    'kopia' = @{
        Backend = 'kopia'
        Description = 'Kopia with built-in config'
        Url = 'https://kopia.io'
        HasUI = $true
        UIPackage = 'KopiaUI'
        UIDescription = 'Kopia UI - Full-featured backup GUI with scheduling'
        UIWinget = 'KopiaUI.KopiaUI'
        UIChoco = 'kopia-ui'
        UIScoop = 'extras/kopia-ui'
    }
    'autorestic' = @{
        Backend = 'restic'
        Description = 'Config-driven restic wrapper (YAML)'
        Url = 'https://autorestic.vercel.app'
        HasUI = $true
        UIPackage = 'restic-browser'
        UIDescription = 'Restic Browser - GUI for browsing restic repositories'
        UIWinget = $null
        UIChoco = $null
        UIScoop = $null
        UIManual = 'https://github.com/emuell/restic-browser/releases'
    }
    'rustic' = @{
        Backend = 'rustic'
        Description = 'Rust restic alternative (TOML)'
        Url = 'https://rustic.cli.rs'
        HasUI = $false
        UIPackage = $null
        UIDescription = $null
    }
}

# Config paths
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
$Script:ConfigPaths = @{
    'resticprofile' = Join-Path $homeDir '.config\resticprofile\profiles.yaml'
    'kopia' = Join-Path $homeDir '.config\kopia\repository.config'
    'autorestic' = Join-Path $homeDir '.autorestic.yml'
    'rustic' = Join-Path $homeDir '.config\rustic\rustic.toml'
}

$Script:TemplateDir = Join-Path $PSScriptRoot '..\..\..\config\backup\templates'

# =============================================================================
# Logging
# =============================================================================

function Write-Info { param([string]$Message) if (-not $Quiet) { Write-Host "▸ $Message" -ForegroundColor Cyan } }
function Write-Ok { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }

function Write-Header {
    param([string]$Title)
    if (-not $Quiet) {
        Write-Host ""
        Write-Host "═══ $Title ═══" -ForegroundColor Cyan
        Write-Host ""
    }
}

# =============================================================================
# Help
# =============================================================================

function Show-Help {
    @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    RSR Backup Wrappers Management (Windows)                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

Manage config-driven backup solutions with YAML/TOML configuration files.

USAGE:
    .\backup-wrappers.ps1                       # Launch interactive mode (default)
    .\backup-wrappers.ps1 [COMMAND] [WRAPPER] [OPTIONS]

COMMANDS:
    (no command)        Launch interactive menu (default when no args)
    status              Show installed wrappers and their status
    install WRAPPER     Install a backup wrapper
    init WRAPPER        Generate config template for wrapper
    run WRAPPER         Run backup using wrapper
    check WRAPPER       Verify/check backup integrity
    list WRAPPER        List backups/snapshots
    restore WRAPPER     Restore from backup
    schedule WRAPPER    Set up scheduled backups
    config WRAPPER      Edit wrapper configuration
    docs WRAPPER        Show wrapper documentation

SUPPORTED WRAPPERS:
    resticprofile       Enterprise restic profiles (YAML) - recommended for Windows
    kopia               Kopia with built-in config and GUI
    autorestic          Config-driven restic wrapper (YAML)
    rustic              Rust restic alternative (TOML)

OPTIONS:
    -Help               Show this help message
    -VerboseOutput      Enable verbose output
    -Quiet              Suppress non-essential output
    -DryRun             Show what would be done
    -Profile NAME       Specify profile name
    -All                Run for all profiles
    -WithUI             Install GUI/UI package where available

EXAMPLES:
    # Check what's installed
    .\backup-wrappers.ps1 status

    # Install resticprofile (recommended for Windows)
    .\backup-wrappers.ps1 install resticprofile

    # Install kopia with GUI
    .\backup-wrappers.ps1 install kopia -WithUI

    # Generate config template
    .\backup-wrappers.ps1 init resticprofile

    # Run backup
    .\backup-wrappers.ps1 run resticprofile
    .\backup-wrappers.ps1 run resticprofile -Profile home

    # Set up scheduling
    .\backup-wrappers.ps1 schedule resticprofile

CONFIG FILE LOCATIONS:
    resticprofile:  ~\.config\resticprofile\profiles.yaml
    kopia:          ~\.config\kopia\repository.config
    autorestic:     ~\.autorestic.yml
    rustic:         ~\.config\rustic\rustic.toml

"@
}

# =============================================================================
# Detection Functions
# =============================================================================

function Test-WrapperInstalled {
    param([string]$WrapperName)
    return (Get-Command $WrapperName -ErrorAction SilentlyContinue) -ne $null
}

function Test-BackendInstalled {
    param([string]$WrapperName)
    $backend = $Script:Wrappers[$WrapperName].Backend
    return (Get-Command $backend -ErrorAction SilentlyContinue) -ne $null
}

function Test-ConfigExists {
    param([string]$WrapperName)
    $configPath = $Script:ConfigPaths[$WrapperName]
    return Test-Path $configPath
}

function Get-WrapperVersion {
    param([string]$WrapperName)

    try {
        switch ($WrapperName) {
            'resticprofile' {
                $output = resticprofile version 2>&1
                if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
            }
            'kopia' {
                $output = kopia --version 2>&1
                if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
            }
            'autorestic' {
                $output = autorestic --version 2>&1
                if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
            }
            'rustic' {
                $output = rustic --version 2>&1
                if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
            }
        }
    } catch { }

    return 'unknown'
}

# =============================================================================
# Command: status
# =============================================================================

function Show-Status {
    Write-Header "Backup Wrappers Status"

    Write-Host ("{0,-15} {1,-12} {2,-10} {3,-8} {4}" -f "WRAPPER", "VERSION", "BACKEND", "CONFIG", "DESCRIPTION")
    Write-Host ("{0,-15} {1,-12} {2,-10} {3,-8} {4}" -f "───────", "───────", "───────", "──────", "───────────")

    foreach ($name in $Script:Wrappers.Keys | Sort-Object) {
        $info = $Script:Wrappers[$name]

        $version = if (Test-WrapperInstalled $name) { Get-WrapperVersion $name } else { "-" }
        $backendStatus = if (Test-BackendInstalled $name) { "✓" } else { "✗" }
        $configStatus = if (Test-ConfigExists $name) { "✓" } else { "✗" }

        $nameColor = if (Test-WrapperInstalled $name) { "Green" } else { "Yellow" }
        $versionDisplay = if ($version -eq "-") { "(not installed)" } else { $version }

        Write-Host ("{0,-15} " -f $name) -NoNewline -ForegroundColor $nameColor
        Write-Host ("{0,-12} " -f $versionDisplay) -NoNewline

        $backendColor = if ($backendStatus -eq "✓") { "Green" } else { "Red" }
        Write-Host "$backendStatus " -NoNewline -ForegroundColor $backendColor
        Write-Host ("{0,-7} " -f $info.Backend) -NoNewline

        $configColor = if ($configStatus -eq "✓") { "Green" } else { "Red" }
        Write-Host "$configStatus " -NoNewline -ForegroundColor $configColor
        Write-Host ("     {0}" -f $info.Description)
    }

    Write-Host ""

    # Recommendations
    $installed = $Script:Wrappers.Keys | Where-Object { Test-WrapperInstalled $_ }
    if (-not $installed) {
        Write-Warn "No config-driven backup wrappers installed"
        Write-Host ""
        Write-Host "Install one with:"
        Write-Host "  .\backup-wrappers.ps1 install resticprofile    # Recommended for Windows"
        Write-Host "  .\backup-wrappers.ps1 install kopia            # Has GUI"
    }
}

# =============================================================================
# Command: install
# =============================================================================

function Install-Wrapper {
    if (-not $Wrapper) {
        Write-Err "Wrapper name required"
        Write-Host "Available: $($Script:Wrappers.Keys -join ', ')"
        return
    }

    if (-not $Script:Wrappers.ContainsKey($Wrapper)) {
        Write-Err "Unknown wrapper: $Wrapper"
        return
    }

    Write-Header "Installing $Wrapper"

    if (Test-WrapperInstalled $Wrapper) {
        $version = Get-WrapperVersion $Wrapper
        Write-Warn "$Wrapper is already installed (version: $version)"
        return
    }

    # Check for package managers
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    $hasChoco = Get-Command choco -ErrorAction SilentlyContinue
    $hasScoop = Get-Command scoop -ErrorAction SilentlyContinue

    if ($DryRun) {
        Write-Warn "Dry run - would install $Wrapper"
        return
    }

    Write-Info "Installing $Wrapper..."

    # Install backend first if needed
    $backend = $Script:Wrappers[$Wrapper].Backend
    if (-not (Test-BackendInstalled $Wrapper) -and $backend -ne $Wrapper) {
        Write-Info "Installing $backend (required backend)..."

        if ($hasWinget) {
            & winget install "$backend.$backend" --silent
        } elseif ($hasChoco) {
            & choco install $backend -y
        } elseif ($hasScoop) {
            & scoop install $backend
        }
    }

    # Install wrapper
    switch ($Wrapper) {
        'resticprofile' {
            if ($hasScoop) {
                & scoop install resticprofile
            } elseif ($hasChoco) {
                & choco install resticprofile -y
            } else {
                Write-Info "Downloading from GitHub..."
                $url = "https://github.com/creativeprojects/resticprofile/releases/latest/download/resticprofile_windows_amd64.zip"
                $dest = Join-Path $env:TEMP "resticprofile.zip"
                Invoke-WebRequest -Uri $url -OutFile $dest
                Expand-Archive -Path $dest -DestinationPath "$env:LOCALAPPDATA\Microsoft\WindowsApps" -Force
                Remove-Item $dest
            }
        }
        'kopia' {
            if ($hasWinget) {
                & winget install KopiaUI.KopiaUI --silent
            } elseif ($hasChoco) {
                & choco install kopia -y
            } elseif ($hasScoop) {
                & scoop install kopia
            } else {
                Write-Warn "Install manually from: https://kopia.io/docs/installation/"
            }
        }
        'autorestic' {
            if ($hasScoop) {
                & scoop install autorestic
            } elseif ($hasChoco) {
                & choco install autorestic -y
            } else {
                $url = "https://github.com/cupcakearmy/autorestic/releases/latest/download/autorestic_windows_amd64.exe"
                $dest = "$env:LOCALAPPDATA\Microsoft\WindowsApps\autorestic.exe"
                Invoke-WebRequest -Uri $url -OutFile $dest
            }
        }
        'rustic' {
            if ($hasScoop) {
                & scoop install rustic
            } else {
                Write-Warn "Install via cargo: cargo install rustic-rs"
            }
        }
    }

    # Install UI package if requested and available
    if ($WithUI -and $Script:Wrappers[$Wrapper].HasUI) {
        $uiPackage = $Script:Wrappers[$Wrapper].UIPackage
        Write-Info "Installing UI package: $uiPackage..."

        if ($hasWinget -and $Script:Wrappers[$Wrapper].UIWinget) {
            & winget install $uiPackage --silent
        } elseif ($hasChoco -and $Script:Wrappers[$Wrapper].UIChoco) {
            & choco install $uiPackage -y
        } elseif ($hasScoop -and $Script:Wrappers[$Wrapper].UIScoop) {
            & scoop install $uiPackage
        } elseif ($Script:Wrappers[$Wrapper].UIManual) {
            Write-Host "Manual installation required: $($Script:Wrappers[$Wrapper].UIManual)"
        }
    }

    if (Test-WrapperInstalled $Wrapper) {
        Write-Ok "$Wrapper installed successfully"
        Write-Host ""
        Write-Host "Next steps:"
        Write-Host "  .\backup-wrappers.ps1 init $Wrapper    # Generate config template"
        Write-Host "  .\backup-wrappers.ps1 run $Wrapper     # Run backup"
    } else {
        Write-Err "Failed to install $Wrapper"
    }
}

# =============================================================================
# Command: init
# =============================================================================

function Initialize-Config {
    if (-not $Wrapper) {
        Write-Err "Wrapper name required"
        return
    }

    $configPath = $Script:ConfigPaths[$Wrapper]
    $templateFile = Join-Path $Script:TemplateDir "$Wrapper.yaml"

    Write-Header "Initializing $Wrapper Configuration"

    Write-Info "Config path: $configPath"

    if (Test-Path $configPath) {
        Write-Warn "Config already exists: $configPath"
        $confirm = Read-Host "Overwrite? (y/N)"
        if ($confirm -notmatch '^[Yy]') {
            Write-Info "Cancelled"
            return
        }
    }

    if ($DryRun) {
        Write-Warn "Dry run - would create $configPath"
        return
    }

    # Create directory
    $configDir = Split-Path $configPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    # Copy template or generate basic config
    if (Test-Path $templateFile) {
        Copy-Item $templateFile $configPath
        Write-Ok "Created config from template: $configPath"
    } else {
        # Generate basic config
        switch ($Wrapper) {
            'resticprofile' {
                $config = @"
version: "1"

default:
  repository: D:\Backup\restic-repo
  password-file: $configDir\.password

  retention:
    keep-daily: 7
    keep-weekly: 4
    keep-monthly: 6

  backup:
    source:
      - $env:USERPROFILE\Documents
      - $env:USERPROFILE\Desktop
    exclude:
      - "*.tmp"
      - "Thumbs.db"
      - node_modules
      - .venv
"@
                Set-Content -Path $configPath -Value $config

                # Generate password file
                $pwFile = Join-Path $configDir ".password"
                if (-not (Test-Path $pwFile)) {
                    [System.Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)) |
                        Set-Content -Path $pwFile
                    Write-Ok "Generated password file: $pwFile"
                }
            }
            'kopia' {
                Write-Info "Kopia uses interactive setup:"
                Write-Host "  kopia repository create filesystem --path D:\Backup\kopia"
            }
            'autorestic' {
                $config = @"
version: 2

backends:
  local:
    type: local
    path: D:\Backup\restic-repo
    key: `${RESTIC_PASSWORD}

locations:
  home:
    from: $env:USERPROFILE
    to:
      - local
    options:
      backup:
        exclude:
          - node_modules
          - .venv
          - "*.tmp"
"@
                Set-Content -Path $configPath -Value $config
            }
        }
        Write-Ok "Created config: $configPath"
    }

    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Edit the config: $configPath"
    Write-Host "  2. Initialize repository"
    Write-Host "  3. Run first backup: .\backup-wrappers.ps1 run $Wrapper"
}

# =============================================================================
# Command: run
# =============================================================================

function Start-WrapperBackup {
    if (-not $Wrapper) {
        # Auto-detect
        foreach ($w in @('resticprofile', 'kopia', 'autorestic')) {
            if ((Test-WrapperInstalled $w) -and (Test-ConfigExists $w)) {
                $script:Wrapper = $w
                Write-Info "Auto-detected: $Wrapper"
                break
            }
        }
    }

    if (-not $Wrapper) {
        Write-Err "No wrapper specified and none auto-detected"
        return
    }

    if (-not (Test-WrapperInstalled $Wrapper)) {
        Write-Err "$Wrapper is not installed"
        return
    }

    Write-Header "Running Backup with $Wrapper"

    if ($DryRun) {
        Write-Warn "Dry run mode"
    }

    switch ($Wrapper) {
        'resticprofile' {
            $args = @()
            if ($Profile) { $args += @('-n', $Profile) }
            if ($DryRun) { $args += '--dry-run' }
            if ($VerboseOutput) { $args += '-v' }
            $args += 'backup'

            & resticprofile @args
        }
        'kopia' {
            $sources = @("$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop")

            if ($DryRun) {
                Write-Info "Would run: kopia snapshot create $($sources -join ' ')"
            } else {
                & kopia snapshot create @sources
            }
        }
        'autorestic' {
            $args = @('backup')
            if ($Profile) { $args += @('-l', $Profile) }
            elseif ($Location) { $args += @('-l', $Location) }
            else { $args += '-a' }

            & autorestic @args
        }
        'rustic' {
            $args = @('backup')
            if ($DryRun) { $args += '--dry-run' }

            & rustic @args
        }
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Backup completed successfully"
    } else {
        Write-Err "Backup failed"
    }
}

# =============================================================================
# Command: check
# =============================================================================

function Test-Backup {
    if (-not $Wrapper) {
        Write-Err "Wrapper name required"
        return
    }

    Write-Header "Checking Backup Integrity ($Wrapper)"

    switch ($Wrapper) {
        'resticprofile' {
            $args = @()
            if ($Profile) { $args += @('-n', $Profile) }
            $args += 'check'
            & resticprofile @args
        }
        'kopia' { & kopia snapshot verify }
        'autorestic' { & autorestic check }
        'rustic' { & rustic check }
    }
}

# =============================================================================
# Command: list
# =============================================================================

function Show-Backups {
    if (-not $Wrapper) {
        Write-Err "Wrapper name required"
        return
    }

    Write-Header "Listing Backups ($Wrapper)"

    switch ($Wrapper) {
        'resticprofile' {
            $args = @()
            if ($Profile) { $args += @('-n', $Profile) }
            $args += 'snapshots'
            & resticprofile @args
        }
        'kopia' { & kopia snapshot list }
        'autorestic' { & autorestic exec -a -- snapshots }
        'rustic' { & rustic snapshots }
    }
}

# =============================================================================
# Command: schedule
# =============================================================================

function Set-Schedule {
    if (-not $Wrapper) {
        Write-Err "Wrapper name required"
        return
    }

    Write-Header "Setting up Schedule ($Wrapper)"

    switch ($Wrapper) {
        'resticprofile' {
            Write-Info "Installing resticprofile schedules (Windows Task Scheduler)..."
            if ($DryRun) {
                & resticprofile schedule --all --dry-run
            } else {
                & resticprofile schedule --all
            }
        }
        'kopia' {
            Write-Info "Kopia uses server mode for scheduling"
            Write-Host ""
            Write-Host "Option 1 - Kopia Server with Web UI:"
            Write-Host "  kopia server start --insecure --address 0.0.0.0:51515"
            Write-Host ""
            Write-Host "Option 2 - Windows Task Scheduler:"
            Write-Host "  Create a task to run: kopia snapshot create $env:USERPROFILE"
        }
        'autorestic' {
            Write-Info "Autorestic uses cron definitions - use Windows Task Scheduler"
            Write-Host ""
            Write-Host "Create a scheduled task to run:"
            Write-Host "  autorestic backup -a"
        }
    }
}

# =============================================================================
# Command: config
# =============================================================================

function Edit-Config {
    if (-not $Wrapper) {
        Write-Err "Wrapper name required"
        return
    }

    $configPath = $Script:ConfigPaths[$Wrapper]

    if (-not (Test-Path $configPath)) {
        Write-Warn "Config not found: $configPath"
        $confirm = Read-Host "Create it? (Y/n)"
        if ($confirm -notmatch '^[Nn]') {
            Initialize-Config
        }
        return
    }

    Write-Info "Opening: $configPath"

    # Try to open with default editor
    if ($env:EDITOR) {
        & $env:EDITOR $configPath
    } else {
        Start-Process notepad $configPath
    }
}

# =============================================================================
# Command: docs
# =============================================================================

function Show-Docs {
    if (-not $Wrapper) {
        Write-Err "Wrapper name required"
        return
    }

    $url = $Script:Wrappers[$Wrapper].Url

    Write-Info "Opening: $url"
    Start-Process $url
}

# =============================================================================
# Interactive Mode
# =============================================================================

function Select-Wrapper {
    param([string]$Prompt = "Select a wrapper")

    Write-Host ""
    Write-Host "  Available wrappers:" -ForegroundColor Yellow
    Write-Host ""

    $wrapperList = @($Script:Wrappers.Keys | Sort-Object)
    $i = 1
    foreach ($name in $wrapperList) {
        $info = $Script:Wrappers[$name]
        $installed = if (Test-WrapperInstalled $name) { "[installed]" } else { "" }
        $installedColor = if ($installed) { "Green" } else { "Gray" }

        Write-Host ("    [{0}] {1,-15} {2} " -f $i, $name, $info.Description) -NoNewline
        Write-Host $installed -ForegroundColor $installedColor
        $i++
    }

    Write-Host ""
    $selection = Read-Host "  $Prompt (1-$($wrapperList.Count))"

    if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $wrapperList.Count) {
        return $wrapperList[[int]$selection - 1]
    }

    return $null
}

function Show-InteractiveMenu {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║           RSR Backup Wrappers - Interactive Mode             ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Manage config-driven backup solutions" -ForegroundColor White
        Write-Host ""
        Write-Host "  [1] Show status           - View installed wrappers"
        Write-Host "  [2] Install wrapper       - Install autorestic, borgmatic, etc."
        Write-Host "  [3] Generate config       - Create config template"
        Write-Host "  [4] Run backup            - Execute backup"
        Write-Host "  [5] Check backup          - Verify backup integrity"
        Write-Host "  [6] List snapshots        - Show available backups"
        Write-Host "  [7] Setup schedule        - Configure automated backups"
        Write-Host "  [8] Edit config           - Open configuration file"
        Write-Host "  [9] Documentation         - Open wrapper docs"
        Write-Host ""
        Write-Host "  [q] Quit"
        Write-Host ""

        $choice = Read-Host "  Select an option"

        switch ($choice) {
            '1' {
                Show-Status
                Read-Host "`n  Press Enter to continue"
            }
            '2' {
                Write-Header "Install Backup Wrapper"
                $script:Wrapper = Select-Wrapper "Select wrapper to install"
                if ($Wrapper) {
                    $uiChoice = Read-Host "`n  Install with GUI/UI package? (y/N)"
                    if ($uiChoice -match '^[Yy]') { $script:WithUI = $true }
                    Install-Wrapper
                    $script:WithUI = $false
                }
                Read-Host "`n  Press Enter to continue"
            }
            '3' {
                Write-Header "Generate Configuration"
                $script:Wrapper = Select-Wrapper "Select wrapper to configure"
                if ($Wrapper) {
                    Initialize-Config
                }
                Read-Host "`n  Press Enter to continue"
            }
            '4' {
                Write-Header "Run Backup"
                # Find configured wrappers
                $available = @()
                foreach ($name in $Script:Wrappers.Keys) {
                    if ((Test-WrapperInstalled $name) -and (Test-ConfigExists $name)) {
                        $available += $name
                    }
                }

                if ($available.Count -eq 0) {
                    Write-Warn "No configured wrappers found"
                    Write-Host "`n  Install and configure a wrapper first."
                } else {
                    Write-Host "`n  Configured wrappers:" -ForegroundColor Yellow
                    $i = 1
                    foreach ($name in $available) {
                        Write-Host "    [$i] $name"
                        $i++
                    }
                    $sel = Read-Host "`n  Select wrapper (1-$($available.Count))"
                    if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $available.Count) {
                        $script:Wrapper = $available[[int]$sel - 1]
                        $script:Profile = Read-Host "  Profile name (or Enter for all)"
                        $dryChoice = Read-Host "  Dry run first? (y/N)"
                        if ($dryChoice -match '^[Yy]') { $script:DryRun = $true }
                        Start-WrapperBackup
                        $script:DryRun = $false
                    }
                }
                Read-Host "`n  Press Enter to continue"
            }
            '5' {
                Write-Header "Check Backup Integrity"
                $script:Wrapper = Select-Wrapper "Select wrapper to check"
                if ($Wrapper) {
                    Test-Backup
                }
                Read-Host "`n  Press Enter to continue"
            }
            '6' {
                Write-Header "List Snapshots"
                $script:Wrapper = Select-Wrapper "Select wrapper"
                if ($Wrapper) {
                    Show-Backups
                }
                Read-Host "`n  Press Enter to continue"
            }
            '7' {
                Write-Header "Setup Backup Schedule"
                $script:Wrapper = Select-Wrapper "Select wrapper"
                if ($Wrapper) {
                    Set-Schedule
                }
                Read-Host "`n  Press Enter to continue"
            }
            '8' {
                Write-Header "Edit Configuration"
                $script:Wrapper = Select-Wrapper "Select wrapper"
                if ($Wrapper) {
                    Edit-Config
                }
                Read-Host "`n  Press Enter to continue"
            }
            '9' {
                Write-Header "Open Documentation"
                $script:Wrapper = Select-Wrapper "Select wrapper"
                if ($Wrapper) {
                    Show-Docs
                }
                Read-Host "`n  Press Enter to continue"
            }
            'q' {
                Write-Host "`n  Goodbye!" -ForegroundColor Green
                Write-Host ""
                return
            }
            'Q' {
                Write-Host "`n  Goodbye!" -ForegroundColor Green
                Write-Host ""
                return
            }
            default {
                Write-Warn "Invalid option: $choice"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# =============================================================================
# Main
# =============================================================================

function Main {
    if ($Help) {
        Show-Help
        return
    }

    # Default to interactive mode when no command specified
    if ($Command -eq 'status' -and -not $Wrapper -and $PSBoundParameters.Count -eq 0) {
        $Command = 'interactive'
    }

    switch ($Command) {
        { $_ -in 'interactive', 'menu', '' } { Show-InteractiveMenu }
        'status' { Show-Status }
        'install' { Install-Wrapper }
        'init' { Initialize-Config }
        { $_ -in 'run', 'backup' } { Start-WrapperBackup }
        { $_ -in 'check', 'verify' } { Test-Backup }
        { $_ -in 'list', 'snapshots' } { Show-Backups }
        'schedule' { Set-Schedule }
        { $_ -in 'config', 'edit' } { Edit-Config }
        'docs' { Show-Docs }
        default {
            Write-Err "Unknown command: $Command"
            Show-Help
        }
    }
}

Main
