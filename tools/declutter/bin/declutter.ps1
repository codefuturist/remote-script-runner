#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Modern File Organization and Cleanup Tool (Windows)

.DESCRIPTION
    Cross-platform file organization and cleanup tool.
    This PowerShell wrapper provides native Windows support.

.EXAMPLE
    .\declutter.ps1 duplicates C:\Users\User\Documents
    .\declutter.ps1 cleanup dev C:\Projects -DryRun
    .\declutter.ps1 analyze C:\Users\User
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Arguments,

    [switch]$DryRun,
    [switch]$Verbose,
    [switch]$Yes,
    [string]$MinSize,
    [int]$Limit,
    [int]$Days,
    [int]$Depth,
    [string]$Target,
    [string]$Style,
    [string]$Output
)

# =============================================================================
# Configuration
# =============================================================================

$Script:Version = "1.0.0"
$Script:DeclutterDir = $PSScriptRoot
$Script:DataDir = Join-Path $env:USERPROFILE ".declutter"
$Script:TrashDir = Join-Path $Script:DataDir "trash"
$Script:UndoDir = Join-Path $Script:DataDir "undo"
$Script:LogFile = Join-Path $Script:DataDir "logs" "declutter.log"

$Script:IsDryRun = $DryRun.IsPresent
$Script:IsInteractive = -not $Yes.IsPresent

# =============================================================================
# Initialization
# =============================================================================

function Initialize-Declutter {
    @($Script:DataDir, $Script:TrashDir, $Script:UndoDir, (Split-Path $Script:LogFile)) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
        }
    }
}

# =============================================================================
# Logging
# =============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    $color = switch ($Level) {
        "DEBUG" { "Gray" }
        "INFO"  { "Cyan" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
    }

    Write-Host $logEntry -ForegroundColor $color
    Add-Content -Path $Script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
}

# =============================================================================
# Size Utilities
# =============================================================================

function Format-FileSize {
    param([long]$Bytes)

    $sizes = "B", "KB", "MB", "GB", "TB"
    $order = 0
    $size = [double]$Bytes

    while ($size -ge 1024 -and $order -lt $sizes.Count - 1) {
        $order++
        $size = $size / 1024
    }

    "{0:N2} {1}" -f $size, $sizes[$order]
}

function ConvertTo-Bytes {
    param([string]$SizeString)

    if ($SizeString -match "^(\d+(?:\.\d+)?)\s*(B|KB|MB|GB|TB)?$") {
        $number = [double]$Matches[1]
        $unit = if ($Matches[2]) { $Matches[2].ToUpper() } else { "B" }

        $multiplier = switch ($unit) {
            "B"  { 1 }
            "KB" { 1024 }
            "MB" { 1024 * 1024 }
            "GB" { 1024 * 1024 * 1024 }
            "TB" { 1024 * 1024 * 1024 * 1024 }
        }

        return [long]($number * $multiplier)
    }
    return [long]$SizeString
}

# =============================================================================
# File Categories
# =============================================================================

$Script:FileCategories = @{
    documents = @("pdf", "doc", "docx", "txt", "rtf", "odt", "xls", "xlsx", "ppt", "pptx", "csv", "md")
    images    = @("jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "ico", "tiff", "raw", "heic")
    videos    = @("mp4", "mkv", "avi", "mov", "wmv", "flv", "webm", "m4v")
    audio     = @("mp3", "wav", "flac", "aac", "ogg", "wma", "m4a", "opus")
    code      = @("js", "ts", "py", "rb", "go", "rs", "java", "c", "cpp", "h", "cs", "php", "swift", "ps1")
    archives  = @("zip", "tar", "gz", "bz2", "xz", "7z", "rar", "iso")
    data      = @("json", "xml", "yaml", "yml", "toml", "ini", "cfg", "conf", "db", "sqlite")
}

function Get-FileCategory {
    param([string]$FilePath)

    $ext = [System.IO.Path]::GetExtension($FilePath).TrimStart(".").ToLower()

    foreach ($category in $Script:FileCategories.Keys) {
        if ($Script:FileCategories[$category] -contains $ext) {
            return $category
        }
    }
    return "other"
}

# =============================================================================
# Safe Operations
# =============================================================================

function Move-ToTrash {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Log "File not found: $Path" -Level WARN
        return $false
    }

    if ($Script:IsDryRun) {
        Write-Log "[DRY-RUN] Would trash: $Path" -Level INFO
        return $true
    }

    $fileName = Split-Path $Path -Leaf
    $destPath = Join-Path $Script:TrashDir $fileName

    $counter = 1
    while (Test-Path $destPath) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $ext = [System.IO.Path]::GetExtension($fileName)
        $destPath = Join-Path $Script:TrashDir "${baseName}_${counter}${ext}"
        $counter++
    }

    Move-Item -Path $Path -Destination $destPath -Force
    Write-Log "Moved to trash: $Path -> $destPath" -Level INFO
    return $true
}

