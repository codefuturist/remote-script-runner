<#
.SYNOPSIS
    Windows Backup - Unified backup management for Windows

.DESCRIPTION
    Comprehensive Windows backup solution supporting:
    - Windows Backup (wbadmin)
    - File History
    - VSS Shadow Copies
    - Robocopy-based backups
    - System Image backups

.PARAMETER Command
    Action to perform: status, backup, restore, history, vss, schedule

.EXAMPLE
    .\windows-backup.ps1 status

.EXAMPLE
    .\windows-backup.ps1 backup -Source C:\Users -Destination D:\Backups

.EXAMPLE
    .\windows-backup.ps1 vss -Create -Volume C:

.NOTES
    Version: 1.0.0
    Author:  RSR Team
    License: MIT
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'backup', 'restore', 'history', 'vss', 'schedule', 'systemimage', 'filehistory')]
    [string]$Command = 'status',

    [Parameter()]
    [string[]]$Source,

    [Parameter()]
    [string]$Destination,

    [Parameter()]
    [string[]]$Exclude,

    [Parameter()]
    [switch]$Mirror,

    [Parameter()]
    [switch]$Create,

    [Parameter()]
    [switch]$Delete,

    [Parameter()]
    [switch]$List,

    [Parameter()]
    [string]$Volume = 'C:',

    [Parameter()]
    [string]$SnapshotId,

    [Parameter()]
    [string]$Target,

    [Parameter()]
    [string]$Time = '02:00',

    [Parameter()]
    [switch]$Daily,

    [Parameter()]
    [switch]$Help,

    [Parameter()]
    [switch]$Verbose
)

# =============================================================================
# Configuration
# =============================================================================

$Script:Name = 'Windows Backup'
$Script:Version = '1.0.0'

# =============================================================================
# RSR Library
# =============================================================================

$RSRModulePath = Join-Path $PSScriptRoot '../../lib/powershell/RSR.psd1'
if (Test-Path $RSRModulePath) {
    Import-Module $RSRModulePath -Force -ErrorAction SilentlyContinue
}

