# RSR.Backup.psm1 - RSR Backup PowerShell Module
# Cross-platform backup operations with Windows-native support
#
# Usage: Import-Module RSR.Backup
#
# Provides:
#   - Tool detection (robocopy, rclone, restic, kopia, Windows Backup)
#   - VSS shadow copy support
#   - Windows File History integration
#   - Unified backup interface

#Requires -Version 5.1

# =============================================================================
# Module Variables
# =============================================================================

$Script:RSR_BACKUP_VERSION = '1.0.0'
$Script:RSR_BACKUP_TOOLS = @('restic', 'rclone', 'kopia', 'robocopy', 'wbadmin')

# =============================================================================
# Tool Detection
# =============================================================================

function Test-RSRBackupToolInstalled {
    <#
    .SYNOPSIS
        Check if a backup tool is installed
    .PARAMETER Tool
        Name of the backup tool to check
    .EXAMPLE
        Test-RSRBackupToolInstalled -Tool restic
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('rsync', 'rclone', 'restic', 'borg', 'kopia', 'robocopy', 'wbadmin', 'vss')]
        [string]$Tool
    )

    switch ($Tool) {
        'robocopy' { return $null -ne (Get-Command robocopy -ErrorAction SilentlyContinue) }
        'wbadmin' { return $null -ne (Get-Command wbadmin -ErrorAction SilentlyContinue) }
        'vss' { return $IsWindows -or (-not $IsLinux -and -not $IsMacOS) }
        'rsync' {
            # Check for WSL rsync or native
            return ($null -ne (Get-Command rsync -ErrorAction SilentlyContinue)) -or
                   ($null -ne (Get-Command wsl -ErrorAction SilentlyContinue))
        }
        default { return $null -ne (Get-Command $Tool -ErrorAction SilentlyContinue) }
    }
}

function Get-RSRBackupToolVersion {
    <#
    .SYNOPSIS
        Get version of a backup tool
    .PARAMETER Tool
        Name of the backup tool
    .EXAMPLE
        Get-RSRBackupToolVersion -Tool restic
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Tool
    )

    try {
        switch ($Tool) {
            'restic' {
                $output = restic version 2>&1
                if ($output -match 'restic\s+(\d+\.\d+\.\d+)') {
                    return $Matches[1]
                }
            }
            'rclone' {
                $output = rclone version 2>&1 | Select-Object -First 1
                if ($output -match 'v?(\d+\.\d+\.\d+)') {
                    return $Matches[1]
                }
            }
            'kopia' {
                $output = kopia --version 2>&1
                if ($output -match '(\d+\.\d+\.\d+)') {
                    return $Matches[1]
                }
            }
            'robocopy' {
                return (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId
            }
            'wbadmin' {
                return (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId
            }
        }
    } catch {
        return 'unknown'
    }
    return 'unknown'
}

function Get-RSRBackupTools {
    <#
    .SYNOPSIS
        List all installed backup tools with versions
    .EXAMPLE
        Get-RSRBackupTools
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    $tools = @()
    foreach ($tool in $Script:RSR_BACKUP_TOOLS) {
        if (Test-RSRBackupToolInstalled -Tool $tool) {
            $tools += [PSCustomObject]@{
                Name = $tool
                Version = Get-RSRBackupToolVersion -Tool $tool
                Available = $true
            }
        }
    }
    return $tools
}

function Get-RSRBackupDefaultTool {
    <#
    .SYNOPSIS
        Get the best available backup tool
    .EXAMPLE
        $tool = Get-RSRBackupDefaultTool
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Priority order for Windows
    $priority = @('restic', 'kopia', 'rclone', 'robocopy')

    foreach ($tool in $priority) {
        if (Test-RSRBackupToolInstalled -Tool $tool) {
            return $tool
        }
    }

    return $null
}

# =============================================================================
# VSS (Volume Shadow Copy) Support
# =============================================================================

function New-RSRVSSSnapshot {
    <#
    .SYNOPSIS
        Create a VSS shadow copy for consistent backups
    .PARAMETER Volume
        Volume to snapshot (e.g., C:)
    .EXAMPLE
        $snapshot = New-RSRVSSSnapshot -Volume 'C:'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Volume
    )

    if (-not (Test-RSRBackupToolInstalled -Tool vss)) {
        Write-RSRError "VSS is not available on this system"
        return $null
    }

    # Requires admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-RSRError "VSS operations require administrator privileges"
        return $null
    }

    if ($PSCmdlet.ShouldProcess($Volume, "Create VSS snapshot")) {
        try {
            Write-RSRInfo "Creating VSS snapshot for $Volume..."

            # Create shadow copy using WMI
            $shadow = (Get-WmiObject -List Win32_ShadowCopy).Create($Volume, "ClientAccessible")

            if ($shadow.ReturnValue -eq 0) {
                $shadowCopy = Get-WmiObject Win32_ShadowCopy | Where-Object { $_.ID -eq $shadow.ShadowID }

                $result = [PSCustomObject]@{
                    Id = $shadow.ShadowID
                    DeviceObject = $shadowCopy.DeviceObject
                    Volume = $Volume
                    Created = Get-Date
                }

                Write-RSROk "VSS snapshot created: $($result.Id)"
                return $result
            } else {
                Write-RSRError "Failed to create VSS snapshot. Return code: $($shadow.ReturnValue)"
                return $null
            }
        } catch {
            Write-RSRError "VSS snapshot failed: $_"
            return $null
        }
    }
}

