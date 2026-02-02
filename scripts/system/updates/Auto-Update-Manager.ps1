<#
.SYNOPSIS
    Windows Auto Update Manager - Install, configure, and manage automated system updates

.DESCRIPTION
    Comprehensive auto-update management for Windows supporting:
    - Windows Task Scheduler integration
    - winget, Chocolatey, and Windows Update
    - Flexible scheduling (daily, weekly, monthly)
    - Email notifications
    - Security-only updates

.PARAMETER Command
    The command to execute: install, remove, status, enable, disable, run-now, logs, config

.PARAMETER Schedule
    Update frequency: daily, weekly, monthly (default: daily)

.PARAMETER Time
    Time to run updates in HH:MM format (default: 02:00)

.PARAMETER DayOfWeek
    Day for weekly schedule: Sunday-Saturday or 0-6 (default: Sunday)

.PARAMETER SecurityOnly
    Only install security updates

.PARAMETER Reboot
    Reboot behavior: never, if-needed, always (default: never)

.PARAMETER IncludeLanguage
    Include language package managers (pip, npm, cargo, gem)

.PARAMETER NotifyEmail
    Email address for notifications

.PARAMETER UseWindowsUpdate
    Include Windows Update (requires admin)

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER UserInstall
    Install for current user only (no admin required)

.EXAMPLE
    .\Auto-Update-Manager.ps1 install
    Install with default settings (daily at 2am)

.EXAMPLE
    .\Auto-Update-Manager.ps1 install -Schedule weekly -DayOfWeek Sunday -Time "03:00"
    Install weekly updates on Sunday at 3am

.EXAMPLE
    .\Auto-Update-Manager.ps1 status
    Check current configuration and status

.EXAMPLE
    .\Auto-Update-Manager.ps1 run-now
    Trigger immediate update

.EXAMPLE
    .\Auto-Update-Manager.ps1
    Run in interactive mode (no arguments)

