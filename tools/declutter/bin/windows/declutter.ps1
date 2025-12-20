#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Modern File Organization and Cleanup Tool

.DESCRIPTION
    Cross-platform file decluttering tool with duplicate detection,
    large file finding, cleanup presets, and safe operations.

.PARAMETER Command
    The command to execute:
    - duplicates: Find duplicate files
    - large/big: Find large files
    - old: Find old/unused files
    - temp: Find temporary files
    - quick: Quick cleanup (junk files, empty dirs)
    - dev: Developer cleanup (node_modules, caches)
    - system: System cleanup (temp, caches)
    - organize: Auto-organize files by type
    - history: Show action history
    - undo: Undo last action

.PARAMETER Path
    Target path to scan/clean (default: current directory)

.PARAMETER DryRun
    Preview changes without making them

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER JsonOutput
    Output results as JSON

.EXAMPLE
    .\declutter.ps1 duplicates ~/Downloads

.EXAMPLE
    .\declutter.ps1 dev -DryRun ~/Projects

.EXAMPLE
    .\declutter.ps1 large -Threshold 500MB ~/Videos

.LINK
    https://github.com/your-repo/declutter
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'duplicates', 'dup', 'dups',
        'similar', 'images',
        'large', 'big',
        'old', 'unused',
        'temp', 'tmp',
        'empty',
        'orphans', 'junk',
        'analyze', 'usage',
        'quick',
        'deep',
        'dev', 'developer',
        'system', 'sys',
        'organize', 'sort',
        'flatten',
        'history', 'log',
        'undo',
        'config',
        'help', '?'
    )]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$Path,

    [Parameter(Position = 2)]
    [string]$Arg1,

    [Alias('n')]
    [switch]$DryRun,

    [Alias('y')]
    [switch]$Force,

    [Alias('v')]
    [switch]$Verbose,

    [Alias('q')]
    [switch]$Quiet,

    [switch]$JsonOutput,

    [string]$Threshold = '100MB',

    [int]$Days = 90,

    [int]$Count = 50,

    [string]$ConfigFile
)

# =============================================================================
# Setup
# =============================================================================

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Version = '2.0.0'
$script:ScriptRoot = $PSScriptRoot
$script:LibRoot = Join-Path (Split-Path (Split-Path $ScriptRoot -Parent) -Parent) 'lib/powershell'

# Fallback paths
if (-not (Test-Path $script:LibRoot)) {
    # Try relative from bin/windows
    $script:LibRoot = Join-Path $ScriptRoot '../../lib/powershell'
}
if (-not (Test-Path $script:LibRoot)) {
    # Try as sibling
    $script:LibRoot = Join-Path (Split-Path $ScriptRoot -Parent) 'lib/powershell'
}

# =============================================================================
# Module Loading
# =============================================================================

