#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Logger Module

.DESCRIPTION
    Structured logging with levels, colors, and file output.
    Supports console and file logging with JSON format option.
#>

using namespace System.IO

# Strict mode
Set-StrictMode -Version Latest

#region Configuration

# Log levels (higher = more verbose)
enum LogLevel {
    SILENT = 0
    ERROR = 1
    WARN = 2
    INFO = 3
    DEBUG = 4
    TRACE = 5
}

# Module-level state
$script:LogLevel = [LogLevel]::INFO
$script:LogFile = $null
$script:LogToFile = $false
$script:LogJson = $false
$script:LogTimestamp = $true
$script:LogColors = @{
    ERROR = 'Red'
    WARN  = 'Yellow'
    INFO  = 'Cyan'
    DEBUG = 'Gray'
    TRACE = 'DarkGray'
    SUCCESS = 'Green'
    HEADER = 'Magenta'
}

#endregion

#region Initialization

function Initialize-Logger {
    <#
    .SYNOPSIS
        Initializes the logging system.
    #>
    param(
        [LogLevel]$Level = [LogLevel]::INFO,
        [string]$LogPath,
        [switch]$JsonOutput,
        [switch]$NoTimestamp
    )

    $script:LogLevel = $Level
    $script:LogJson = $JsonOutput.IsPresent
    $script:LogTimestamp = -not $NoTimestamp.IsPresent

    if ($LogPath) {
        $script:LogFile = $LogPath
        $script:LogToFile = $true

        # Ensure log directory exists
        $logDir = Split-Path $LogPath -Parent
        if ($logDir -and -not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    }
}

function Set-LogLevel {
    param(
        [Parameter(Mandatory)]
        [LogLevel]$Level
    )
    $script:LogLevel = $Level
}

function Get-LogLevel {
    return $script:LogLevel
}

#endregion

#region Core Logging

function Write-Log {
    <#
    .SYNOPSIS
        Core logging function.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [LogLevel]$Level = [LogLevel]::INFO,

        [string]$Prefix,

        [ConsoleColor]$Color,

        [switch]$NoNewline
    )

    # Check if level is enabled
    if ([int]$Level -gt [int]$script:LogLevel) {
        return
    }

    # Build log entry
    $timestamp = if ($script:LogTimestamp) { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' } else { '' }
    $levelName = $Level.ToString()

    # JSON output
    if ($script:LogJson) {
        $entry = @{
            timestamp = $timestamp
            level = $levelName
            message = $Message
        }

        if ($Prefix) { $entry['prefix'] = $Prefix }

        $json = $entry | ConvertTo-Json -Compress

        if ($script:LogToFile) {
            Add-Content -Path $script:LogFile -Value $json
        }
        else {
            Write-Host $json
        }
        return
    }

    # Console output
    $displayColor = if ($Color) { $Color } else { $script:LogColors[$levelName] }
    $prefix = if ($Prefix) { $Prefix } else { "[$levelName]" }

    $formattedMessage = if ($script:LogTimestamp) {
        "$timestamp $prefix $Message"
    }
    else {
        "$prefix $Message"
    }

    # Write to console
    if ($NoNewline) {
        Write-Host $formattedMessage -ForegroundColor $displayColor -NoNewline
    }
    else {
        Write-Host $formattedMessage -ForegroundColor $displayColor
    }

    # Write to file
    if ($script:LogToFile) {
        Add-Content -Path $script:LogFile -Value $formattedMessage
    }
}

#endregion

#region Convenience Functions

function Write-LogError {
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level ([LogLevel]::ERROR) -Prefix '✗' -Color Red
}

function Write-LogWarn {
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level ([LogLevel]::WARN) -Prefix '⚠' -Color Yellow
}

function Write-LogInfo {
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level ([LogLevel]::INFO) -Prefix '•' -Color Cyan
}

function Write-LogDebug {
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level ([LogLevel]::DEBUG) -Prefix '⋯' -Color Gray
}

function Write-LogTrace {
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level ([LogLevel]::TRACE) -Prefix '→' -Color DarkGray
}

function Write-LogSuccess {
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level ([LogLevel]::INFO) -Prefix '✓' -Color Green
}

function Write-LogStep {
    param([Parameter(Mandatory)][string]$Message)
    Write-Log -Message $Message -Level ([LogLevel]::INFO) -Prefix '▶' -Color White
}

#endregion

#region UI Elements

function Write-Header {
    <#
    .SYNOPSIS
        Writes a styled header.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title
    )

    $width = 60
    $line = '═' * $width
    $padding = ($width - $Title.Length - 2) / 2
    $leftPad = ' ' * [Math]::Floor($padding)
    $rightPad = ' ' * [Math]::Ceiling($padding)

    Write-Host ""
    Write-Host "╔$line╗" -ForegroundColor Magenta
    Write-Host "║$leftPad$Title$rightPad║" -ForegroundColor Magenta
    Write-Host "╚$line╝" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Divider {
    <#
    .SYNOPSIS
        Writes a horizontal divider line.
    #>
    param(
        [int]$Width = 60,
        [char]$Char = '─'
    )

    Write-Host ($Char.ToString() * $Width) -ForegroundColor DarkGray
}

function Write-KeyValue {
    <#
    .SYNOPSIS
        Writes a key-value pair with alignment.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$Value,

        [int]$KeyWidth = 20
    )

    $paddedKey = $Key.PadRight($KeyWidth)
    Write-Host "  $paddedKey" -ForegroundColor Gray -NoNewline
    Write-Host " $Value" -ForegroundColor White
}