.NOTES
    Version: 1.0.0
    Author: codefuturist
    Platform: Windows (PowerShell 5.1+)
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Position = 0)]
    [ValidateSet('install', 'remove', 'status', 'enable', 'disable', 'run-now', 'logs', 'config', 'help', '')]
    [string]$Command = '',

    [Alias('i')]
    [switch]$Interactive,

    [ValidateSet('daily', 'weekly', 'monthly')]
    [string]$Schedule = 'daily',

    [ValidatePattern('^([01]?[0-9]|2[0-3]):[0-5][0-9]$')]
    [string]$Time = '02:00',

    [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', '0', '1', '2', '3', '4', '5', '6')]
    [string]$DayOfWeek = 'Sunday',

    [switch]$SecurityOnly,

    [ValidateSet('never', 'if-needed', 'always')]
    [string]$Reboot = 'never',

    [switch]$IncludeLanguage,

    [string]$NotifyEmail,

    [switch]$UseWindowsUpdate,

    [switch]$Force,

    [switch]$UserInstall,

    [int]$TailLines = 50
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "1.0.0"
$ScriptName = "Auto Update Manager"

# =============================================================================
# Configuration
# =============================================================================

$TaskName = "RSR-Auto-Update"
$TaskPath = "\RSR\"
$ConfigDir = "$env:ProgramData\rsr"
$ConfigFile = "$ConfigDir\auto-update.json"
$LogDir = "$ConfigDir\logs"
$LogFile = "$LogDir\auto-update.log"

# User-level paths
$UserConfigDir = "$env:APPDATA\rsr"
$UserConfigFile = "$UserConfigDir\auto-update.json"
$UserLogDir = "$UserConfigDir\logs"
$UserLogFile = "$UserLogDir\auto-update.log"

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$UpdateScript = Join-Path $ScriptDir "System-Update.ps1"

# =============================================================================
# Helper Functions
# =============================================================================

function Write-Header {
    param([string]$Text)
    Write-Host "`n$Text" -ForegroundColor Cyan -NoNewline
    Write-Host " v$ScriptVersion" -ForegroundColor Gray
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

function Write-Info {
    param([string]$Message)
    Write-Host "  i  " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "  +  " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warning2 {
    param([string]$Message)
    Write-Host "  !  " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error2 {
    param([string]$Message)
    Write-Host "  x  " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Write-Step {
    param([string]$Message)
    Write-Host "  -> " -ForegroundColor Cyan -NoNewline
    Write-Host $Message
}

function Write-Dim {
    param([string]$Message)
    Write-Host "     $Message" -ForegroundColor DarkGray
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    if (-not (Test-Administrator)) {
        Write-Error2 "This operation requires administrator privileges"
        Write-Dim "Run PowerShell as Administrator"
        exit 3
    }
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Dim "Created directory: $Path"
    }
}

# =============================================================================
# Interactive Mode Functions
# =============================================================================

function Write-BoxHeader {
    param([string]$Title)
    $width = 60
    $padding = [Math]::Floor(($width - $Title.Length - 2) / 2)
    
    Write-Host ""
    Write-Host ("+" + ("-" * $width) + "+") -ForegroundColor Cyan
    Write-Host ("|" + (" " * $padding) + $Title + (" " * ($width - $padding - $Title.Length)) + "|") -ForegroundColor Cyan
    Write-Host ("+" + ("-" * $width) + "+") -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host $Title -ForegroundColor White
    Write-Host ("-" * $Title.Length) -ForegroundColor DarkGray
}

function Read-YesNo {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )
    
    $defaultText = if ($Default) { "[Y/n]" } else { "[y/N]" }
    Write-Host "  ?  " -ForegroundColor Cyan -NoNewline
    Write-Host "$Prompt " -NoNewline
    Write-Host $defaultText -ForegroundColor DarkGray -NoNewline
    Write-Host " " -NoNewline
    
    $response = Read-Host
    if ([string]::IsNullOrEmpty($response)) {
        return $Default
    }
    return $response.ToLower() -in @('y', 'yes')
}

function Read-Value {
    param(
        [string]$Prompt,
        [string]$Default
    )
    
    Write-Host "  ?  " -ForegroundColor Cyan -NoNewline
    Write-Host "$Prompt " -NoNewline
    Write-Host "[$Default]" -ForegroundColor DarkGray -NoNewline
    Write-Host " " -NoNewline
    
    $response = Read-Host
    if ([string]::IsNullOrEmpty($response)) {
        return $Default
    }
    return $response
}

function Show-Menu {
    param(
        [string]$Prompt,
        [string[]]$Options
    )
    
    Write-Host "  ?  " -ForegroundColor Cyan -NoNewline
    Write-Host $Prompt
    Write-Host ""
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "  " -NoNewline
        Write-Host "$($i + 1)" -ForegroundColor Cyan -NoNewline
        Write-Host ") $($Options[$i])"
    }
    
    Write-Host ""
    while ($true) {
        Write-Host "     Enter choice [1-$($Options.Count)]: " -ForegroundColor DarkGray -NoNewline
        $choice = Read-Host
        
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $Options.Count) {
            return [int]$choice - 1
        }
        Write-Host "     Invalid choice" -ForegroundColor Red
    }
}

function Read-Time {
    param(
        [string]$Prompt,
        [string]$Default
    )
    
    while ($true) {
        $result = Read-Value -Prompt "$Prompt (HH:MM)" -Default $Default
        if ($result -match '^([01]?[0-9]|2[0-3]):[0-5][0-9]$') {
            $parts = $result.Split(':')
            return "{0:D2}:{1:D2}" -f [int]$parts[0], [int]$parts[1]
        }
        Write-Error2 "Invalid time format. Use HH:MM (e.g., 02:00, 14:30)"
    }
}

function Show-InteractiveInstall {
    Write-BoxHeader "Auto Update Manager Setup"
    
    Write-Host "  Platform:        " -NoNewline -ForegroundColor DarkGray
    Write-Host "Windows"
    Write-Host "  PowerShell:      " -NoNewline -ForegroundColor DarkGray
    Write-Host $PSVersionTable.PSVersion
    Write-Host ""
    
    # Check existing installation
    if (Test-TaskInstalled) {
        Write-Warning2 "Auto-updates are already configured"
        Write-Host ""
        if (-not (Read-YesNo -Prompt "Do you want to reconfigure?" -Default $false)) {
            Write-Host ""
            Write-Info "Keeping existing configuration"
            return $null
        }
        $script:Force = $true
    }
    
    $config = @{}
    
    Write-Section "Update Schedule"
    
    # Schedule selection
    $schedules = @(
        "Daily - Run updates every day",
        "Weekly - Run updates once a week",
        "Monthly - Run updates once a month"
    )
    $schedIdx = Show-Menu -Prompt "How often should updates run?" -Options $schedules
    
    $config.Schedule = @('daily', 'weekly', 'monthly')[$schedIdx]
    Write-Success "Schedule: $($config.Schedule)"
    
    # Time selection
    Write-Host ""
    $config.Time = Read-Time -Prompt "What time should updates run?" -Default "02:00"
    Write-Success "Time: $($config.Time)"
    
    # Day selection for weekly
    if ($config.Schedule -eq 'weekly') {
        Write-Host ""
        $days = @("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
        $dayIdx = Show-Menu -Prompt "Which day of the week?" -Options $days
        $config.DayOfWeek = $days[$dayIdx]
        Write-Success "Day: $($config.DayOfWeek)"
    } else {
        $config.DayOfWeek = 'Sunday'
    }
    
    Write-Section "Update Options"
    
    # Security only - not really applicable to Windows the same way
    Write-Host ""
    $config.SecurityOnly = $false
    Write-Info "Note: Windows Update handles security classifications automatically"
    
    # Language packages
    Write-Host ""
    $config.IncludeLanguage = Read-YesNo -Prompt "Include language packages (pip, npm, cargo, gem)?" -Default $false
    Write-Success "Language packages: $($config.IncludeLanguage)"
    
    # Windows Update
    Write-Host ""
    $config.UseWindowsUpdate = Read-YesNo -Prompt "Include Windows Update? (requires admin)" -Default $false
    Write-Success "Windows Update: $($config.UseWindowsUpdate)"
    
    # Reboot behavior
    Write-Host ""
    $rebootOptions = @(
        "Never - Never automatically reboot",
        "If needed - Reboot only when required",
        "Always - Always reboot after updates"
    )
    $rebootIdx = Show-Menu -Prompt "Automatic reboot after updates?" -Options $rebootOptions
    $config.Reboot = @('never', 'if-needed', 'always')[$rebootIdx]
    Write-Success "Reboot: $($config.Reboot)"
    
    # Email notifications
    Write-Section "Notifications"
    Write-Host ""
    if (Read-YesNo -Prompt "Enable email notifications on failure?" -Default $false) {
        $config.NotifyEmail = Read-Value -Prompt "Email address" -Default "admin@localhost"
        Write-Success "Notifications: $($config.NotifyEmail)"
    } else {
        $config.NotifyEmail = ''
        Write-Success "Notifications: Disabled"
    }
    
    # Summary
    Write-Section "Summary"
    Write-Host ""
    Write-Host "  Schedule:        " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($config.Schedule) at $($config.Time)"
    if ($config.Schedule -eq 'weekly') {
        Write-Host "  Day:             " -NoNewline -ForegroundColor DarkGray
        Write-Host $config.DayOfWeek
    }
    Write-Host "  Languages:       " -NoNewline -ForegroundColor DarkGray
    Write-Host $config.IncludeLanguage
    Write-Host "  Windows Update:  " -NoNewline -ForegroundColor DarkGray
    Write-Host $config.UseWindowsUpdate
    Write-Host "  Reboot:          " -NoNewline -ForegroundColor DarkGray
    Write-Host $config.Reboot
    Write-Host "  Notifications:   " -NoNewline -ForegroundColor DarkGray
    Write-Host $(if ($config.NotifyEmail) { $config.NotifyEmail } else { "none" })
    Write-Host ""
    
    if (-not (Read-YesNo -Prompt "Proceed with installation?" -Default $true)) {
        Write-Host ""
        Write-Warning2 "Installation cancelled"
        return $null
    }
    
    Write-Host ""
    return $config
}

function Show-InteractiveMenu {
    Write-BoxHeader "Auto Update Manager"
    
    $installed = Test-TaskInstalled
    $enabled = Test-TaskEnabled
    
    # Show current status
    if ($installed) {
        Write-Host "  " -NoNewline
        Write-Host "●" -ForegroundColor Green -NoNewline
        Write-Host " Auto-updates are " -NoNewline
        Write-Host "installed" -ForegroundColor Green
        
        Write-Host "  " -NoNewline
        if ($enabled) {
            Write-Host "●" -ForegroundColor Green -NoNewline
            Write-Host " Status: " -NoNewline
            Write-Host "Enabled" -ForegroundColor Green
        } else {
            Write-Host "○" -ForegroundColor Yellow -NoNewline
            Write-Host " Status: " -NoNewline
            Write-Host "Disabled" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  " -NoNewline
        Write-Host "○" -ForegroundColor DarkGray -NoNewline
        Write-Host " Auto-updates are " -NoNewline
        Write-Host "not installed" -ForegroundColor DarkGray
    }
    Write-Host ""
    
    # Build menu options
    $options = @()
    $actions = @()
    
    if (-not $installed) {
        $options += "Install auto-updates"
        $actions += "install"
    } else {
        $options += "Reconfigure auto-updates"
        $actions += "install"
        
        if ($enabled) {
            $options += "Disable auto-updates"
            $actions += "disable"
        } else {
            $options += "Enable auto-updates"
            $actions += "enable"
        }
        
        $options += "Run update now"
        $actions += "run-now"
        
        $options += "View logs"
        $actions += "logs"
        
        $options += "Show configuration"
        $actions += "config"
        
        $options += "Remove auto-updates"
        $actions += "remove"
    }
    
    $options += "Exit"
    $actions += "exit"
    
    $choice = Show-Menu -Prompt "What would you like to do?" -Options $options
    
    return $actions[$choice]
}

function Show-InteractiveRemove {
    Write-BoxHeader "Remove Auto-Updates"
    
    if (-not (Test-TaskInstalled)) {
        Write-Warning2 "Auto-updates are not installed"
        return $false
    }
    
    Write-Warning2 "This will remove all auto-update configuration"
    Write-Host ""
    
    return (Read-YesNo -Prompt "Are you sure you want to remove auto-updates?" -Default $false)
}

function ConvertTo-DayOfWeekEnum {
    param([string]$Day)
    switch ($Day.ToLower()) {
        '0' { return [DayOfWeek]::Sunday }
        '1' { return [DayOfWeek]::Monday }
        '2' { return [DayOfWeek]::Tuesday }
        '3' { return [DayOfWeek]::Wednesday }
        '4' { return [DayOfWeek]::Thursday }
        '5' { return [DayOfWeek]::Friday }
        '6' { return [DayOfWeek]::Saturday }
        'sunday' { return [DayOfWeek]::Sunday }
        'monday' { return [DayOfWeek]::Monday }
        'tuesday' { return [DayOfWeek]::Tuesday }
        'wednesday' { return [DayOfWeek]::Wednesday }
        'thursday' { return [DayOfWeek]::Thursday }
        'friday' { return [DayOfWeek]::Friday }
        'saturday' { return [DayOfWeek]::Saturday }
        default { return [DayOfWeek]::Sunday }
    }
}

# =============================================================================
# Configuration Management
# =============================================================================

function Get-DefaultConfig {
    return @{
        Schedule = 'daily'
        Time = '02:00'
        DayOfWeek = 'Sunday'
        SecurityOnly = $false
        Reboot = 'never'
        IncludeLanguage = $false
        NotifyEmail = ''
        UseWindowsUpdate = $false
        UserInstall = $false
        InstalledAt = (Get-Date -Format 'o')
    }
}

function Load-Config {
    $configPath = if ($UserInstall -or -not (Test-Administrator)) { $UserConfigFile } else { $ConfigFile }
    
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            return $config
        } catch {
            Write-Warning2 "Failed to load config, using defaults"
        }
    }
    
    return Get-DefaultConfig
}

function Save-Config {
    param([hashtable]$Config)
    
    $configPath = if ($Config.UserInstall -or -not (Test-Administrator)) { $UserConfigFile } else { $ConfigFile }
    $configDir = Split-Path $configPath -Parent
    
    Ensure-Directory $configDir
    
    $Config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
    Write-Success "Configuration saved to $configPath"
}

function Show-Config {
    Write-Host "`nCurrent Configuration" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    
    $config = Load-Config
    
    Write-Host "  Schedule:           " -NoNewline; Write-Host $config.Schedule -ForegroundColor Cyan
    Write-Host "  Time:               " -NoNewline; Write-Host $config.Time -ForegroundColor Cyan
    if ($config.Schedule -eq 'weekly') {
        Write-Host "  Day:                " -NoNewline; Write-Host $config.DayOfWeek -ForegroundColor Cyan
    }
    Write-Host "  Security Only:      " -NoNewline; Write-Host $config.SecurityOnly -ForegroundColor Cyan
    Write-Host "  Include Languages:  " -NoNewline; Write-Host $config.IncludeLanguage -ForegroundColor Cyan
    Write-Host "  Windows Update:     " -NoNewline; Write-Host $config.UseWindowsUpdate -ForegroundColor Cyan
    Write-Host "  Reboot Mode:        " -NoNewline; Write-Host $config.Reboot -ForegroundColor Cyan
    Write-Host "  Notifications:      " -NoNewline
    if ($config.NotifyEmail) {
        Write-Host $config.NotifyEmail -ForegroundColor Cyan
    } else {
        Write-Host "none" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# =============================================================================
# Task Scheduler Functions
# =============================================================================

function Test-TaskInstalled {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        return $null -ne $task
    } catch {
        return $false
    }
}

function Test-TaskEnabled {
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        return $task -and $task.State -ne 'Disabled'
    } catch {
        return $false
    }
}

function Install-UpdateTask {
    Write-Step "Installing scheduled task..."
    
    if (-not (Test-Path $UpdateScript)) {
        Write-Error2 "Update script not found: $UpdateScript"
        exit 1
    }
    
    $logPath = if ($UserInstall) { $UserLogDir } else { $LogDir }
    Ensure-Directory $logPath
    
    # Parse time
    $timeParts = $Time.Split(':')
    $hour = [int]$timeParts[0]
    $minute = [int]$timeParts[1]
    
    # Build arguments
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$UpdateScript`"", '-All', '-Force')
    
    if ($IncludeLanguage) {
        $arguments += '-IncludeLanguage'
    }
    
    if ($UseWindowsUpdate) {
        $arguments += '-IncludeWindowsUpdate'
    }
    
    $argumentString = $arguments -join ' '
    
    # Create action
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentString
    
    # Create trigger based on schedule
    switch ($Schedule) {
        'daily' {
            $trigger = New-ScheduledTaskTrigger -Daily -At "${hour}:${minute}"
        }
        'weekly' {
            $dayEnum = ConvertTo-DayOfWeekEnum $DayOfWeek
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $dayEnum -At "${hour}:${minute}"
        }
        'monthly' {
            # Monthly on the 1st
            $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -WeeksInterval 4 -At "${hour}:${minute}"
            # Note: True monthly requires more complex setup, using ~monthly approximation
        }
    }
    
    # Add random delay to prevent thundering herd
    $trigger.RandomDelay = 'PT15M'
    
    # Settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)
    
    # Principal (run as SYSTEM for system install, current user for user install)
    if ($UserInstall) {
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited
    } else {
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    }
    
    # Create or update task
    try {
        $existingTask = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        if ($existingTask) {
            Set-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
            Write-Success "Updated scheduled task"
        } else {
            # Ensure task folder exists
            $scheduleService = New-Object -ComObject Schedule.Service
            $scheduleService.Connect()
            $rootFolder = $scheduleService.GetFolder('\')
            try {
                $rootFolder.GetFolder('RSR') | Out-Null
            } catch {
                $rootFolder.CreateFolder('RSR') | Out-Null
            }
            
            Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $action -Trigger $trigger -Settings $settings -Principal $principal | Out-Null
            Write-Success "Created scheduled task"
        }
    } catch {
        Write-Error2 "Failed to create scheduled task: $_"
        exit 1
    }
    
    Write-Dim "Task: $TaskPath$TaskName"
    Write-Dim "Schedule: $Schedule at $Time"
}

function Remove-UpdateTask {
    Write-Step "Removing scheduled task..."
    
    try {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue
        Write-Success "Scheduled task removed"
    } catch {
        Write-Warning2 "Task may not exist or could not be removed"
    }
    
    # Clean up config
    if (Test-Path $ConfigFile) {
        Remove-Item $ConfigFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $UserConfigFile) {
        Remove-Item $UserConfigFile -Force -ErrorAction SilentlyContinue
    }
}

function Enable-UpdateTask {
    Write-Step "Enabling scheduled task..."
    
    if (-not (Test-TaskInstalled)) {
        Write-Error2 "Auto-updates not installed"
        Write-Dim "Run '$($MyInvocation.MyCommand.Name) install' first"
        exit 4
    }
    
    try {
        Enable-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath | Out-Null
        Write-Success "Auto-updates enabled"
    } catch {
        Write-Error2 "Failed to enable task: $_"
        exit 1
    }
}

function Disable-UpdateTask {
    Write-Step "Disabling scheduled task..."
    
    if (-not (Test-TaskInstalled)) {
        Write-Error2 "Auto-updates not installed"
        exit 4
    }
    
    try {
        Disable-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath | Out-Null
        Write-Success "Auto-updates disabled (configuration preserved)"
        Write-Dim "Run 'enable' to re-enable"
    } catch {
        Write-Error2 "Failed to disable task: $_"
        exit 1
    }
}

# =============================================================================
# Status and Control
# =============================================================================

function Show-Status {
    Write-Host "`nStatus" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    
    $installed = Test-TaskInstalled
    $enabled = Test-TaskEnabled
    
    Write-Host "  Installed:          " -NoNewline
    if ($installed) {
        Write-Host "Yes" -ForegroundColor Green
    } else {
        Write-Host "No" -ForegroundColor Red
        Write-Host ""
        Write-Dim "Run '$($MyInvocation.MyCommand.Name) install' to set up automatic updates"
        return
    }
    
    Write-Host "  Enabled:            " -NoNewline
    if ($enabled) {
        Write-Host "Yes" -ForegroundColor Green
    } else {
        Write-Host "No (disabled)" -ForegroundColor Yellow
    }
    
    Write-Host "  Method:             " -NoNewline
    Write-Host "Windows Task Scheduler" -ForegroundColor Cyan
    
    # Get next run time
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        if ($task) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
            if ($taskInfo.NextRunTime) {
                Write-Host "  Next Run:           " -NoNewline
                Write-Host $taskInfo.NextRunTime.ToString('yyyy-MM-dd HH:mm') -ForegroundColor Cyan
            }
            if ($taskInfo.LastRunTime -and $taskInfo.LastRunTime -ne [DateTime]::MinValue) {
                Write-Host "  Last Run:           " -NoNewline
                Write-Host $taskInfo.LastRunTime.ToString('yyyy-MM-dd HH:mm') -ForegroundColor DarkGray
                
                Write-Host "  Last Result:        " -NoNewline
                $resultCode = $taskInfo.LastTaskResult
                if ($resultCode -eq 0) {
                    Write-Host "Success (0)" -ForegroundColor Green
                } elseif ($resultCode -eq 267009) {
                    Write-Host "Running" -ForegroundColor Yellow
                } else {
                    Write-Host "Error ($resultCode)" -ForegroundColor Red
                }
            }
        }
    } catch {
        Write-Dim "Could not retrieve task info"
    }
    
    Write-Host ""
}