function Remove-RSRVSSSnapshot {
    <#
    .SYNOPSIS
        Remove a VSS shadow copy
    .PARAMETER SnapshotId
        ID of the snapshot to remove
    .EXAMPLE
        Remove-RSRVSSSnapshot -SnapshotId '{GUID}'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$SnapshotId
    )

    if ($PSCmdlet.ShouldProcess($SnapshotId, "Remove VSS snapshot")) {
        try {
            $shadow = Get-WmiObject Win32_ShadowCopy | Where-Object { $_.ID -eq $SnapshotId }
            if ($shadow) {
                $shadow.Delete()
                Write-RSROk "VSS snapshot removed: $SnapshotId"
            } else {
                Write-RSRWarn "VSS snapshot not found: $SnapshotId"
            }
        } catch {
            Write-RSRError "Failed to remove VSS snapshot: $_"
        }
    }
}

function Get-RSRVSSSnapshots {
    <#
    .SYNOPSIS
        List all VSS shadow copies
    .EXAMPLE
        Get-RSRVSSSnapshots
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        $shadows = Get-WmiObject Win32_ShadowCopy
        return $shadows | ForEach-Object {
            [PSCustomObject]@{
                Id = $_.ID
                Volume = $_.VolumeName
                DeviceObject = $_.DeviceObject
                Created = [Management.ManagementDateTimeConverter]::ToDateTime($_.InstallDate)
                State = $_.State
            }
        }
    } catch {
        Write-RSRError "Failed to list VSS snapshots: $_"
        return @()
    }
}

# =============================================================================
# Windows File History
# =============================================================================

function Get-RSRFileHistoryStatus {
    <#
    .SYNOPSIS
        Get Windows File History status
    .EXAMPLE
        Get-RSRFileHistoryStatus
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    try {
        $fhConfig = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\FileHistory' -ErrorAction SilentlyContinue

        if ($fhConfig) {
            return [PSCustomObject]@{
                Enabled = $fhConfig.ProtectedUpToTime -ne $null
                TargetPath = $fhConfig.TargetUrl
                LastBackup = if ($fhConfig.ProtectedUpToTime) { [DateTime]::FromFileTime($fhConfig.ProtectedUpToTime) } else { $null }
            }
        }

        return [PSCustomObject]@{
            Enabled = $false
            TargetPath = $null
            LastBackup = $null
        }
    } catch {
        Write-RSRError "Failed to get File History status: $_"
        return $null
    }
}

# =============================================================================
# Backup Operations
# =============================================================================