function Invoke-SafeMove {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path $Source)) {
        Write-Log "Source not found: $Source" -Level ERROR
        return $false
    }

    if ($Script:IsDryRun) {
        Write-Log "[DRY-RUN] Would move: $Source -> $Destination" -Level INFO
        return $true
    }

    $destDir = Split-Path $Destination -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Move-Item -Path $Source -Destination $Destination -Force
    Write-Log "Moved: $Source -> $Destination" -Level INFO
    return $true
}

# =============================================================================
# Duplicate Detection
# =============================================================================

function Find-Duplicates {
    param(
        [string]$Path = ".",
        [long]$MinSize = 1
    )

    Write-Log "Scanning for duplicates in: $Path" -Level INFO

    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Length -ge $MinSize }

    # Group by size first
    $sizeGroups = $files | Group-Object Length | Where-Object { $_.Count -gt 1 }

    $hashGroups = @{}
    $processed = 0
    $total = ($sizeGroups | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum

    foreach ($group in $sizeGroups) {
        foreach ($file in $group.Group) {
            $processed++
            Write-Progress -Activity "Hashing files" -Status "$processed of $total" -PercentComplete (($processed / $total) * 100)

            try {
                $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
                if (-not $hashGroups.ContainsKey($hash)) {
                    $hashGroups[$hash] = @()
                }
                $hashGroups[$hash] += $file
            } catch {
                Write-Log "Failed to hash: $($file.FullName)" -Level WARN
            }
        }
    }

    Write-Progress -Activity "Hashing files" -Completed

    # Display results
    $duplicateGroups = $hashGroups.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }

    if ($duplicateGroups.Count -eq 0) {
        Write-Log "No duplicates found." -Level INFO
        return
    }

    $groupNum = 0
    foreach ($group in $duplicateGroups) {
        $groupNum++
        $files = $group.Value
        $size = $files[0].Length

        Write-Host ""
        Write-Host "=== Group $groupNum ($(Format-FileSize $size) each, $($files.Count) files) ===" -ForegroundColor Cyan
        foreach ($file in $files) {
            Write-Host "  $($file.FullName)"
        }
    }

    Write-Host ""
    Write-Log "Found $($duplicateGroups.Count) duplicate groups" -Level INFO
}

# =============================================================================
# Large File Finder
# =============================================================================

function Find-LargeFiles {
    param(
        [string]$Path = ".",
        [string]$MinSizeStr = "100MB",
        [int]$Limit = 50
    )

    $minSize = ConvertTo-Bytes $MinSizeStr
    Write-Log "Finding files larger than $(Format-FileSize $minSize)..." -Level INFO

    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Length -ge $minSize } |
             Sort-Object Length -Descending |
             Select-Object -First $Limit

    Write-Host ""
    Write-Host ("{0,-12} {1}" -f "SIZE", "FILE") -ForegroundColor Cyan
    Write-Host ("-" * 72)

    foreach ($file in $files) {
        Write-Host ("{0,-12} {1}" -f (Format-FileSize $file.Length), $file.FullName)
    }

    Write-Host ""
    Write-Log "Found $($files.Count) large files" -Level INFO
}

# =============================================================================
# Old File Finder
# =============================================================================

function Find-OldFiles {
    param(
        [string]$Path = ".",
        [int]$Days = 365
    )

    $cutoffDate = (Get-Date).AddDays(-$Days)
    Write-Log "Finding files not modified since $($cutoffDate.ToString('yyyy-MM-dd'))..." -Level INFO

    $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.LastWriteTime -lt $cutoffDate } |
             Sort-Object LastWriteTime

    Write-Host ""
    Write-Host ("{0,-20} {1,-12} {2}" -f "LAST MODIFIED", "SIZE", "FILE") -ForegroundColor Cyan
    Write-Host ("-" * 80)

    foreach ($file in $files | Select-Object -First 50) {
        Write-Host ("{0,-20} {1,-12} {2}" -f $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm"), (Format-FileSize $file.Length), $file.FullName)
    }

    if ($files.Count -gt 50) {
        Write-Host "... and $($files.Count - 50) more files"
    }

    Write-Host ""
    Write-Log "Found $($files.Count) old files" -Level INFO
}

