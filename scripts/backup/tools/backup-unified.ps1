 <#
.SYNOPSIS
    RSR Unified Backup System for Windows - Comprehensive backup management

.DESCRIPTION
    Unified backup interface supporting multiple backup solutions:
    - Robocopy (file sync/mirror)
    - Windows Backup (wbadmin)
    - File History
    - VSS Shadow Copies
    - Restic (if installed)
    - Rclone (if installed)
    - Kopia (if installed)

.PARAMETER Command
    Main command: status, run, restore, list, init, verify, prune, profile, schedule, install

.PARAMETER Tool
    Backup tool to use: robocopy, wbadmin, restic, rclone, kopia, vss (auto-detects if not specified)

.PARAMETER Source
    Source path(s) to backup

.PARAMETER Destination
    Destination/repository path

.PARAMETER Profile
    Backup profile name

.EXAMPLE
    .\backup-unified.ps1 status

.EXAMPLE
    .\backup-unified.ps1 run -Source C:\Users\Me\Documents -Destination D:\Backups -Tool robocopy

.EXAMPLE
    .\backup-unified.ps1 profile create daily -Source C:\Users -Destination D:\Backups -Tool restic

.NOTES
    Version: 1.0.0
    Author:  RSR Team
    License: MIT
#>

[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'run', 'backup', 'restore', 'list', 'init', 'verify', 'prune', 'profile', 'schedule', 'install', 'interactive')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [string]$Subcommand = '',

    [Parameter()]
    [ValidateSet('auto', 'robocopy', 'wbadmin', 'restic', 'rclone', 'kopia', 'vss', 'filehistory')]
    [string]$Tool = 'auto',

    [Parameter()]
    [string[]]$Source,

    [Parameter()]
    [Alias('Dest', 'Repo', 'Repository')]
    [string]$Destination,

    [Parameter()]
    [string[]]$Exclude,

    [Parameter()]
    [string]$Profile,

    [Parameter()]
    [string]$Snapshot = 'latest',

    [Parameter()]
    [string]$Target,

    [Parameter()]
    [string]$Password,

    [Parameter()]
    [int]$KeepDaily = 7,

    [Parameter()]
    [int]$KeepWeekly = 4,

    [Parameter()]
    [int]$KeepMonthly = 6,

    [Parameter()]
    [int]$KeepYearly = 1,

    [Parameter()]
    [switch]$Mirror,

    [Parameter()]
    [switch]$Verify,

    [Parameter()]
    [switch]$Prune,

    [Parameter()]
    [switch]$Encrypt,

    [Parameter()]
    [string]$Time = '02:00',

    [Parameter()]
    [switch]$Daily,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [switch]$Quiet,

    [Parameter()]
    [switch]$VerboseOutput,

    [Parameter()]
    [switch]$Help
)

# =============================================================================
# Configuration
# =============================================================================

$Script:Name = 'RSR Unified Backup'
$Script:Version = '1.0.0'

# Cross-platform home directory detection
$homeDir = if ($env:USERPROFILE) { $env:USERPROFILE } elseif ($env:HOME) { $env:HOME } else { [Environment]::GetFolderPath('UserProfile') }
$Script:ProfileDir = Join-Path $homeDir '.config/rsr/backup/profiles'

# Priority order for tool auto-detection
$Script:ToolPriority = @('restic', 'kopia', 'rclone', 'robocopy')

# =============================================================================
# RSR Library
# =============================================================================

$RSRModulePath = Join-Path $PSScriptRoot '..\..\lib\powershell\RSR.psd1'
if (Test-Path $RSRModulePath) {
    Import-Module $RSRModulePath -Force -ErrorAction SilentlyContinue
}