function New-RSRBackup {
    <#
    .SYNOPSIS
        Create a backup using the specified tool
    .PARAMETER Tool
        Backup tool to use
    .PARAMETER Source
        Source path(s) to backup
    .PARAMETER Destination
        Backup destination
    .PARAMETER Exclude
        Patterns to exclude
    .PARAMETER UseVSS
        Use VSS snapshot for consistent backup (Windows only)
    .EXAMPLE
        New-RSRBackup -Tool restic -Source 'C:\Users' -Destination 'D:\Backups\repo'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$Tool,

        [Parameter(Mandatory)]
        [string[]]$Source,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter()]
        [string[]]$Exclude,

        [Parameter()]
        [switch]$UseVSS,

        [Parameter()]
        [string]$Password,

        [Parameter()]
        [hashtable]$Options
    )

    # Auto-detect tool if not specified
    if (-not $Tool) {
        $Tool = Get-RSRBackupDefaultTool
        if (-not $Tool) {
            Write-RSRError "No backup tool available. Install restic, rclone, or kopia."
            return $false
        }
        Write-RSRInfo "Using backup tool: $Tool"
    }

    if (-not (Test-RSRBackupToolInstalled -Tool $Tool)) {
        Write-RSRError "$Tool is not installed"
        return $false
    }

    # VSS snapshot for Windows
    $vssSnapshot = $null
    $actualSource = $Source

    if ($UseVSS -and ($IsWindows -or (-not $IsLinux -and -not $IsMacOS))) {
        $volume = Split-Path -Qualifier $Source[0]
        $vssSnapshot = New-RSRVSSSnapshot -Volume $volume
        if ($vssSnapshot) {
            # Mount shadow copy
            $actualSource = $Source | ForEach-Object {
                $relativePath = $_.Substring($volume.Length)
                "$($vssSnapshot.DeviceObject)$relativePath"
            }
        }
    }

    try {
        if ($PSCmdlet.ShouldProcess("$Source -> $Destination", "Create backup with $Tool")) {
            Write-RSRInfo "Creating backup with $Tool..."
            Write-RSRInfo "Source: $($actualSource -join ', ')"
            Write-RSRInfo "Destination: $Destination"

            $result = $false

            switch ($Tool) {
                'robocopy' {
                    $robocopyArgs = @('/MIR', '/R:3', '/W:5', '/MT:8', '/NP', '/NDL', '/NFL')
                    if ($Exclude) {
                        $robocopyArgs += '/XD'
                        $robocopyArgs += $Exclude
                    }

                    foreach ($src in $actualSource) {
                        $destPath = Join-Path $Destination (Split-Path $src -Leaf)
                        & robocopy $src $destPath @robocopyArgs
                        # Robocopy exit codes < 8 are success
                        if ($LASTEXITCODE -lt 8) { $result = $true }
                    }
                }
                'restic' {
                    $env:RESTIC_PASSWORD = $Password
                    $resticArgs = @('-r', $Destination, 'backup')

                    if ($Exclude) {
                        foreach ($pattern in $Exclude) {
                            $resticArgs += '--exclude'
                            $resticArgs += $pattern
                        }
                    }

                    $resticArgs += $actualSource
                    & restic @resticArgs
                    $result = $LASTEXITCODE -eq 0
                }
                'rclone' {
                    $rcloneArgs = @('sync', '--progress')

                    if ($Exclude) {
                        foreach ($pattern in $Exclude) {
                            $rcloneArgs += '--exclude'
                            $rcloneArgs += $pattern
                        }
                    }

                    foreach ($src in $actualSource) {
                        & rclone @rcloneArgs $src $Destination
                        if ($LASTEXITCODE -eq 0) { $result = $true }
                    }
                }
                'kopia' {
                    if ($Exclude) {
                        foreach ($pattern in $Exclude) {
                            & kopia policy set --global --add-ignore $pattern
                        }
                    }

                    foreach ($src in $actualSource) {
                        & kopia snapshot create $src
                        if ($LASTEXITCODE -eq 0) { $result = $true }
                    }
                }
                default {
                    Write-RSRError "Unknown tool: $Tool"
                    return $false
                }
            }

            if ($result) {
                Write-RSROk "Backup completed successfully"
            } else {
                Write-RSRError "Backup failed"
            }

            return $result
        }
    } finally {
        # Clean up VSS snapshot
        if ($vssSnapshot) {
            Remove-RSRVSSSnapshot -SnapshotId $vssSnapshot.Id
        }
    }
}