function Invoke-UpdateNow {
    Write-Step "Running system update now..."
    Write-Host ""
    
    if (-not (Test-Path $UpdateScript)) {
        Write-Error2 "Update script not found: $UpdateScript"
        exit 1
    }
    
    $config = Load-Config
    
    $arguments = @('-All', '-Force')
    
    if ($config.IncludeLanguage) {
        $arguments += '-IncludeLanguage'
    }
    
    if ($config.UseWindowsUpdate) {
        $arguments += '-IncludeWindowsUpdate'
    }
    
    & $UpdateScript @arguments
}

function Show-Logs {
    $logPath = if (Test-Path $LogFile) { $LogFile } elseif (Test-Path $UserLogFile) { $UserLogFile } else { $null }
    
    if (-not $logPath) {
        Write-Warning2 "No log file found"
        Write-Dim "Logs will appear after the first scheduled update run"
        
        # Check Windows Event Log for task scheduler events
        Write-Host "`nRecent Task Scheduler Events:" -ForegroundColor White
        try {
            Get-WinEvent -FilterHashtable @{
                LogName = 'Microsoft-Windows-TaskScheduler/Operational'
                Level = 1,2,3,4
            } -MaxEvents 10 -ErrorAction SilentlyContinue | 
            Where-Object { $_.Message -like "*RSR*" -or $_.Message -like "*Auto-Update*" } |
            Format-Table TimeCreated, Message -AutoSize
        } catch {
            Write-Dim "No recent events found"
        }
        return
    }
    
    Write-Host "Update Logs " -ForegroundColor White -NoNewline
    Write-Host "($logPath)" -ForegroundColor DarkGray
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Host ""
    
    Get-Content $logPath -Tail $TailLines
}