# =============================================================================
# Empty Files/Directories
# =============================================================================

function Find-Empty {
    param([string]$Path = ".")

    Write-Log "Finding empty files..." -Level INFO
    $emptyFiles = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Length -eq 0 }

    if ($emptyFiles.Count -gt 0) {
        Write-Host ""
        Write-Host "Empty Files:" -ForegroundColor Cyan
        foreach ($file in $emptyFiles) {
            Write-Host "  $($file.FullName)"
        }
    }

    Write-Log "Finding empty directories..." -Level INFO
    $emptyDirs = Get-ChildItem -Path $Path -Recurse -Directory -ErrorAction SilentlyContinue |
                 Where-Object { (Get-ChildItem $_.FullName -Force).Count -eq 0 }

    if ($emptyDirs.Count -gt 0) {
        Write-Host ""
        Write-Host "Empty Directories:" -ForegroundColor Cyan
        foreach ($dir in $emptyDirs) {
            Write-Host "  $($dir.FullName)"
        }
    }

    Write-Host ""
    Write-Log "Found $($emptyFiles.Count) empty files and $($emptyDirs.Count) empty directories" -Level INFO
}

# =============================================================================
# Orphan Files
# =============================================================================

function Find-OrphanFiles {
    param([string]$Path = ".")

    $orphanPatterns = @(
        "Thumbs.db",
        "desktop.ini",
        "*.tmp",
        "*.temp",
        "*.bak",
        "*~"
    )

    Write-Log "Finding orphan/system files..." -Level INFO

    $orphans = @()
    foreach ($pattern in $orphanPatterns) {
        $orphans += Get-ChildItem -Path $Path -Recurse -Filter $pattern -Force -ErrorAction SilentlyContinue
    }

    if ($orphans.Count -gt 0) {
        Write-Host ""
        Write-Host "Orphan Files Found:" -ForegroundColor Cyan
        foreach ($file in $orphans) {
            Write-Host "  $($file.FullName)"
        }
    }

    Write-Host ""
    Write-Log "Found $($orphans.Count) orphan files" -Level INFO
}

# =============================================================================
# Directory Analysis
# =============================================================================