# Fallback logging if RSR module not loaded
if (-not (Get-Command Write-RSRInfo -ErrorAction SilentlyContinue)) {
    function Write-RSRInfo { param([string]$Message) Write-Host "▸ $Message" -ForegroundColor Cyan }
    function Write-RSROk { param([string]$Message) Write-Host "✓ $Message" -ForegroundColor Green }
    function Write-RSRWarn { param([string]$Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
    function Write-RSRError { param([string]$Message) Write-Host "✗ $Message" -ForegroundColor Red }
}

# =============================================================================
# Help
# =============================================================================

function Show-Help {
    @"
Windows Backup - Comprehensive Windows backup management

USAGE:
    windows-backup.ps1 [COMMAND] [OPTIONS]

COMMANDS:
    status          Show backup status (default)
    backup          Create backup using robocopy
    restore         Restore from backup
    history         Manage File History
    vss             Manage VSS shadow copies
    schedule        Create scheduled backup task
    systemimage     Create/restore system image
    filehistory     Configure File History

BACKUP OPTIONS:
    -Source PATH        Source path(s) to backup
    -Destination PATH   Backup destination
    -Exclude PATTERN    Exclude patterns
    -Mirror             Mirror mode (delete extra files)

VSS OPTIONS:
    -Create             Create shadow copy
    -Delete             Delete shadow copy
    -List               List shadow copies
    -Volume X:          Target volume
    -SnapshotId ID      Snapshot ID for operations

RESTORE OPTIONS:
    -Target PATH        Restore target path
    -SnapshotId ID      VSS snapshot to restore from

SCHEDULE OPTIONS:
    -Time HH:MM         Backup time (default: 02:00)
    -Daily              Run daily

EXAMPLES:
    # Check backup status
    .\windows-backup.ps1 status

    # Backup user folders
    .\windows-backup.ps1 backup -Source C:\Users -Destination D:\Backups

    # Mirror backup with exclusions
    .\windows-backup.ps1 backup -Source C:\Data -Destination E:\Backup -Mirror -Exclude "*.tmp","Temp"

    # Create VSS snapshot
    .\windows-backup.ps1 vss -Create -Volume C:

    # List VSS snapshots
    .\windows-backup.ps1 vss -List

    # Create scheduled daily backup
    .\windows-backup.ps1 schedule -Source C:\Users -Destination D:\Backup -Daily -Time 03:00

    # Create system image
    .\windows-backup.ps1 systemimage -Destination E:

"@
}

# =============================================================================
# Status Command
# =============================================================================

function Get-BackupStatus {
    Write-Host ""
    Write-Host "═══ Windows Backup Status ═══" -ForegroundColor Cyan
    Write-Host ""

    # Windows Backup Status
    Write-Host "Windows Backup (wbadmin):" -ForegroundColor Yellow
    try {
        $wbStatus = wbadmin get status 2>&1
        if ($wbStatus -match "no backup") {
            Write-Host "  No backup in progress" -ForegroundColor Gray
        } else {
            Write-Host "  $wbStatus"
        }
    } catch {
        Write-Host "  Not available" -ForegroundColor Gray
    }

    Write-Host ""

    # File History Status
    Write-Host "File History:" -ForegroundColor Yellow
    try {
        $fhStatus = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\FileHistory' -ErrorAction SilentlyContinue
        if ($fhStatus) {
            Write-Host "  Configured: Yes" -ForegroundColor Green
            if ($fhStatus.TargetUrl) {
                Write-Host "  Target: $($fhStatus.TargetUrl)"
            }
        } else {
            Write-Host "  Configured: No" -ForegroundColor Gray
            Write-Host "  Configure in: Settings → Update & Security → Backup"
        }
    } catch {
        Write-Host "  Not available" -ForegroundColor Gray
    }

    Write-Host ""

    # VSS Status
    Write-Host "Volume Shadow Copies:" -ForegroundColor Yellow
    try {
        $shadows = Get-WmiObject Win32_ShadowCopy -ErrorAction SilentlyContinue
        if ($shadows) {
            $count = ($shadows | Measure-Object).Count
            Write-Host "  Available snapshots: $count" -ForegroundColor Green

            $shadows | Sort-Object InstallDate -Descending | Select-Object -First 3 | ForEach-Object {
                $date = [Management.ManagementDateTimeConverter]::ToDateTime($_.InstallDate)
                Write-Host "    • $($date.ToString('yyyy-MM-dd HH:mm')) - $($_.VolumeName)"
            }
        } else {
            Write-Host "  No shadow copies found" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Not available" -ForegroundColor Gray
    }

    Write-Host ""

    # Scheduled Tasks
    Write-Host "Scheduled Backup Tasks:" -ForegroundColor Yellow
    try {
        $tasks = Get-ScheduledTask -TaskPath '\' -ErrorAction SilentlyContinue |
                 Where-Object { $_.TaskName -like '*backup*' -or $_.TaskName -like '*RSR*' }

        if ($tasks) {
            $tasks | ForEach-Object {
                $state = $_.State
                $color = if ($state -eq 'Ready') { 'Green' } else { 'Gray' }
                Write-Host "  • $($_.TaskName): $state" -ForegroundColor $color
            }
        } else {
            Write-Host "  No backup tasks found" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Could not query scheduled tasks" -ForegroundColor Gray
    }

    Write-Host ""
}

# =============================================================================
# Backup Command (Robocopy)
# =============================================================================

function Start-RobocopyBackup {
    if (-not $Source) {
        Write-RSRError "Source path required. Use -Source"
        return
    }

    if (-not $Destination) {
        Write-RSRError "Destination path required. Use -Destination"
        return
    }

    Write-RSRInfo "Starting robocopy backup..."
    Write-RSRInfo "Source: $($Source -join ', ')"
    Write-RSRInfo "Destination: $Destination"

    # Build robocopy arguments
    $robocopyArgs = @()

    if ($Mirror) {
        $robocopyArgs += '/MIR'
    } else {
        $robocopyArgs += '/E'  # Copy subdirectories including empty ones
    }

    # Standard options
    $robocopyArgs += @(
        '/R:3',      # Retries
        '/W:5',      # Wait between retries
        '/MT:8',     # Multi-threaded
        '/NP',       # No progress percentage
        '/NDL',      # No directory list
        '/TEE',      # Output to console and log
        '/DCOPY:DAT' # Copy directory timestamps
    )

    # Exclusions
    if ($Exclude) {
        $robocopyArgs += '/XD'
        $robocopyArgs += $Exclude
        $robocopyArgs += '/XF'
        $robocopyArgs += $Exclude
    }

    # Default exclusions
    $defaultExcludes = @('$Recycle.Bin', 'System Volume Information', 'pagefile.sys', 'hiberfil.sys', 'swapfile.sys')
    $robocopyArgs += '/XD'
    $robocopyArgs += $defaultExcludes

    # Log file
    $logDir = Join-Path $Destination '_logs'
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logFile = Join-Path $logDir "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $robocopyArgs += "/LOG+:$logFile"

    # Run backup for each source
    foreach ($src in $Source) {
        $destPath = Join-Path $Destination (Split-Path $src -Leaf)

        Write-RSRInfo "Backing up: $src"

        & robocopy $src $destPath @robocopyArgs

        # Robocopy exit codes: 0-7 are success, 8+ are errors
        if ($LASTEXITCODE -lt 8) {
            Write-RSROk "Backup completed: $src"
        } else {
            Write-RSRError "Backup failed: $src (exit code: $LASTEXITCODE)"
        }
    }

    Write-RSRInfo "Log file: $logFile"
}

# =============================================================================
# VSS Commands
# =============================================================================

function Invoke-VSSCommand {
    if ($List) {
        Write-Host ""
        Write-Host "═══ VSS Shadow Copies ═══" -ForegroundColor Cyan
        Write-Host ""

        $shadows = Get-WmiObject Win32_ShadowCopy | Sort-Object InstallDate -Descending

        if (-not $shadows) {
            Write-RSRWarn "No shadow copies found"
            return
        }

        $shadows | ForEach-Object {
            $date = [Management.ManagementDateTimeConverter]::ToDateTime($_.InstallDate)
            Write-Host "ID: $($_.ID)" -ForegroundColor Yellow
            Write-Host "  Volume: $($_.VolumeName)"
            Write-Host "  Created: $($date.ToString('yyyy-MM-dd HH:mm:ss'))"
            Write-Host "  Device: $($_.DeviceObject)"
            Write-Host ""
        }
    }
    elseif ($Create) {
        Write-RSRInfo "Creating VSS snapshot for $Volume..."

        try {
            $shadow = (Get-WmiObject -List Win32_ShadowCopy).Create($Volume, "ClientAccessible")

            if ($shadow.ReturnValue -eq 0) {
                $newShadow = Get-WmiObject Win32_ShadowCopy | Where-Object { $_.ID -eq $shadow.ShadowID }
                Write-RSROk "Shadow copy created"
                Write-Host "  ID: $($shadow.ShadowID)"
                Write-Host "  Device: $($newShadow.DeviceObject)"
            } else {
                Write-RSRError "Failed to create shadow copy. Return code: $($shadow.ReturnValue)"
            }
        } catch {
            Write-RSRError "VSS operation failed: $_"
        }
    }
    elseif ($Delete) {
        if (-not $SnapshotId) {
            Write-RSRError "Snapshot ID required. Use -SnapshotId"
            return
        }

        Write-RSRInfo "Deleting VSS snapshot: $SnapshotId"

        try {
            $shadow = Get-WmiObject Win32_ShadowCopy | Where-Object { $_.ID -eq $SnapshotId }
            if ($shadow) {
                $shadow.Delete()
                Write-RSROk "Shadow copy deleted"
            } else {
                Write-RSRError "Shadow copy not found: $SnapshotId"
            }
        } catch {
            Write-RSRError "Failed to delete shadow copy: $_"
        }
    }
    else {
        # Default to list
        Invoke-VSSCommand -List
    }
}

# =============================================================================
# Restore Command
# =============================================================================

function Start-Restore {
    if (-not $Source) {
        Write-RSRError "Source backup path required. Use -Source"
        return
    }

    if (-not $Target) {
        Write-RSRError "Target restore path required. Use -Target"
        return
    }

    Write-RSRInfo "Restoring from backup..."
    Write-RSRInfo "Source: $Source"
    Write-RSRInfo "Target: $Target"

    # Create target directory
    if (-not (Test-Path $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }

    foreach ($src in $Source) {
        $robocopyArgs = @('/E', '/R:3', '/W:5', '/MT:8', '/NP')

        & robocopy $src $Target @robocopyArgs

        if ($LASTEXITCODE -lt 8) {
            Write-RSROk "Restore completed"
        } else {
            Write-RSRError "Restore failed (exit code: $LASTEXITCODE)"
        }
    }
}

# =============================================================================
# Schedule Command
# =============================================================================

function New-BackupSchedule {
    if (-not $Source) {
        Write-RSRError "Source path required. Use -Source"
        return
    }

    if (-not $Destination) {
        Write-RSRError "Destination path required. Use -Destination"
        return
    }

    $taskName = "RSR-Backup-$(Get-Date -Format 'yyyyMMdd')"

    Write-RSRInfo "Creating scheduled backup task: $taskName"
    Write-RSRInfo "Time: $Time"
    Write-RSRInfo "Frequency: $(if ($Daily) { 'Daily' } else { 'Once' })"

    # Build the robocopy command
    $sourcePaths = $Source -join '" "'
    $command = "robocopy `"$sourcePaths`" `"$Destination`" /MIR /R:3 /W:5 /MT:8 /NP"

    # Create scheduled task
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c $command"

    if ($Daily) {
        $trigger = New-ScheduledTaskTrigger -Daily -At $Time
    } else {
        $trigger = New-ScheduledTaskTrigger -Once -At $Time
    }

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable

    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    try {
        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Principal $principal `
            -Description "RSR Backup: $($Source -join ', ') -> $Destination" `
            -Force

        Write-RSROk "Scheduled task created: $taskName"
        Write-RSRInfo "View in Task Scheduler or run: Get-ScheduledTask -TaskName '$taskName'"
    } catch {
        Write-RSRError "Failed to create scheduled task: $_"
    }
}

# =============================================================================
# System Image Command
# =============================================================================

function Invoke-SystemImage {
    if (-not $Destination) {
        Write-RSRError "Destination drive required. Use -Destination (e.g., E:)"
        return
    }

    Write-RSRInfo "Creating system image backup..."
    Write-RSRInfo "Destination: $Destination"
    Write-RSRWarn "This may take a long time. Do not interrupt."

    try {
        # Use wbadmin for system image
        $wbadminArgs = @(
            'start', 'backup',
            '-backupTarget:' + $Destination,
            '-include:C:',
            '-allCritical',
            '-quiet'
        )

        & wbadmin @wbadminArgs

        if ($LASTEXITCODE -eq 0) {
            Write-RSROk "System image created successfully"
        } else {
            Write-RSRError "System image creation failed (exit code: $LASTEXITCODE)"
        }
    } catch {
        Write-RSRError "System image failed: $_"
    }
}

# =============================================================================
# File History Command
# =============================================================================

function Invoke-FileHistory {
    Write-Host ""
    Write-Host "═══ File History Configuration ═══" -ForegroundColor Cyan
    Write-Host ""

    # Check current status
    $fhPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\FileHistory'
    $fhConfig = Get-ItemProperty $fhPath -ErrorAction SilentlyContinue

    if ($fhConfig) {
        Write-Host "Status: Configured" -ForegroundColor Green
        if ($fhConfig.TargetUrl) {
            Write-Host "Target: $($fhConfig.TargetUrl)"
        }
    } else {
        Write-Host "Status: Not Configured" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "To configure File History:" -ForegroundColor Cyan
    Write-Host "  1. Open Settings → Update & Security → Backup"
    Write-Host "  2. Click 'Add a drive' to select backup destination"
    Write-Host "  3. Toggle 'Automatically back up my files' to On"
    Write-Host ""
    Write-Host "Or use PowerShell:" -ForegroundColor Cyan
    Write-Host "  # Enable File History on drive E:"
    Write-Host '  FhConfigureBackup -Target "E:\FileHistory" -UserProtected'
    Write-Host ""
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
        'status' { Get-BackupStatus }
        'backup' { Start-RobocopyBackup }
        'restore' { Start-Restore }
        'history' { Invoke-FileHistory }
        'vss' { Invoke-VSSCommand }
        'schedule' { New-BackupSchedule }
        'systemimage' { Invoke-SystemImage }
        'filehistory' { Invoke-FileHistory }
        default {
            Write-RSRError "Unknown command: $Command"
            Show-Help
        }
    }
}

Main