function Show-Help {
    @"
$ScriptName v$ScriptVersion

Install, configure, and manage automated system updates on Windows.

USAGE:
    .\Auto-Update-Manager.ps1                  # Interactive mode
    .\Auto-Update-Manager.ps1 -Interactive     # Force interactive mode
    .\Auto-Update-Manager.ps1 <command> [options]

COMMANDS:
    install         Install and configure automatic updates
    remove          Remove automatic update configuration
    status          Show current configuration and status
    enable          Enable scheduled updates
    disable         Disable updates (keep configuration)
    run-now         Trigger an immediate update
    logs            Show update history and logs
    config          Show current configuration
    help            Show this help message

OPTIONS:
    -Interactive    Run in interactive mode with guided setup
    -Schedule       Update frequency: daily, weekly, monthly (default: daily)
    -Time           Time to run updates HH:MM (default: 02:00)
    -DayOfWeek      Day for weekly schedule (default: Sunday)
    -SecurityOnly   Only install security updates
    -Reboot         Reboot behavior: never, if-needed, always
    -IncludeLanguage Include language package managers
    -UseWindowsUpdate Include Windows Update
    -NotifyEmail    Email address for notifications
    -Force          Skip confirmation prompts
    -UserInstall    Install for current user only

EXAMPLES:
    # Interactive setup wizard (recommended)
    .\Auto-Update-Manager.ps1

    # Install with defaults (daily at 2am)
    .\Auto-Update-Manager.ps1 install

    # Install weekly updates on Sunday at 3am
    .\Auto-Update-Manager.ps1 install -Schedule weekly -DayOfWeek Sunday -Time "03:00"

    # Check current status
    .\Auto-Update-Manager.ps1 status

    # View recent logs
    .\Auto-Update-Manager.ps1 logs -TailLines 100

    # Disable temporarily
    .\Auto-Update-Manager.ps1 disable

    # Run update now
    .\Auto-Update-Manager.ps1 run-now

"@ | Write-Host
}

