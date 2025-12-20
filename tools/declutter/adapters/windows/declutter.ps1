#Requires -Version 5.1
# ============================================================================
# Declutter - File Organization & Cleanup Tool
# Windows PowerShell Adapter
# ============================================================================
#
# Cross-platform wrapper that provides Windows support for Declutter
# Implements the same interface as the Bash version
#
# Usage: .\declutter.ps1 <command> [options]
#
# ============================================================================

param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments,

    [switch]$DryRun,
    [switch]$NoConfirm,
    [switch]$Quiet,
    [switch]$Verbose,
    [switch]$Help,
    [switch]$Version
)

$ErrorActionPreference = "Stop"
$Script:Version = "1.0.0"

# Configuration
$Script:ConfigDir = Join-Path $env:USERPROFILE ".declutter"
$Script:ConfigFile = Join-Path $Script:ConfigDir "config.yaml"
$Script:LogDir = Join-Path $Script:ConfigDir "logs"
$Script:UndoDir = Join-Path $Script:ConfigDir "undo"
$Script:TrashDir = Join-Path $Script:ConfigDir "trash"

# Colors
$Script:Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Blue"
    Cyan = "Cyan"
    White = "White"
    Gray = "Gray"
}

# Initialize
function Initialize-Declutter {
    @($Script:ConfigDir, $Script:LogDir, $Script:UndoDir, $Script:TrashDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
}

# Logging
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$Color = "White"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logFile = Join-Path $Script:LogDir "declutter_$(Get-Date -Format 'yyyyMMdd').log"

    if (-not $Script:Quiet) {
        Write-Host "[$timestamp] " -NoNewline -ForegroundColor Gray
        Write-Host "[$Level] " -NoNewline -ForegroundColor $Color
        Write-Host $Message
    }

    "[$timestamp] [$Level] $Message" | Out-File -Append -FilePath $logFile
}

function Write-Info { param([string]$Message) Write-Log $Message "INFO" "Blue" }
function Write-Success { param([string]$Message) Write-Log $Message "OK" "Green" }
function Write-Warning { param([string]$Message) Write-Log $Message "WARN" "Yellow" }
function Write-Error { param([string]$Message) Write-Log $Message "ERROR" "Red" }

function Write-Header {
    param([string]$Title)

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ("=" * 60) -ForegroundColor Magenta
    Write-Host ""
}

# File Operations
function Get-FileSize {
    param([string]$Path)

    if (Test-Path $Path) {
        return (Get-Item $Path).Length
    }
    return 0
}

function Get-HumanSize {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Move-ToTrash {
    param([string]$Path)

    if ($Script:DryRun) {
        Write-Info "[DRY RUN] Would delete: $Path"
        return
    }

    $fileName = Split-Path $Path -Leaf
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $trashPath = Join-Path $Script:TrashDir "${timestamp}_${fileName}"

    Move-Item -Path $Path -Destination $trashPath -Force
    Write-Info "Moved to trash: $Path"
}

function Confirm-Action {
    param([string]$Message)

    if ($Script:NoConfirm) { return $true }

    $response = Read-Host "$Message [y/N]"
    return $response -match '^[Yy]'
}

# Czkawka Integration
function Find-Czkawka {
    $paths = @(
        "czkawka_cli.exe",
        "$env:USERPROFILE\scoop\apps\czkawka\current\czkawka_cli.exe",
        "$env:LOCALAPPDATA\Programs\czkawka\czkawka_cli.exe",
        "C:\Program Files\czkawka\czkawka_cli.exe"
    )

    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
        $found = Get-Command $path -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }

    return $null
}

# Duplicate Detection
function Find-Duplicates {
    param([string]$SearchPath = ".")

    $czkawka = Find-Czkawka

    if (-not $czkawka) {
        Write-Warning "czkawka not found. Install from: https://github.com/qarmin/czkawka"
        Write-Info "Or install via: scoop install czkawka"
        return
    }

    Write-Header "Duplicate File Finder"
    Write-Info "Scanning: $SearchPath"
    Write-Info "Using czkawka: $czkawka"

    $outputFile = [System.IO.Path]::GetTempFileName()

    & $czkawka dup --directories $SearchPath --file-to-save $outputFile 2>$null

    if (Test-Path $outputFile) {
        $content = Get-Content $outputFile
        Write-Host $content
        Remove-Item $outputFile -Force
    }
}