function Write-Progress2 {
    <#
    .SYNOPSIS
        Writes a progress bar.
    #>
    param(
        [Parameter(Mandatory)]
        [int]$Current,

        [Parameter(Mandatory)]
        [int]$Total,

        [string]$Label = '',

        [int]$Width = 40
    )

    $percent = if ($Total -gt 0) { [Math]::Round(($Current / $Total) * 100) } else { 0 }
    $filled = [Math]::Round(($Current / [Math]::Max($Total, 1)) * $Width)
    $empty = $Width - $filled

    $bar = ('█' * $filled) + ('░' * $empty)

    Write-Host "`r  [$bar] $percent% $Label" -NoNewline

    if ($Current -eq $Total) {
        Write-Host ""
    }
}

function Show-DryRunBanner {
    <#
    .SYNOPSIS
        Shows a prominent dry-run mode banner.
    #>
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
    Write-Host "║                     DRY RUN MODE                             ║" -ForegroundColor Yellow
    Write-Host "║          No changes will be made to the filesystem           ║" -ForegroundColor Yellow
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
    Write-Host ""
}

function Request-Confirmation {
    <#
    .SYNOPSIS
        Prompts the user for confirmation.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [switch]$DefaultYes
    )

    $prompt = if ($DefaultYes) { "$Message [Y/n]" } else { "$Message [y/N]" }

    Write-Host "$prompt " -ForegroundColor Yellow -NoNewline
    $response = Read-Host

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultYes.IsPresent
    }

    return $response -match '^[Yy]'
}

#endregion

#region Timer

function Start-Timer {
    <#
    .SYNOPSIS
        Starts a timer and returns the start time.
    #>
    return [DateTime]::Now
}

function Stop-Timer {
    <#
    .SYNOPSIS
        Stops a timer and outputs the elapsed time.
    #>
    param(
        [Parameter(Mandatory)]
        [DateTime]$StartTime,

        [string]$Label = 'Elapsed'
    )

    $elapsed = [DateTime]::Now - $StartTime

    $formatted = if ($elapsed.TotalHours -ge 1) {
        '{0:D2}:{1:D2}:{2:D2}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
    }
    elseif ($elapsed.TotalMinutes -ge 1) {
        '{0:D2}:{1:D2}' -f [int]$elapsed.TotalMinutes, $elapsed.Seconds
    }
    else {
        '{0:F2}s' -f $elapsed.TotalSeconds
    }

    Write-LogDebug "$Label : $formatted"

    return $elapsed
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Initialize-Logger',
    'Set-LogLevel',
    'Get-LogLevel',
    'Write-Log',
    'Write-LogError',
    'Write-LogWarn',
    'Write-LogInfo',
    'Write-LogDebug',
    'Write-LogTrace',
    'Write-LogSuccess',
    'Write-LogStep',
    'Write-Header',
    'Write-Divider',
    'Write-KeyValue',
    'Write-Progress2',
    'Show-DryRunBanner',
    'Request-Confirmation',
    'Start-Timer',
    'Stop-Timer'
)