function Get-RSRBackupList {
    <#
    .SYNOPSIS
        List backups/snapshots
    .PARAMETER Tool
        Backup tool to use
    .PARAMETER Repository
        Backup repository path
    .EXAMPLE
        Get-RSRBackupList -Tool restic -Repository 'D:\Backups\repo'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,

        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter()]
        [string]$Password
    )

    if (-not (Test-RSRBackupToolInstalled -Tool $Tool)) {
        Write-RSRError "$Tool is not installed"
        return @()
    }

    switch ($Tool) {
        'robocopy' {
            Get-ChildItem -Path $Repository -Directory | Select-Object Name, LastWriteTime, @{N='Size';E={(Get-ChildItem $_.FullName -Recurse | Measure-Object -Property Length -Sum).Sum}}
        }
        'restic' {
            $env:RESTIC_PASSWORD = $Password
            $output = restic -r $Repository snapshots --json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $output | ConvertFrom-Json
            }
        }
        'rclone' {
            rclone lsf $Repository --dirs-only
        }
        'kopia' {
            kopia snapshot list --json | ConvertFrom-Json
        }
    }
}

function Restore-RSRBackup {
    <#
    .SYNOPSIS
        Restore from backup
    .PARAMETER Tool
        Backup tool to use
    .PARAMETER Repository
        Backup repository path
    .PARAMETER Target
        Restore target path
    .PARAMETER SnapshotId
        Specific snapshot to restore (optional)
    .EXAMPLE
        Restore-RSRBackup -Tool restic -Repository 'D:\Backups\repo' -Target 'C:\Restore'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,

        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter()]
        [string]$SnapshotId = 'latest',

        [Parameter()]
        [string]$Password
    )

    if (-not (Test-RSRBackupToolInstalled -Tool $Tool)) {
        Write-RSRError "$Tool is not installed"
        return $false
    }

    if ($PSCmdlet.ShouldProcess("$Repository -> $Target", "Restore backup")) {
        Write-RSRInfo "Restoring backup from $Tool..."

        switch ($Tool) {
            'robocopy' {
                & robocopy $Repository $Target /MIR /R:3 /W:5
                return $LASTEXITCODE -lt 8
            }
            'restic' {
                $env:RESTIC_PASSWORD = $Password
                & restic -r $Repository restore $SnapshotId --target $Target
                return $LASTEXITCODE -eq 0
            }
            'rclone' {
                & rclone sync $Repository $Target --progress
                return $LASTEXITCODE -eq 0
            }
            'kopia' {
                & kopia snapshot restore $SnapshotId $Target
                return $LASTEXITCODE -eq 0
            }
        }
    }
}

# =============================================================================
# Repository Management
# =============================================================================

function Initialize-RSRBackupRepository {
    <#
    .SYNOPSIS
        Initialize a backup repository
    .PARAMETER Tool
        Backup tool to use
    .PARAMETER Path
        Repository path
    .PARAMETER Password
        Encryption password
    .EXAMPLE
        Initialize-RSRBackupRepository -Tool restic -Path 'D:\Backups\repo'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$Password
    )

    if (-not (Test-RSRBackupToolInstalled -Tool $Tool)) {
        Write-RSRError "$Tool is not installed"
        return $false
    }

    if ($PSCmdlet.ShouldProcess($Path, "Initialize $Tool repository")) {
        Write-RSRInfo "Initializing $Tool repository at $Path..."

        switch ($Tool) {
            'restic' {
                $env:RESTIC_PASSWORD = $Password
                & restic init --repo $Path
                return $LASTEXITCODE -eq 0
            }
            'kopia' {
                if ($Password) {
                    & kopia repository create filesystem --path $Path --password $Password
                } else {
                    & kopia repository create filesystem --path $Path
                }
                return $LASTEXITCODE -eq 0
            }
            'robocopy' {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
                Write-RSROk "Created directory: $Path"
                return $true
            }
            'rclone' {
                New-Item -ItemType Directory -Path $Path -Force | Out-Null
                Write-RSROk "Created directory: $Path"
                return $true
            }
        }
    }
}