# Large File Finder
function Find-LargeFiles {
    param(
        [string]$SearchPath = ".",
        [int]$ThresholdMB = 100,
        [int]$Limit = 50
    )

    Write-Header "Large File Finder"
    Write-Info "Searching in: $SearchPath"
    Write-Info "Threshold: ${ThresholdMB}MB"

    $thresholdBytes = $ThresholdMB * 1MB

    $files = Get-ChildItem -Path $SearchPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge $thresholdBytes } |
        Sort-Object Length -Descending |
        Select-Object -First $Limit

    if ($files.Count -eq 0) {
        Write-Info "No files larger than ${ThresholdMB}MB found"
        return
    }

    $totalSize = ($files | Measure-Object -Property Length -Sum).Sum

    Write-Host ""
    Write-Host ("{0,-45} {1,12} {2,12}" -f "FILE", "SIZE", "MODIFIED") -ForegroundColor White
    Write-Host ("{0,-45} {1,12} {2,12}" -f ("-" * 45), ("-" * 12), ("-" * 12)) -ForegroundColor Gray

    $idx = 1
    foreach ($file in $files) {
        $name = $file.Name
        if ($name.Length -gt 42) { $name = $name.Substring(0, 39) + "..." }

        Write-Host ("[{0,2}] {1,-40} {2,12} {3,12}" -f $idx, $name, (Get-HumanSize $file.Length), $file.LastWriteTime.ToString("yyyy-MM-dd")) -ForegroundColor Cyan
        $idx++
    }

    Write-Host ""
    Write-Info "Total: $($files.Count) files ($(Get-HumanSize $totalSize))"
}

# Old File Finder
function Find-OldFiles {
    param(
        [string]$SearchPath = ".",
        [int]$Days = 90
    )

    Write-Header "Old File Finder"
    Write-Info "Threshold: $Days days since last access"

    $threshold = (Get-Date).AddDays(-$Days)

    $files = Get-ChildItem -Path $SearchPath -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastAccessTime -lt $threshold } |
        Sort-Object LastAccessTime |
        Select-Object -First 100

    if ($files.Count -eq 0) {
        Write-Info "No files older than $Days days found"
        return
    }

    Write-Host ""
    foreach ($file in $files) {
        $daysOld = [math]::Floor(((Get-Date) - $file.LastAccessTime).TotalDays)
        $color = if ($daysOld -gt 365) { "Red" } elseif ($daysOld -gt 180) { "Yellow" } else { "White" }

        Write-Host ("{0,-40} {1,10} days old" -f $file.Name.Substring(0, [Math]::Min(40, $file.Name.Length)), $daysOld) -ForegroundColor $color
    }
}

# Directory Analysis
function Get-DirectoryAnalysis {
    param(
        [string]$SearchPath = ".",
        [int]$Depth = 2
    )

    Write-Header "Directory Size Analysis"
    Write-Info "Analyzing: $SearchPath"

    $dirs = Get-ChildItem -Path $SearchPath -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $size = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            [PSCustomObject]@{
                Name = $_.Name
                Path = $_.FullName
                Size = if ($size) { $size } else { 0 }
            }
        } |
        Sort-Object Size -Descending |
        Select-Object -First 20

    $totalSize = ($dirs | Measure-Object -Property Size -Sum).Sum

    Write-Host ""
    Write-Host ("{0,-40} {1,15} {2,8}" -f "DIRECTORY", "SIZE", "%") -ForegroundColor White
    Write-Host ("{0,-40} {1,15} {2,8}" -f ("-" * 40), ("-" * 15), ("-" * 8)) -ForegroundColor Gray

    foreach ($dir in $dirs) {
        $pct = if ($totalSize -gt 0) { [math]::Round($dir.Size / $totalSize * 100) } else { 0 }
        $color = if ($pct -gt 50) { "Red" } elseif ($pct -gt 25) { "Yellow" } else { "Cyan" }

        Write-Host ("{0,-40} {1,15} {2,7}%" -f $dir.Name, (Get-HumanSize $dir.Size), $pct) -ForegroundColor $color
    }
}