# =============================================================================
# Main Installation Logic
# =============================================================================

function Invoke-Install {
    Write-Header "Installing Auto-Updates"
    Write-Host ""
    
    Write-Info "Platform: Windows"
    Write-Info "Method: Task Scheduler"
    Write-Host ""
    
    # Check if already installed
    if ((Test-TaskInstalled) -and -not $Force) {
        Write-Warning2 "Auto-updates already configured"
        Write-Dim "Use -Force to reconfigure, or run 'remove' first"
        exit 5
    }
    
    if (Test-TaskInstalled) {
        Write-Warning2 "Reconfiguring existing installation..."
        Remove-UpdateTask
    }
    
    # Build and save config
    $config = @{
        Schedule = $Schedule
        Time = $Time
        DayOfWeek = $DayOfWeek
        SecurityOnly = [bool]$SecurityOnly
        Reboot = $Reboot
        IncludeLanguage = [bool]$IncludeLanguage
        NotifyEmail = $NotifyEmail
        UseWindowsUpdate = [bool]$UseWindowsUpdate
        UserInstall = [bool]$UserInstall
        InstalledAt = (Get-Date -Format 'o')
    }
    
    Save-Config $config
    
    # Install task
    Install-UpdateTask
    
    Write-Host ""
    Write-Success "Auto-updates installed successfully!"
    Write-Host ""
    
    Show-Config
    Show-Status
}