try {
    Import-Module (Join-Path $LibRoot 'core/Platform.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $LibRoot 'core/Logger.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $LibRoot 'scanners/Duplicates.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $LibRoot 'scanners/LargeFiles.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $LibRoot 'scanners/OldFiles.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $LibRoot 'actions/SafeActions.psm1') -Force -ErrorAction Stop
    Import-Module (Join-Path $LibRoot 'presets/Presets.psm1') -Force -ErrorAction Stop
}
catch {
    Write-Error "Failed to load modules: $_"
    Write-Error "Library path: $LibRoot"
    exit 1
}

# =============================================================================
# Initialization
# =============================================================================

# Set log level
if ($Quiet) {
    Set-LogLevel -Level ([LogLevel]::ERROR)
}
elseif ($Verbose) {
    Set-LogLevel -Level ([LogLevel]::DEBUG)
}
else {
    Set-LogLevel -Level ([LogLevel]::INFO)
}

# Configure actions
Set-ActionConfig -DryRun:$DryRun

# Default path
if (-not $Path) {
    $Path = $PWD.Path
}

# =============================================================================
# Help
# =============================================================================

function Show-Help {
    $helpText = @"

╔══════════════════════════════════════════════════════════════╗
║                        DECLUTTER                              ║
║            Modern File Organization & Cleanup Tool            ║
╚══════════════════════════════════════════════════════════════╝

USAGE: declutter <command> [path] [options]

SCAN COMMANDS:
  duplicates, dup     Find duplicate files
  similar, images     Find similar images (requires czkawka)
  large, big          Find files above size threshold
  old, unused         Find old/unused files
  temp, tmp           Find temporary files
  empty               Find empty files and directories
  orphans, junk       Find orphaned/junk files
  analyze, usage      Analyze disk usage

CLEANUP PRESETS:
  quick               Quick cleanup (junk files, empty dirs)
  deep                Full deep scan and cleanup
  dev, developer      Clean dev artifacts (node_modules, caches)
  system, sys         Clean system temp files and caches

ACTIONS:
  organize, sort      Auto-organize files by type
  flatten             Flatten nested directories

HISTORY:
  history, log        Show action history
  undo                Undo last action

OPTIONS:
  -DryRun, -n         Preview changes without making them
  -Force, -y          Skip confirmation prompts
  -Verbose, -v        Show detailed output
  -Quiet, -q          Minimal output
  -JsonOutput         Output results as JSON
  -Threshold          Size threshold for 'large' command (default: 100MB)
  -Days               Age threshold for 'old' command (default: 90)
  -Count              Max results to show (default: 50)

EXAMPLES:
  declutter duplicates ~/Downloads
  declutter large -Threshold 500MB ~/Videos
  declutter old -Days 30 ~/Downloads
  declutter dev -DryRun ~/Projects
  declutter quick ~/Desktop
  declutter organize ~/Downloads

VERSION: $script:Version
PLATFORM: $(Get-Platform)

"@
    Write-Host $helpText
}

# =============================================================================
# Command Execution
# =============================================================================

function Invoke-Command {
    param([string]$Cmd)

    switch ($Cmd) {
        # Scan commands
        { $_ -in @('duplicates', 'dup', 'dups') } {
            Find-DuplicateFiles -Path $Path -JsonOutput:$JsonOutput
        }

        { $_ -in @('similar', 'images') } {
            Find-SimilarImages -Path $Path -JsonOutput:$JsonOutput
        }

        { $_ -in @('large', 'big') } {
            $countVal = if ($Arg1) { [int]$Arg1 } else { $Count }
            Find-LargeFiles -Path $Path -Threshold $Threshold -Count $countVal -JsonOutput:$JsonOutput
        }

        { $_ -in @('old', 'unused') } {
            $daysVal = if ($Arg1) { [int]$Arg1 } else { $Days }
            Find-OldFiles -Path $Path -Days $daysVal -JsonOutput:$JsonOutput
        }

        { $_ -in @('temp', 'tmp') } {
            Find-TempFiles -Path $Path -JsonOutput:$JsonOutput
        }

        { $_ -in @('analyze', 'usage') } {
            Get-DiskUsageSummary -Path $Path -JsonOutput:$JsonOutput
        }

        # Presets
        'quick' {
            Invoke-QuickCleanup -Path $Path -Force:$Force
        }

        { $_ -in @('dev', 'developer') } {
            Invoke-DevCleanup -Path $Path -Force:$Force
        }

        { $_ -in @('system', 'sys') } {
            Invoke-SystemCleanup -Force:$Force
        }

        # Actions
        { $_ -in @('organize', 'sort') } {
            Move-ToCategory -Path $Path -Force:$Force
        }

        # History
        { $_ -in @('history', 'log') } {
            $entries = Get-JournalHistory -Count $Count

            if ($entries.Count -eq 0) {
                Write-LogInfo "No actions in history"
                return
            }

            Write-Header "Action History"

            foreach ($entry in $entries) {
                $time = [DateTime]::Parse($entry.Timestamp).ToString('yyyy-MM-dd HH:mm')
                Write-Host "  $time " -NoNewline -ForegroundColor Gray
                Write-Host "$($entry.Action.ToUpper().PadRight(8)) " -NoNewline -ForegroundColor Cyan
                Write-Host $entry.Source -ForegroundColor White

                if ($entry.Destination) {
                    Write-Host "              → $($entry.Destination)" -ForegroundColor DarkGray
                }
            }
        }

        'undo' {
            if ($Arg1) {
                Undo-JournalEntry -Id $Arg1
            }
            else {
                Undo-LastAction
            }
        }

        'config' {
            Write-Header "Configuration"
            Write-KeyValue "Platform" (Get-Platform)
            Write-KeyValue "PowerShell" $PSVersionTable.PSVersion.ToString()
            Write-KeyValue "Czkawka" $(if (Test-CzkawkaInstalled) { "Installed" } else { "Not found" })
            Write-KeyValue "Dry Run" $DryRun
            Write-KeyValue "Use Trash" $true
        }

        { $_ -in @('help', '?') } {
            Show-Help
        }

        default {
            Write-LogError "Unknown command: $Cmd"
            Write-Host "Use 'declutter help' for usage information"
            exit 1
        }
    }
}

# =============================================================================
# Main
# =============================================================================

try {
    Invoke-Command -Cmd $Command
}
catch {
    Write-LogError "Error: $_"
    if ($Verbose) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
}