# Cleanup Presets
function Invoke-Cleanup {
    param(
        [string]$Preset,
        [string]$SearchPath = "."
    )

    $patterns = switch ($Preset) {
        "dev" {
            @("node_modules", "__pycache__", "*.pyc", ".pytest_cache", ".mypy_cache",
              "target", ".gradle", "build", "dist", ".next", ".nuxt", "coverage")
        }
        "system" {
            @("*.tmp", "*.temp", "*.log", "*.bak", "Thumbs.db", "desktop.ini")
        }
        "all" {
            @("node_modules", "__pycache__", "*.pyc", ".pytest_cache",
              "*.tmp", "*.temp", "*.log", "Thumbs.db", "desktop.ini")
        }
        default {
            Write-Error "Unknown preset: $Preset"
            Write-Info "Available: dev, system, all"
            return
        }
    }

    Write-Header "Cleanup: $Preset"

    $totalSize = 0
    $totalCount = 0

    foreach ($pattern in $patterns) {
        $items = Get-ChildItem -Path $SearchPath -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $pattern }

        foreach ($item in $items) {
            $size = if ($item.PSIsContainer) {
                (Get-ChildItem -Path $item.FullName -Recurse -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
            } else {
                $item.Length
            }

            $totalSize += $size
            $totalCount++

            if ($Script:DryRun) {
                Write-Info "[DRY RUN] Would delete: $($item.FullName) ($(Get-HumanSize $size))"
            } else {
                Move-ToTrash $item.FullName
            }
        }
    }

    Write-Success "Cleaned up $totalCount items ($(Get-HumanSize $totalSize) freed)"
}

# Show Help
function Show-Help {
    @"
╔══════════════════════════════════════════════════════════════════════════════╗
║                    DECLUTTER - File Organization Tool (Windows)               ║
╚══════════════════════════════════════════════════════════════════════════════╝

USAGE:
    .\declutter.ps1 <command> [options] [path]

COMMANDS:
    duplicates <path>       Find duplicate files
    large <path> [size_mb]  Find large files (default: 100MB)
    old <path> [days]       Find old files (default: 90 days)
    analyze <path>          Analyze directory sizes
    cleanup <preset> [path] Run cleanup (dev, system, all)

OPTIONS:
    -DryRun                 Preview without executing
    -NoConfirm              Skip confirmation prompts
    -Quiet                  Minimal output
    -Help                   Show this help
    -Version                Show version

EXAMPLES:
    .\declutter.ps1 duplicates C:\Users\Me\Documents
    .\declutter.ps1 large C:\Downloads 500
    .\declutter.ps1 cleanup dev -DryRun
    .\declutter.ps1 analyze C:\Users
"@
}

# Main
function Main {
    Initialize-Declutter

    $Script:DryRun = $DryRun.IsPresent
    $Script:NoConfirm = $NoConfirm.IsPresent
    $Script:Quiet = $Quiet.IsPresent

    if ($Help -or [string]::IsNullOrEmpty($Command)) {
        Show-Help
        return
    }

    if ($Version) {
        Write-Host "declutter version $Script:Version (Windows PowerShell)"
        return
    }

    switch ($Command.ToLower()) {
        "duplicates" { Find-Duplicates ($Arguments[0] ?? ".") }
        "dupes" { Find-Duplicates ($Arguments[0] ?? ".") }
        "large" { Find-LargeFiles ($Arguments[0] ?? ".") ([int]($Arguments[1] ?? 100)) }
        "big" { Find-LargeFiles ($Arguments[0] ?? ".") ([int]($Arguments[1] ?? 100)) }
        "old" { Find-OldFiles ($Arguments[0] ?? ".") ([int]($Arguments[1] ?? 90)) }
        "analyze" { Get-DirectoryAnalysis ($Arguments[0] ?? ".") }
        "dir" { Get-DirectoryAnalysis ($Arguments[0] ?? ".") }
        "cleanup" { Invoke-Cleanup ($Arguments[0] ?? "dev") ($Arguments[1] ?? ".") }
        "clean" { Invoke-Cleanup ($Arguments[0] ?? "dev") ($Arguments[1] ?? ".") }
        "help" { Show-Help }
        default {
            Write-Error "Unknown command: $Command"
            Write-Host ""
            Write-Host "Run '.\declutter.ps1 -Help' for usage information."
        }
    }
}

Main