function Invoke-Remove {
    Write-Header "Removing Auto-Updates"
    Write-Host ""
    
    Remove-UpdateTask
    
    Write-Host ""
    Write-Success "Auto-updates removed"
}

# =============================================================================
# Main Entry Point
# =============================================================================

# Handle interactive mode
$InteractiveMode = $Interactive -or ([string]::IsNullOrEmpty($Command))

if ($InteractiveMode -and [string]::IsNullOrEmpty($Command)) {
    $Command = Show-InteractiveMenu
    if ($Command -eq 'exit') {
        Write-Host ""
        Write-Info "Goodbye!"
        exit 0
    }
    if ($Command -eq 'install') {
        $InteractiveMode = $true
    }
}

# Interactive install wizard
if ($InteractiveMode -and $Command -eq 'install') {
    $config = Show-InteractiveInstall
    if ($null -eq $config) {
        exit 0
    }
    # Apply config from wizard
    $Schedule = $config.Schedule
    $Time = $config.Time
    $DayOfWeek = $config.DayOfWeek
    $SecurityOnly = $config.SecurityOnly
    $IncludeLanguage = $config.IncludeLanguage
    $UseWindowsUpdate = $config.UseWindowsUpdate
    $Reboot = $config.Reboot
    $NotifyEmail = $config.NotifyEmail
}

# Interactive remove confirmation
if ($InteractiveMode -and $Command -eq 'remove' -and -not $Force) {
    if (-not (Show-InteractiveRemove)) {
        Write-Host ""
        Write-Info "Removal cancelled"
        exit 0
    }
    Write-Host ""
}

switch ($Command.ToLower()) {
    'install' {
        if (-not $UserInstall) {
            Require-Administrator
        }
        Invoke-Install
    }
    'remove' {
        Require-Administrator
        Invoke-Remove
    }
    'status' {
        Show-Config
        Show-Status
    }
    'enable' {
        Require-Administrator
        Enable-UpdateTask
    }
    'disable' {
        Require-Administrator
        Disable-UpdateTask
    }
    'run-now' {
        Require-Administrator
        Invoke-UpdateNow
    }
    'logs' {
        Show-Logs
    }
    'config' {
        Show-Config
    }
    'help' {
        Show-Help
    }
    default {
        Show-Help
    }
}