function Get-DirectoryAnalysis {
    param(
        [string]$Path = ".",
        [int]$Depth = 1
    )

    Write-Log "Analyzing disk usage: $Path" -Level INFO

    $items = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue

    $results = foreach ($item in $items) {
        $size = (Get-ChildItem -Path $item.FullName -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum

        [PSCustomObject]@{
            Name = $item.Name
            Path = $item.FullName
            Size = $size
            SizeFormatted = Format-FileSize $size
        }
    }

    Write-Host ""
    Write-Host ("{0,-12} {1}" -f "SIZE", "DIRECTORY") -ForegroundColor Cyan
    Write-Host ("-" * 60)

    $results | Sort-Object Size -Descending | ForEach-Object {
        Write-Host ("{0,-12} {1}" -f $_.SizeFormatted, $_.Path)
    }
}

# =============================================================================
# Organization
# =============================================================================

function Invoke-Organize {
    param(
        [string]$Path = ".",
        [string]$TargetPath
    )

    if (-not $TargetPath) { $TargetPath = $Path }

    Write-Log "Organizing files from: $Path" -Level INFO

    $files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue
    $organized = 0

    foreach ($file in $files) {
        $category = Get-FileCategory $file.FullName
        $destDir = Join-Path $TargetPath (Get-Culture).TextInfo.ToTitleCase($category)
        $destPath = Join-Path $destDir $file.Name

        if (Invoke-SafeMove -Source $file.FullName -Destination $destPath) {
            $organized++
        }
    }

    Write-Host ""
    Write-Log "Organized $organized files" -Level INFO
}

# =============================================================================
# Cleanup Presets
# =============================================================================

function Invoke-CleanupPreset {
    param(
        [string]$Preset,
        [string]$Path = "."
    )

    $patterns = switch ($Preset) {
        "dev" {
            @("node_modules", "__pycache__", "*.pyc", ".pytest_cache", "dist", "build", "*.log")
        }
        "system" {
            @("*.tmp", "*.temp", "Thumbs.db", "desktop.ini", "*.bak", "*~")
        }
        "cache" {
            @(".cache", ".npm", ".yarn")
        }
        default {
            Write-Log "Unknown preset: $Preset" -Level ERROR
            Write-Host "Available presets: dev, system, cache"
            return
        }
    }

    Write-Log "Running cleanup preset: $Preset" -Level INFO

    $totalSize = 0
    $totalCount = 0

    foreach ($pattern in $patterns) {
        $items = Get-ChildItem -Path $Path -Recurse -Filter $pattern -Force -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            $size = if ($item.PSIsContainer) {
                (Get-ChildItem $item.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            } else {
                $item.Length
            }

            Write-Host "  $(Format-FileSize $size)`t$($item.FullName)"
            $totalSize += $size
            $totalCount++
        }
    }

    Write-Host ""
    Write-Host "Items found: $totalCount" -ForegroundColor Cyan
    Write-Host "Total size:  $(Format-FileSize $totalSize)" -ForegroundColor Cyan

    if (-not $Script:IsDryRun -and $totalCount -gt 0 -and $Script:IsInteractive) {
        $confirm = Read-Host "Proceed with cleanup? [y/N]"
        if ($confirm -eq "y" -or $confirm -eq "Y") {
            foreach ($pattern in $patterns) {
                Get-ChildItem -Path $Path -Recurse -Filter $pattern -Force -ErrorAction SilentlyContinue |
                    ForEach-Object { Remove-Item $_.FullName -Recurse -Force }
            }
            Write-Log "Cleanup complete!" -Level INFO
        }
    }
}

# =============================================================================
# Help
# =============================================================================

function Show-Help {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Declutter - File Organization & Cleanup Tool v$($Script:Version)           ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE" -ForegroundColor Yellow
    Write-Host "    declutter.ps1 <command> [path] [options]"
    Write-Host ""
    Write-Host "COMMANDS" -ForegroundColor Yellow
    Write-Host "    duplicates      Find duplicate files"
    Write-Host "    large           Find large files"
    Write-Host "    old             Find old/unused files"
    Write-Host "    empty           Find empty files and directories"
    Write-Host "    orphans         Find orphan/system files"
    Write-Host "    analyze         Analyze directory sizes"
    Write-Host "    organize        Organize files by category"
    Write-Host "    cleanup <preset> Run cleanup preset (dev, system, cache)"
    Write-Host ""
    Write-Host "OPTIONS" -ForegroundColor Yellow
    Write-Host "    -DryRun         Preview changes without executing"
    Write-Host "    -Yes            Skip confirmation prompts"
    Write-Host "    -MinSize        Minimum file size (e.g., 100MB)"
    Write-Host "    -Days           Days for old file detection"
    Write-Host "    -Limit          Limit number of results"
    Write-Host ""
    Write-Host "EXAMPLES" -ForegroundColor Yellow
    Write-Host "    .\declutter.ps1 duplicates C:\Documents"
    Write-Host "    .\declutter.ps1 large -MinSize 500MB C:\Downloads"
    Write-Host "    .\declutter.ps1 cleanup dev C:\Projects -DryRun"
    Write-Host ""
}

# =============================================================================
# Main
# =============================================================================

Initialize-Declutter

$targetPath = if ($Arguments.Count -gt 0) { $Arguments[0] } else { "." }

switch ($Command.ToLower()) {
    "duplicates" { Find-Duplicates -Path $targetPath }
    "dups"       { Find-Duplicates -Path $targetPath }
    "large"      { Find-LargeFiles -Path $targetPath -MinSizeStr $(if ($MinSize) { $MinSize } else { "100MB" }) -Limit $(if ($Limit) { $Limit } else { 50 }) }
    "big"        { Find-LargeFiles -Path $targetPath -MinSizeStr $(if ($MinSize) { $MinSize } else { "100MB" }) -Limit $(if ($Limit) { $Limit } else { 50 }) }
    "old"        { Find-OldFiles -Path $targetPath -Days $(if ($Days) { $Days } else { 365 }) }
    "empty"      { Find-Empty -Path $targetPath }
    "orphans"    { Find-OrphanFiles -Path $targetPath }
    "analyze"    { Get-DirectoryAnalysis -Path $targetPath -Depth $(if ($Depth) { $Depth } else { 1 }) }
    "organize"   { Invoke-Organize -Path $targetPath -TargetPath $Target }
    "cleanup"    {
        $preset = if ($Arguments.Count -gt 0) { $Arguments[0] } else { "" }
        $path = if ($Arguments.Count -gt 1) { $Arguments[1] } else { "." }
        Invoke-CleanupPreset -Preset $preset -Path $path
    }
    "help"       { Show-Help }
    default      { Show-Help }
}