# Fallback logging
if (-not (Get-Command Write-RSRInfo -ErrorAction SilentlyContinue)) {
    function Write-RSRInfo { param([string]$Message) if (-not $Quiet) { Write-Host "▸ $Message" -ForegroundColor Cyan } }
    function Write-RSROk { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
    function Write-RSRWarn { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
    function Write-RSRError { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
}

# =============================================================================
# Help
# =============================================================================

function Show-Help {
    @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                     RSR Unified Backup System (Windows)                      ║
╚══════════════════════════════════════════════════════════════════════════════╝

USAGE:
    backup-unified.ps1 [COMMAND] [OPTIONS]

COMMANDS:
    status          Show backup status and installed tools (default)
    run             Run a backup
    restore         Restore from backup
    list            List available backups/snapshots
    init            Initialize backup repository
    verify          Verify backup integrity
    prune           Apply retention policy
    profile         Manage backup profiles (create/list/show/delete/run)
    schedule        Create scheduled backup task
    install         Install backup tools
    interactive     Launch interactive backup menu

GLOBAL OPTIONS:
    -Help               Show this help message
    -VerboseOutput      Enable verbose output
    -Quiet              Suppress non-essential output
    -DryRun             Show what would be done without executing

RUN OPTIONS:
    -Tool TOOL          Backup tool: auto, robocopy, restic, rclone, kopia, wbadmin
    -Source PATH        Source path(s) to backup
    -Destination PATH   Destination/repository path
    -Exclude PATTERN    Exclude patterns
    -Profile NAME       Use saved backup profile
    -Password PWD       Encryption password
    -Verify             Verify backup after completion
    -Prune              Apply retention policy after backup
    -Mirror             Mirror mode (delete extra files in destination)
    -Encrypt            Enable encryption (requires password)

RESTORE OPTIONS:
    -Snapshot ID        Snapshot ID to restore (default: latest)
    -Target PATH        Restore target path

RETENTION OPTIONS:
    -KeepDaily N        Keep N daily backups (default: 7)
    -KeepWeekly N       Keep N weekly backups (default: 4)
    -KeepMonthly N      Keep N monthly backups (default: 6)
    -KeepYearly N       Keep N yearly backups (default: 1)

PROFILE SUBCOMMANDS:
    profile create NAME     Create a new profile
    profile list            List all profiles
    profile show NAME       Show profile details
    profile delete NAME     Delete a profile
    profile run NAME        Run backup using profile

SCHEDULE OPTIONS:
    -Time HH:MM         Time to run scheduled backup (default: 02:00)
    -Daily              Run daily

SUPPORTED BACKUP TOOLS:
    robocopy    Built-in Windows file copy (fast, reliable)
    wbadmin     Windows Server Backup (system images)
    restic      Fast, secure, deduplicated backups
    rclone      Cloud storage swiss army knife (40+ backends)
    kopia       Fast, encrypted, deduplicated backups
    vss         Volume Shadow Copy Service
    filehistory Windows File History

EXAMPLES:
    # Check status and installed tools
    .\backup-unified.ps1 status

    # Quick backup with auto-detected tool
    .\backup-unified.ps1 run -Source C:\Users\Me -Destination D:\Backup

    # Backup with specific tool
    .\backup-unified.ps1 run -Tool restic -Source C:\Data -Destination D:\Repo -Encrypt

    # Create and use a profile
    .\backup-unified.ps1 profile create daily -Tool restic -Source C:\Users -Destination D:\Backup
    .\backup-unified.ps1 profile run daily

    # Restore latest backup
    .\backup-unified.ps1 restore -Destination D:\Repo -Target C:\Restore

    # Schedule daily backup
    .\backup-unified.ps1 schedule -Profile daily -Time 02:00 -Daily

    # Launch interactive menu
    .\backup-unified.ps1 interactive

"@
}

# =============================================================================
# Tool Detection
# =============================================================================

function Test-BackupTool {
    param([string]$ToolName)

    # Check if running on Windows
    $runningOnWindows = $env:OS -eq 'Windows_NT' -or ([System.Environment]::OSVersion.Platform -eq 'Win32NT')

    switch ($ToolName) {
        'robocopy' { return $runningOnWindows -and ((Get-Command robocopy -ErrorAction SilentlyContinue) -ne $null) }
        'wbadmin' { return $runningOnWindows -and ((Get-Command wbadmin -ErrorAction SilentlyContinue) -ne $null) }
        'restic' { return (Get-Command restic -ErrorAction SilentlyContinue) -ne $null }
        'rclone' { return (Get-Command rclone -ErrorAction SilentlyContinue) -ne $null }
        'kopia' { return (Get-Command kopia -ErrorAction SilentlyContinue) -ne $null }
        'vss' { return $runningOnWindows }  # Built into Windows only
        'filehistory' { return $runningOnWindows }  # Built into Windows only
        default { return $false }
    }
}

function Get-BackupToolVersion {
    param([string]$ToolName)

    switch ($ToolName) {
        'robocopy' {
            try {
                $cmd = Get-Command robocopy -ErrorAction Stop
                if ($cmd -and $cmd.Version) {
                    return "$($cmd.Version.Major).$($cmd.Version.Minor)"
                }
                return 'system'
            } catch {
                return 'unknown'
            }
        }
        'restic' {
            try {
                $output = restic version 2>&1
                if ($output -match 'restic (\d+\.\d+\.\d+)') { return $Matches[1] }
            } catch { }
            return 'unknown'
        }
        'rclone' {
            try {
                $output = rclone version 2>&1 | Select-Object -First 1
                if ($output -match 'v(\d+\.\d+\.\d+)') { return $Matches[1] }
            } catch { }
            return 'unknown'
        }
        'kopia' {
            try {
                $output = kopia --version 2>&1
                if ($output -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
            } catch { }
            return 'unknown'
        }
        'wbadmin' { return 'system' }
        'vss' { return 'system' }
        'filehistory' { return 'system' }
        default { return 'unknown' }
    }
}

function Get-InstalledBackupTools {
    $tools = @()
    foreach ($tool in @('robocopy', 'wbadmin', 'vss', 'restic', 'rclone', 'kopia')) {
        if (Test-BackupTool $tool) {
            $tools += @{
                Name = $tool
                Version = Get-BackupToolVersion $tool
                Installed = $true
            }
        }
    }
    return $tools
}

function Get-DefaultBackupTool {
    foreach ($tool in $Script:ToolPriority) {
        if (Test-BackupTool $tool) {
            return $tool
        }
    }
    return 'robocopy'  # Fallback to robocopy (always available)
}

# =============================================================================
# Status Command
# =============================================================================

function Show-BackupStatus {
    Write-Host ""
    Write-Host "═══ RSR Unified Backup System Status ═══" -ForegroundColor Cyan
    Write-Host ""

    # Installed tools
    Write-Host "Installed Backup Tools:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host ("{0,-15} {1,-15} {2}" -f "TOOL", "VERSION", "STATUS")
    Write-Host ("{0,-15} {1,-15} {2}" -f "────", "───────", "──────")

    $installedTools = Get-InstalledBackupTools
    foreach ($tool in $installedTools) {
        Write-Host ("{0,-15} {1,-15} " -f $tool.Name, $tool.Version) -NoNewline
        Write-Host "✓ installed" -ForegroundColor Green
    }

    # Missing popular tools
    $popularTools = @('restic', 'rclone', 'kopia')
    foreach ($tool in $popularTools) {
        if (-not (Test-BackupTool $tool)) {
            Write-Host ("{0,-15} {1,-15} " -f $tool, "-") -NoNewline
            Write-Host "○ not installed" -ForegroundColor Gray
        }
    }

    Write-Host ""

    # Default tool
    $defaultTool = Get-DefaultBackupTool
    Write-Host "Default Tool: " -NoNewline
    Write-Host $defaultTool -ForegroundColor Green
    Write-Host ""

    # Profiles
    Write-Host "Backup Profiles:" -ForegroundColor Yellow
    if (Test-Path $Script:ProfileDir) {
        $profiles = Get-ChildItem -Path $Script:ProfileDir -Filter "*.json" -ErrorAction SilentlyContinue
        if ($profiles) {
            foreach ($profile in $profiles) {
                Write-Host "  • $($profile.BaseName)"
            }
        } else {
            Write-Host "  (no profiles configured)" -ForegroundColor Gray
        }
    } else {
        Write-Host "  (no profiles configured)" -ForegroundColor Gray
    }

    Write-Host ""

    # VSS Status
    Write-Host "Volume Shadow Copies:" -ForegroundColor Yellow
    try {
        $shadows = Get-WmiObject Win32_ShadowCopy -ErrorAction SilentlyContinue
        if ($shadows) {
            $count = ($shadows | Measure-Object).Count
            Write-Host "  Snapshots available: $count" -ForegroundColor Green
        } else {
            Write-Host "  No snapshots" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Unable to query" -ForegroundColor Gray
    }

    Write-Host ""

    # Scheduled Tasks
    Write-Host "Scheduled Backup Tasks:" -ForegroundColor Yellow
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
                 Where-Object { $_.TaskName -like '*backup*' -or $_.TaskName -like '*RSR*' }
        if ($tasks) {
            foreach ($task in $tasks) {
                $color = if ($task.State -eq 'Ready') { 'Green' } else { 'Gray' }
                Write-Host "  • $($task.TaskName): $($task.State)" -ForegroundColor $color
            }
        } else {
            Write-Host "  (no backup tasks)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Unable to query" -ForegroundColor Gray
    }

    Write-Host ""
}

# =============================================================================
# Backup Commands
# =============================================================================

function Start-Backup {
    # Use profile if specified
    if ($Profile) {
        Start-ProfileBackup
        return
    }

    # Validate
    if (-not $Source) {
        Write-RSRError "Source path required. Use -Source"
        return
    }

    if (-not $Destination) {
        Write-RSRError "Destination path required. Use -Destination"
        return
    }

    # Auto-detect tool
    if ($Tool -eq 'auto') {
        $Tool = Get-DefaultBackupTool
        Write-RSRInfo "Auto-selected backup tool: $Tool"
    }

    if (-not (Test-BackupTool $Tool)) {
        Write-RSRError "Backup tool '$Tool' is not installed"
        return
    }

    Write-Host ""
    Write-Host "═══ Running Backup ═══" -ForegroundColor Cyan
    Write-Host ""

    Write-RSRInfo "Tool: $Tool"
    Write-RSRInfo "Source: $($Source -join ', ')"
    Write-RSRInfo "Destination: $Destination"

    if ($Exclude) {
        Write-RSRInfo "Excludes: $($Exclude -join ', ')"
    }

    if ($DryRun) {
        Write-RSRWarn "Dry run mode - no changes will be made"
    }

    Write-Host ""

    # Execute backup based on tool
    $success = $false

    switch ($Tool) {
        'robocopy' { $success = Invoke-RobocopyBackup }
        'restic' { $success = Invoke-ResticBackup }
        'rclone' { $success = Invoke-RcloneBackup }
        'kopia' { $success = Invoke-KopiaBackup }
        default {
            Write-RSRError "Unsupported tool: $Tool"
            return
        }
    }

    if ($success) {
        if ($Verify) {
            Write-RSRInfo "Verifying backup..."
            Start-BackupVerify
        }

        if ($Prune) {
            Write-RSRInfo "Applying retention policy..."
            Start-BackupPrune
        }

        Write-RSROk "Backup completed successfully"
    } else {
        Write-RSRError "Backup failed"
    }
}

function Invoke-RobocopyBackup {
    $robocopyArgs = @()

    if ($Mirror) {
        $robocopyArgs += '/MIR'
    } else {
        $robocopyArgs += '/E'
    }

    $robocopyArgs += @('/R:3', '/W:5', '/MT:8', '/NP', '/NDL', '/TEE')

    if ($Exclude) {
        $robocopyArgs += '/XD'
        $robocopyArgs += $Exclude
        $robocopyArgs += '/XF'
        $robocopyArgs += ($Exclude | ForEach-Object { "*$_*" })
    }

    # Default exclusions
    $robocopyArgs += '/XD'
    $robocopyArgs += @('$Recycle.Bin', 'System Volume Information')

    if ($DryRun) {
        $robocopyArgs += '/L'
    }

    $allSuccess = $true

    foreach ($src in $Source) {
        $destPath = Join-Path $Destination (Split-Path $src -Leaf)
        Write-RSRInfo "Backing up: $src -> $destPath"

        if ($VerboseOutput) {
            & robocopy $src $destPath @robocopyArgs
        } else {
            & robocopy $src $destPath @robocopyArgs | Out-Null
        }

        if ($LASTEXITCODE -ge 8) {
            $allSuccess = $false
            Write-RSRError "Robocopy failed for: $src"
        }
    }

    return $allSuccess
}

function Invoke-ResticBackup {
    if ($Password) {
        $env:RESTIC_PASSWORD = $Password
    } elseif (-not $env:RESTIC_PASSWORD) {
        Write-RSRError "Password required for restic. Use -Password or set RESTIC_PASSWORD"
        return $false
    }

    $resticArgs = @('backup', '-r', $Destination)

    if ($Exclude) {
        foreach ($ex in $Exclude) {
            $resticArgs += @('--exclude', $ex)
        }
    }

    if ($DryRun) {
        $resticArgs += '-n'
    }

    if ($VerboseOutput) {
        $resticArgs += '-v'
    }

    $resticArgs += $Source

    try {
        & restic @resticArgs
        return $LASTEXITCODE -eq 0
    } catch {
        Write-RSRError "Restic error: $_"
        return $false
    }
}

function Invoke-RcloneBackup {
    $rcloneArgs = @('sync')

    if ($Exclude) {
        foreach ($ex in $Exclude) {
            $rcloneArgs += @('--exclude', $ex)
        }
    }

    if ($DryRun) {
        $rcloneArgs += '--dry-run'
    }

    if ($VerboseOutput) {
        $rcloneArgs += '-v'
    }

    $rcloneArgs += '--progress'

    $allSuccess = $true

    foreach ($src in $Source) {
        $destPath = "$Destination/$(Split-Path $src -Leaf)"
        $args = $rcloneArgs + @($src, $destPath)

        try {
            & rclone @args
            if ($LASTEXITCODE -ne 0) { $allSuccess = $false }
        } catch {
            $allSuccess = $false
            Write-RSRError "Rclone error: $_"
        }
    }

    return $allSuccess
}

function Invoke-KopiaBackup {
    if ($Password) {
        $env:KOPIA_PASSWORD = $Password
    }

    $kopiaArgs = @('snapshot', 'create')

    if ($Exclude) {
        foreach ($ex in $Exclude) {
            $kopiaArgs += @('--add-ignore', $ex)
        }
    }

    if ($DryRun) {
        $kopiaArgs += '--dry-run'
    }

    $kopiaArgs += $Source

    try {
        & kopia @kopiaArgs
        return $LASTEXITCODE -eq 0
    } catch {
        Write-RSRError "Kopia error: $_"
        return $false
    }
}

# =============================================================================
# Restore Command
# =============================================================================

function Start-Restore {
    if (-not $Destination) {
        Write-RSRError "Repository/source path required. Use -Destination"
        return
    }

    if (-not $Target) {
        Write-RSRError "Restore target path required. Use -Target"
        return
    }

    if ($Tool -eq 'auto') {
        $Tool = Get-DefaultBackupTool
    }

    Write-Host ""
    Write-Host "═══ Restoring Backup ═══" -ForegroundColor Cyan
    Write-Host ""

    Write-RSRInfo "Tool: $Tool"
    Write-RSRInfo "Source: $Destination"
    Write-RSRInfo "Snapshot: $Snapshot"
    Write-RSRInfo "Target: $Target"

    if (-not (Test-Path $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }

    switch ($Tool) {
        'robocopy' {
            & robocopy $Destination $Target /E /R:3 /W:5 /MT:8 /NP
            if ($LASTEXITCODE -lt 8) {
                Write-RSROk "Restore completed"
            } else {
                Write-RSRError "Restore failed"
            }
        }
        'restic' {
            if ($Password) { $env:RESTIC_PASSWORD = $Password }
            & restic -r $Destination restore $Snapshot --target $Target
        }
        'rclone' {
            & rclone sync $Destination $Target --progress
        }
        'kopia' {
            if ($Password) { $env:KOPIA_PASSWORD = $Password }
            & kopia snapshot restore $Snapshot $Target
        }
    }
}

# =============================================================================
# List Command
# =============================================================================

function Show-BackupList {
    if (-not $Destination) {
        Write-RSRError "Repository path required. Use -Destination"
        return
    }

    if ($Tool -eq 'auto') {
        $Tool = Get-DefaultBackupTool
    }

    Write-Host ""
    Write-Host "═══ Backup Snapshots ═══" -ForegroundColor Cyan
    Write-Host ""

    switch ($Tool) {
        'robocopy' {
            Get-ChildItem -Path $Destination -Directory | ForEach-Object {
                Write-Host "  $($_.Name) - $($_.LastWriteTime)"
            }
        }
        'restic' {
            if ($Password) { $env:RESTIC_PASSWORD = $Password }
            & restic -r $Destination snapshots
        }
        'rclone' {
            & rclone lsd $Destination
        }
        'kopia' {
            if ($Password) { $env:KOPIA_PASSWORD = $Password }
            & kopia snapshot list
        }
    }
}

# =============================================================================
# Init Command
# =============================================================================

function Initialize-BackupRepo {
    if (-not $Destination) {
        Write-RSRError "Repository path required. Use -Destination"
        return
    }

    if ($Tool -eq 'auto') {
        $Tool = Get-DefaultBackupTool
    }

    Write-Host ""
    Write-Host "═══ Initializing Backup Repository ═══" -ForegroundColor Cyan
    Write-Host ""

    Write-RSRInfo "Tool: $Tool"
    Write-RSRInfo "Repository: $Destination"

    switch ($Tool) {
        'robocopy' {
            if (-not (Test-Path $Destination)) {
                New-Item -ItemType Directory -Path $Destination -Force | Out-Null
            }
            Write-RSROk "Directory created: $Destination"
        }
        'restic' {
            if ($Password) { $env:RESTIC_PASSWORD = $Password }
            & restic init -r $Destination
        }
        'rclone' {
            if (-not (Test-Path $Destination)) {
                New-Item -ItemType Directory -Path $Destination -Force | Out-Null
            }
            Write-RSROk "Directory created: $Destination"
        }
        'kopia' {
            if ($Password) {
                & kopia repository create filesystem --path $Destination --password $Password
            } else {
                & kopia repository create filesystem --path $Destination
            }
        }
    }
}

# =============================================================================
# Verify Command
# =============================================================================

function Start-BackupVerify {
    if (-not $Destination) {
        Write-RSRError "Repository path required. Use -Destination"
        return
    }

    if ($Tool -eq 'auto') {
        $Tool = Get-DefaultBackupTool
    }

    Write-Host ""
    Write-Host "═══ Verifying Backup ═══" -ForegroundColor Cyan
    Write-Host ""

    switch ($Tool) {
        'robocopy' {
            if (Test-Path $Destination) {
                Write-RSROk "Backup destination exists"
            } else {
                Write-RSRError "Backup destination not found"
            }
        }
        'restic' {
            if ($Password) { $env:RESTIC_PASSWORD = $Password }
            & restic -r $Destination check
        }
        'kopia' {
            if ($Password) { $env:KOPIA_PASSWORD = $Password }
            & kopia snapshot verify
        }
        default {
            Write-RSRWarn "Verification not supported for $Tool"
        }
    }
}

# =============================================================================
# Prune Command
# =============================================================================

function Start-BackupPrune {
    if (-not $Destination) {
        Write-RSRError "Repository path required. Use -Destination"
        return
    }

    if ($Tool -eq 'auto') {
        $Tool = Get-DefaultBackupTool
    }

    Write-Host ""
    Write-Host "═══ Applying Retention Policy ═══" -ForegroundColor Cyan
    Write-Host ""

    Write-RSRInfo "Keep daily: $KeepDaily"
    Write-RSRInfo "Keep weekly: $KeepWeekly"
    Write-RSRInfo "Keep monthly: $KeepMonthly"

    switch ($Tool) {
        'restic' {
            if ($Password) { $env:RESTIC_PASSWORD = $Password }
            $args = @('-r', $Destination, 'forget',
                '--keep-daily', $KeepDaily,
                '--keep-weekly', $KeepWeekly,
                '--keep-monthly', $KeepMonthly,
                '--prune')
            if ($DryRun) { $args += '-n' }
            & restic @args
        }
        'kopia' {
            if ($Password) { $env:KOPIA_PASSWORD = $Password }
            & kopia policy set --global `
                --keep-daily $KeepDaily `
                --keep-weekly $KeepWeekly `
                --keep-monthly $KeepMonthly
            & kopia maintenance run --full
        }
        default {
            Write-RSRWarn "Retention policy not supported for $Tool"
        }
    }
}

# =============================================================================
# Profile Management
# =============================================================================

function Invoke-ProfileCommand {
    switch ($Subcommand.ToLower()) {
        'create' { New-BackupProfile }
        'list' { Show-ProfileList }
        'show' { Show-Profile }
        'delete' { Remove-BackupProfile }
        'run' { Start-ProfileBackup }
        default { Show-ProfileList }
    }
}

function New-BackupProfile {
    if (-not $Profile) {
        Write-RSRError "Profile name required. Use -Profile"
        return
    }

    if (-not $Source) {
        Write-RSRError "Source path required. Use -Source"
        return
    }

    if (-not $Destination) {
        Write-RSRError "Destination path required. Use -Destination"
        return
    }

    if (-not (Test-Path $Script:ProfileDir)) {
        New-Item -ItemType Directory -Path $Script:ProfileDir -Force | Out-Null
    }

    $profileData = @{
        Name = $Profile
        Tool = if ($Tool -eq 'auto') { Get-DefaultBackupTool } else { $Tool }
        Source = $Source
        Destination = $Destination
        Exclude = $Exclude
        KeepDaily = $KeepDaily
        KeepWeekly = $KeepWeekly
        KeepMonthly = $KeepMonthly
        KeepYearly = $KeepYearly
        Verify = $Verify.IsPresent
        Prune = $Prune.IsPresent
        Mirror = $Mirror.IsPresent
        Created = Get-Date -Format 'o'
    }

    $profilePath = Join-Path $Script:ProfileDir "$Profile.json"
    $profileData | ConvertTo-Json -Depth 10 | Set-Content -Path $profilePath

    Write-RSROk "Created profile: $Profile"
    Write-RSRInfo "Saved to: $profilePath"
}

function Show-ProfileList {
    Write-Host ""
    Write-Host "═══ Backup Profiles ═══" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $Script:ProfileDir)) {
        Write-RSRWarn "No profiles configured"
        Write-Host ""
        Write-Host "Create a profile with:"
        Write-Host "  .\backup-unified.ps1 profile create myprofile -Source C:\Users -Destination D:\Backup"
        return
    }

    $profiles = Get-ChildItem -Path $Script:ProfileDir -Filter "*.json" -ErrorAction SilentlyContinue

    if (-not $profiles) {
        Write-RSRWarn "No profiles configured"
        return
    }

    foreach ($file in $profiles) {
        $data = Get-Content $file.FullName | ConvertFrom-Json
        Write-Host "Profile: $($data.Name)" -ForegroundColor Yellow
        Write-Host "  Tool: $($data.Tool)"
        Write-Host "  Source: $($data.Source -join ', ')"
        Write-Host "  Destination: $($data.Destination)"
        Write-Host ""
    }
}

function Show-Profile {
    if (-not $Profile) {
        Write-RSRError "Profile name required. Use -Profile"
        return
    }

    $profilePath = Join-Path $Script:ProfileDir "$Profile.json"

    if (-not (Test-Path $profilePath)) {
        Write-RSRError "Profile not found: $Profile"
        return
    }

    Write-Host ""
    Write-Host "═══ Profile: $Profile ═══" -ForegroundColor Cyan
    Write-Host ""

    Get-Content $profilePath | ConvertFrom-Json | Format-List
}

function Remove-BackupProfile {
    if (-not $Profile) {
        Write-RSRError "Profile name required. Use -Profile"
        return
    }

    $profilePath = Join-Path $Script:ProfileDir "$Profile.json"

    if (-not (Test-Path $profilePath)) {
        Write-RSRError "Profile not found: $Profile"
        return
    }

    if ($DryRun) {
        Write-RSRWarn "Would delete: $profilePath"
        return
    }

    Remove-Item $profilePath -Force
    Write-RSROk "Deleted profile: $Profile"
}

function Start-ProfileBackup {
    if (-not $Profile) {
        Write-RSRError "Profile name required. Use -Profile"
        return
    }

    $profilePath = Join-Path $Script:ProfileDir "$Profile.json"

    if (-not (Test-Path $profilePath)) {
        Write-RSRError "Profile not found: $Profile"
        return
    }

    $data = Get-Content $profilePath | ConvertFrom-Json

    # Override script parameters from profile
    $script:Tool = $data.Tool
    $script:Source = $data.Source
    $script:Destination = $data.Destination
    $script:Exclude = $data.Exclude
    $script:KeepDaily = $data.KeepDaily
    $script:KeepWeekly = $data.KeepWeekly
    $script:KeepMonthly = $data.KeepMonthly
    $script:Verify = [switch]$data.Verify
    $script:Prune = [switch]$data.Prune
    $script:Mirror = [switch]$data.Mirror

    Write-RSRInfo "Running profile: $Profile"
    Start-Backup
}

# =============================================================================
# Schedule Command
# =============================================================================

function New-BackupSchedule {
    if (-not $Profile) {
        Write-RSRError "Profile name required. Use -Profile"
        return
    }

    $profilePath = Join-Path $Script:ProfileDir "$Profile.json"

    if (-not (Test-Path $profilePath)) {
        Write-RSRError "Profile not found: $Profile"
        return
    }

    $taskName = "RSR-Backup-$Profile"
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }
    if (-not $scriptPath) {
        $scriptPath = Join-Path $PSScriptRoot 'backup-unified.ps1'
    }

    Write-Host ""
    Write-Host "═══ Creating Scheduled Backup ═══" -ForegroundColor Cyan
    Write-Host ""

    Write-RSRInfo "Profile: $Profile"
    Write-RSRInfo "Time: $Time"
    Write-RSRInfo "Frequency: $(if ($Daily) { 'Daily' } else { 'Once' })"

    if ($DryRun) {
        Write-RSRWarn "Would create scheduled task: $taskName"
        return
    }

    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" profile run $Profile"

    if ($Daily) {
        $trigger = New-ScheduledTaskTrigger -Daily -At $Time
    } else {
        $trigger = New-ScheduledTaskTrigger -Once -At $Time
    }

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable

    try {
        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description "RSR Backup Profile: $Profile" `
            -Force

        Write-RSROk "Scheduled task created: $taskName"
    } catch {
        Write-RSRError "Failed to create scheduled task: $_"
    }
}

# =============================================================================
# Install Command
# =============================================================================

function Install-BackupTool {
    $toolToInstall = if ($Subcommand) { $Subcommand } else { 'restic' }

    Write-Host ""
    Write-Host "═══ Installing Backup Tool ═══" -ForegroundColor Cyan
    Write-Host ""

    if (Test-BackupTool $toolToInstall) {
        $version = Get-BackupToolVersion $toolToInstall
        Write-RSRWarn "$toolToInstall is already installed (version: $version)"
        return
    }

    Write-RSRInfo "Installing: $toolToInstall"

    # Check for package managers
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    $hasChoco = Get-Command choco -ErrorAction SilentlyContinue
    $hasScoop = Get-Command scoop -ErrorAction SilentlyContinue

    switch ($toolToInstall) {
        'restic' {
            if ($hasWinget) {
                & winget install restic.restic
            } elseif ($hasChoco) {
                & choco install restic -y
            } elseif ($hasScoop) {
                & scoop install restic
            } else {
                Write-RSRWarn "Install manually from: https://restic.net/"
                Write-RSRInfo "Or install a package manager: winget, chocolatey, or scoop"
            }
        }
        'rclone' {
            if ($hasWinget) {
                & winget install Rclone.Rclone
            } elseif ($hasChoco) {
                & choco install rclone -y
            } elseif ($hasScoop) {
                & scoop install rclone
            } else {
                Write-RSRWarn "Install manually from: https://rclone.org/"
            }
        }
        'kopia' {
            if ($hasWinget) {
                & winget install KopiaUI
            } elseif ($hasChoco) {
                & choco install kopia -y
            } elseif ($hasScoop) {
                & scoop install kopia
            } else {
                Write-RSRWarn "Install manually from: https://kopia.io/"
            }
        }
        default {
            Write-RSRError "Unknown tool: $toolToInstall"
            Write-RSRInfo "Supported tools: restic, rclone, kopia"
        }
    }
}

# =============================================================================
# Interactive Menu
# =============================================================================

function Show-InteractiveMenu {
    Clear-Host

    while ($true) {
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║               RSR Unified Backup System                      ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [1] Check backup status"
        Write-Host "  [2] Run backup"
        Write-Host "  [3] Restore from backup"
        Write-Host "  [4] List backups/snapshots"
        Write-Host "  [5] Manage profiles"
        Write-Host "  [6] Create VSS snapshot"
        Write-Host "  [7] Schedule backup"
        Write-Host "  [8] Install backup tool"
        Write-Host "  [9] Exit"
        Write-Host ""

        $choice = Read-Host "Select an option"

        switch ($choice) {
            '1' {
                Show-BackupStatus
                Read-Host "Press Enter to continue"
            }
            '2' {
                $src = Read-Host "Source path"
                $dest = Read-Host "Destination path"
                $script:Source = @($src)
                $script:Destination = $dest
                $script:Tool = 'auto'
                Start-Backup
                Read-Host "Press Enter to continue"
            }
            '3' {
                $src = Read-Host "Backup source path"
                $dest = Read-Host "Restore target path"
                $script:Destination = $src
                $script:Target = $dest
                $script:Tool = 'auto'
                Start-Restore
                Read-Host "Press Enter to continue"
            }
            '4' {
                $dest = Read-Host "Repository path"
                $script:Destination = $dest
                $script:Tool = 'auto'
                Show-BackupList
                Read-Host "Press Enter to continue"
            }
            '5' {
                Show-ProfileList
                Read-Host "Press Enter to continue"
            }
            '6' {
                $vol = Read-Host "Volume (e.g., C:)"
                if (-not $vol) { $vol = "C:" }
                try {
                    $shadow = (Get-WmiObject -List Win32_ShadowCopy).Create($vol, "ClientAccessible")
                    Write-RSROk "VSS snapshot created: $($shadow.ShadowID)"
                } catch {
                    Write-RSRError "Failed to create VSS snapshot: $_"
                }
                Read-Host "Press Enter to continue"
            }
            '7' {
                $prof = Read-Host "Profile name"
                $time = Read-Host "Time (HH:MM)"
                if (-not $time) { $time = "02:00" }
                $script:Profile = $prof
                $script:Time = $time
                $script:Daily = $true
                New-BackupSchedule
                Read-Host "Press Enter to continue"
            }
            '8' {
                Write-Host "Available tools: restic, rclone, kopia"
                $tool = Read-Host "Tool to install"
                $script:Subcommand = $tool
                Install-BackupTool
                Read-Host "Press Enter to continue"
            }
            '9' {
                Write-Host "Goodbye!" -ForegroundColor Green
                return
            }
            default {
                Write-RSRWarn "Invalid option"
            }
        }

        Clear-Host
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

    switch ($Command.ToLower()) {
        'status' { Show-BackupStatus }
        { $_ -in 'run', 'backup' } { Start-Backup }
        'restore' { Start-Restore }
        'list' { Show-BackupList }
        'init' { Initialize-BackupRepo }
        'verify' { Start-BackupVerify }
        'prune' { Start-BackupPrune }
        { $_ -in 'profile', 'profiles' } { Invoke-ProfileCommand }
        'schedule' { New-BackupSchedule }
        'install' { Install-BackupTool }
        'interactive' { Show-InteractiveMenu }
        default {
            Write-RSRError "Unknown command: $Command"
            Show-Help
        }
    }
}

Main