# =============================================================================
# Retention & Maintenance
# =============================================================================

function Invoke-RSRBackupPrune {
    <#
    .SYNOPSIS
        Apply retention policy to backups
    .PARAMETER Tool
        Backup tool to use
    .PARAMETER Repository
        Repository path
    .PARAMETER KeepDaily
        Number of daily backups to keep
    .PARAMETER KeepWeekly
        Number of weekly backups to keep
    .PARAMETER KeepMonthly
        Number of monthly backups to keep
    .EXAMPLE
        Invoke-RSRBackupPrune -Tool restic -Repository 'D:\Backups\repo' -KeepDaily 7
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,

        [Parameter(Mandatory)]
        [string]$Repository,

        [Parameter()]
        [int]$KeepDaily = 7,

        [Parameter()]
        [int]$KeepWeekly = 4,

        [Parameter()]
        [int]$KeepMonthly = 6,

        [Parameter()]
        [string]$Password
    )

    if ($PSCmdlet.ShouldProcess($Repository, "Prune backups")) {
        Write-RSRInfo "Applying retention policy..."

        switch ($Tool) {
            'restic' {
                $env:RESTIC_PASSWORD = $Password
                & restic -r $Repository forget `
                    --keep-daily $KeepDaily `
                    --keep-weekly $KeepWeekly `
                    --keep-monthly $KeepMonthly `
                    --prune
                return $LASTEXITCODE -eq 0
            }
            'kopia' {
                & kopia policy set --global `
                    --keep-daily $KeepDaily `
                    --keep-weekly $KeepWeekly `
                    --keep-monthly $KeepMonthly
                & kopia maintenance run --full
                return $LASTEXITCODE -eq 0
            }
            default {
                Write-RSRWarn "Retention not supported for $Tool"
                return $true
            }
        }
    }
}

# =============================================================================
# Profile Management
# =============================================================================

$Script:RSR_BACKUP_PROFILE_DIR = Join-Path $env:USERPROFILE '.config\rsr\backup\profiles'

function Get-RSRBackupProfiles {
    <#
    .SYNOPSIS
        List available backup profiles
    .EXAMPLE
        Get-RSRBackupProfiles
    #>
    [CmdletBinding()]
    param()

    if (Test-Path $Script:RSR_BACKUP_PROFILE_DIR) {
        Get-ChildItem -Path $Script:RSR_BACKUP_PROFILE_DIR -Filter '*.json' | ForEach-Object {
            $content = Get-Content $_.FullName | ConvertFrom-Json
            [PSCustomObject]@{
                Name = $_.BaseName
                Tool = $content.Tool
                Sources = $content.Sources
                Destination = $content.Destination
            }
        }
    }
}

function New-RSRBackupProfile {
    <#
    .SYNOPSIS
        Create a backup profile
    .PARAMETER Name
        Profile name
    .PARAMETER Tool
        Backup tool to use
    .PARAMETER Sources
        Source paths
    .PARAMETER Destination
        Backup destination
    .PARAMETER Excludes
        Patterns to exclude
    .EXAMPLE
        New-RSRBackupProfile -Name 'daily' -Tool restic -Sources 'C:\Users' -Destination 'D:\Backups'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Tool,

        [Parameter(Mandatory)]
        [string[]]$Sources,

        [Parameter(Mandatory)]
        [string]$Destination,

        [Parameter()]
        [string[]]$Excludes,

        [Parameter()]
        [int]$KeepDaily = 7,

        [Parameter()]
        [int]$KeepWeekly = 4,

        [Parameter()]
        [int]$KeepMonthly = 6
    )

    if (-not (Test-Path $Script:RSR_BACKUP_PROFILE_DIR)) {
        New-Item -ItemType Directory -Path $Script:RSR_BACKUP_PROFILE_DIR -Force | Out-Null
    }

    $profile = @{
        Tool = $Tool
        Sources = $Sources
        Destination = $Destination
        Excludes = $Excludes
        Retention = @{
            KeepDaily = $KeepDaily
            KeepWeekly = $KeepWeekly
            KeepMonthly = $KeepMonthly
        }
        Created = Get-Date -Format 'o'
    }

    $profilePath = Join-Path $Script:RSR_BACKUP_PROFILE_DIR "$Name.json"
    $profile | ConvertTo-Json -Depth 5 | Set-Content -Path $profilePath

    Write-RSROk "Created profile: $Name"
}

function Invoke-RSRBackupProfile {
    <#
    .SYNOPSIS
        Run a backup using a saved profile
    .PARAMETER Name
        Profile name
    .EXAMPLE
        Invoke-RSRBackupProfile -Name 'daily'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        [string]$Password
    )

    $profilePath = Join-Path $Script:RSR_BACKUP_PROFILE_DIR "$Name.json"

    if (-not (Test-Path $profilePath)) {
        Write-RSRError "Profile not found: $Name"
        return $false
    }

    $profile = Get-Content $profilePath | ConvertFrom-Json

    Write-RSRInfo "Running backup profile: $Name"

    $result = New-RSRBackup `
        -Tool $profile.Tool `
        -Source $profile.Sources `
        -Destination $profile.Destination `
        -Exclude $profile.Excludes `
        -Password $Password

    return $result
}

# =============================================================================
# Scheduling
# =============================================================================

function New-RSRBackupScheduledTask {
    <#
    .SYNOPSIS
        Create a Windows scheduled task for backup
    .PARAMETER Name
        Task name
    .PARAMETER Profile
        Backup profile to run
    .PARAMETER Time
        Time to run (e.g., "02:00")
    .PARAMETER Daily
        Run daily
    .EXAMPLE
        New-RSRBackupScheduledTask -Name 'DailyBackup' -Profile 'daily' -Time '02:00' -Daily
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Profile,

        [Parameter()]
        [string]$Time = '02:00',

        [Parameter()]
        [switch]$Daily
    )

    if ($PSCmdlet.ShouldProcess($Name, "Create scheduled task")) {
        $action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -Command `"Import-Module RSR; Invoke-RSRBackupProfile -Name '$Profile'`""

        if ($Daily) {
            $trigger = New-ScheduledTaskTrigger -Daily -At $Time
        } else {
            $trigger = New-ScheduledTaskTrigger -Once -At $Time
        }

        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

        Register-ScheduledTask -TaskName "RSR-Backup-$Name" -Action $action -Trigger $trigger -Settings $settings -Description "RSR Backup: $Profile"

        Write-RSROk "Created scheduled task: RSR-Backup-$Name"
    }
}

# =============================================================================
# Export
# =============================================================================

Export-ModuleMember -Function @(
    'Test-RSRBackupToolInstalled',
    'Get-RSRBackupToolVersion',
    'Get-RSRBackupTools',
    'Get-RSRBackupDefaultTool',
    'New-RSRVSSSnapshot',
    'Remove-RSRVSSSnapshot',
    'Get-RSRVSSSnapshots',
    'Get-RSRFileHistoryStatus',
    'New-RSRBackup',
    'Get-RSRBackupList',
    'Restore-RSRBackup',
    'Initialize-RSRBackupRepository',
    'Invoke-RSRBackupPrune',
    'Get-RSRBackupProfiles',
    'New-RSRBackupProfile',
    'Invoke-RSRBackupProfile',
    'New-RSRBackupScheduledTask'
)

