#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Large Files Scanner Module

.DESCRIPTION
    Finds files exceeding specified size thresholds.
    Supports sorting by size, age, and access time.
#>

# Import core modules
$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot 'core/Platform.psm1') -Force
Import-Module (Join-Path $ModuleRoot 'core/Logger.psm1') -Force

function Find-LargeFiles {
    <#
    .SYNOPSIS
        Finds files larger than the specified threshold.

    .PARAMETER Path
        Path(s) to scan for large files.

    .PARAMETER Threshold
        Minimum file size (default: 100MB). Accepts human-readable formats like "500MB", "1GB".

    .PARAMETER Count
        Maximum number of results to return (default: 50).

    .PARAMETER SortBy
        Sort results by: Size, AccessTime, ModifiedTime (default: Size).

    .PARAMETER IncludeHidden
        Include hidden files in the scan.

    .EXAMPLE
        Find-LargeFiles -Path "C:\Users" -Threshold "500MB" -Count 20

    .EXAMPLE
        Find-LargeFiles -Path "D:\" -SortBy AccessTime
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Path = $PWD.Path,

        [Alias('MinSize', 'Size')]
        [string]$Threshold = '100MB',

        [Alias('Limit', 'Top')]
        [int]$Count = 50,

        [ValidateSet('Size', 'AccessTime', 'ModifiedTime', 'Name')]
        [string]$SortBy = 'Size',

        [switch]$IncludeHidden,

        [switch]$NoRecursive,

        [switch]$JsonOutput
    )

    Write-LogStep "Scanning for large files (threshold: $Threshold)..."
    $timer = Start-Timer

    # Normalize paths
    $normalizedPaths = $Path | ForEach-Object { Get-NormalizedPath $_ }

    # Validate paths
    foreach ($p in $normalizedPaths) {
        if (-not (Test-Path $p)) {
            Write-LogError "Path not found: $p"
            return
        }
    }

    $thresholdBytes = ConvertTo-Bytes $Threshold
    Write-LogDebug "Threshold: $thresholdBytes bytes"

    # Try czkawka first
    if (Test-CzkawkaInstalled) {
        $result = Find-LargeFilesWithCzkawka -Paths $normalizedPaths -ThresholdBytes $thresholdBytes -Count $Count
        if ($null -ne $result) {
            Stop-Timer $timer "Large files scan"
            return Format-LargeFilesResult -Result $result -JsonOutput:$JsonOutput
        }
    }

    # Native PowerShell implementation
    $allFiles = @()

    foreach ($p in $normalizedPaths) {
        $getParams = @{
            Path = $p
            File = $true
            Recurse = (-not $NoRecursive)
            ErrorAction = 'SilentlyContinue'
        }

        $files = Get-ChildItem @getParams | Where-Object { $_.Length -ge $thresholdBytes }
        $allFiles += $files
    }

    Write-LogDebug "Found $($allFiles.Count) large files"

    # Sort files
    $sortedFiles = switch ($SortBy) {
        'Size' { $allFiles | Sort-Object Length -Descending }
        'AccessTime' { $allFiles | Sort-Object LastAccessTime -Descending }
        'ModifiedTime' { $allFiles | Sort-Object LastWriteTime -Descending }
        'Name' { $allFiles | Sort-Object Name }
        default { $allFiles | Sort-Object Length -Descending }
    }

    # Limit results
    if ($Count -gt 0) {
        $sortedFiles = $sortedFiles | Select-Object -First $Count
    }

    # Build result
    $files = $sortedFiles | ForEach-Object {
        @{
            Path = $_.FullName
            Name = $_.Name
            Size = $_.Length
            SizeFormatted = Format-FileSize $_.Length
            ModifiedTime = $_.LastWriteTime.ToString('o')
            AccessTime = $_.LastAccessTime.ToString('o')
            Extension = $_.Extension.TrimStart('.')
            Category = Get-FileCategory $_.FullName
            DaysSinceAccess = [Math]::Round(((Get-Date) - $_.LastAccessTime).TotalDays)
            Recommendations = Get-FileSuggestions -File $_
        }
    }

    $totalSize = ($sortedFiles | Measure-Object -Property Length -Sum).Sum

    $result = @{
        ScanType = 'large_files'
        Threshold = $Threshold
        ThresholdBytes = $thresholdBytes
        SortBy = $SortBy
        Timestamp = (Get-Date).ToString('o')
        Files = @($files)
        Stats = @{
            TotalFiles = $files.Count
            TotalSize = $totalSize
            TotalSizeFormatted = Format-FileSize $totalSize
        }
    }

    Stop-Timer $timer "Large files scan"
    return Format-LargeFilesResult -Result $result -JsonOutput:$JsonOutput
}

function Find-LargeFilesWithCzkawka {
    <#
    .SYNOPSIS
        Uses czkawka_cli for finding large files.
    #>
    param(
        [string[]]$Paths,
        [long]$ThresholdBytes,
        [int]$Count
    )

    $czkawkaPath = Get-CzkawkaPath
    if (-not $czkawkaPath) { return $null }

    Write-LogDebug "Using czkawka_cli for large file detection"

    $args = @('big')
    $args += '-d'
    $args += ($Paths -join ',')
    $args += '-n'
    $args += $Count.ToString()
    $args += '-f'
    $args += 'json'

    try {
        $output = & $czkawkaPath $args 2>&1
        $jsonOutput = $output | Where-Object { $_ -match '^\s*[\[\{]' } | Out-String

        if ([string]::IsNullOrWhiteSpace($jsonOutput)) {
            return @{
                ScanType = 'large_files'
                Files = @()
                Stats = @{ TotalFiles = 0; TotalSize = 0 }
            }
        }

        $parsed = $jsonOutput | ConvertFrom-Json

        # Convert to our format
        $files = $parsed | ForEach-Object {
            @{
                Path = $_.path
                Size = $_.size
                SizeFormatted = Format-FileSize $_.size
                ModifiedTime = $_.modified_date
            }
        }

        $totalSize = ($files | Measure-Object -Property { $_.Size } -Sum).Sum

        return @{
            ScanType = 'large_files'
            Tool = 'czkawka'
            Files = $files
            Stats = @{
                TotalFiles = $files.Count
                TotalSize = $totalSize
                TotalSizeFormatted = Format-FileSize $totalSize
            }
        }
    }
    catch {
        Write-LogWarn "czkawka failed, using native: $_"
        return $null
    }
}

function Get-FileSuggestions {
    <#
    .SYNOPSIS
        Generates cleanup suggestions for a file.
    #>
    param($File)

    $suggestions = @()
    $category = Get-FileCategory $File.FullName

    # Age-based suggestions
    $daysSinceAccess = ((Get-Date) - $File.LastAccessTime).TotalDays

    if ($daysSinceAccess -gt 365) {
        $suggestions += 'archive'
        $suggestions += 'delete'
    }
    elseif ($daysSinceAccess -gt 180) {
        $suggestions += 'archive'
    }

    # Category-based suggestions
    switch ($category) {
        'archives' {
            $suggestions += 'extract_and_delete'
        }
        'videos' {
            if ($File.Length -gt 1GB) {
                $suggestions += 'compress'
                $suggestions += 'move_to_external'
            }
        }
        'images' {
            if ($File.Length -gt 10MB) {
                $suggestions += 'compress'
            }
        }
    }

    # Log files
    if ($File.Extension -in @('.log', '.txt', '.tmp')) {
        $suggestions += 'delete'
    }

    return $suggestions | Select-Object -Unique
}

function Format-LargeFilesResult {
    <#
    .SYNOPSIS
        Formats the large files result for output.
    #>
    param(
        $Result,
        [switch]$JsonOutput
    )

    if ($JsonOutput) {
        return $Result | ConvertTo-Json -Depth 10
    }

    Write-Divider
    Write-Header "Large Files Report"

    if ($Result.Stats.TotalFiles -eq 0) {
        Write-LogSuccess "No files found above threshold"
        return $Result
    }

    Write-KeyValue "Files Found" $Result.Stats.TotalFiles
    Write-KeyValue "Total Size" $Result.Stats.TotalSizeFormatted
    Write-KeyValue "Threshold" $Result.Threshold

    Write-Divider
    Write-LogInfo "Largest files:"
    Write-Host ""

    $showCount = [Math]::Min(20, $Result.Files.Count)

    for ($i = 0; $i -lt $showCount; $i++) {
        $file = $Result.Files[$i]

        # Format line
        $sizeStr = $file.SizeFormatted.PadLeft(10)
        Write-Host "  $sizeStr  " -NoNewline -ForegroundColor Cyan
        Write-Host $file.Path -ForegroundColor White

        # Show suggestions if any
        if ($file.Recommendations) {
            Write-Host "             Suggestions: $($file.Recommendations -join ', ')" -ForegroundColor DarkGray
        }
    }

    if ($Result.Files.Count -gt $showCount) {
        Write-Host ""
        Write-LogInfo "... and $($Result.Files.Count - $showCount) more files"
    }

    return $Result
}

function Get-DiskUsageSummary {
    <#
    .SYNOPSIS
        Gets a disk usage summary for a path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = $PWD.Path,

        [int]$Depth = 1,

        [switch]$JsonOutput
    )

    Write-LogStep "Analyzing disk usage..."
    $timer = Start-Timer

    $normalizedPath = Get-NormalizedPath $Path

    if (-not (Test-Path $normalizedPath -PathType Container)) {
        Write-LogError "Directory not found: $normalizedPath"
        return
    }

    # Get immediate child directories with sizes
    $items = Get-ChildItem -Path $normalizedPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $dir = $_
        $size = (Get-ChildItem -Path $dir.FullName -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum

        @{
            Name = $dir.Name
            Path = $dir.FullName
            Size = $size
            SizeFormatted = Format-FileSize $size
        }
    } | Sort-Object { $_.Size } -Descending

    # Get files in root
    $rootFiles = Get-ChildItem -Path $normalizedPath -File -ErrorAction SilentlyContinue
    $rootFilesSize = ($rootFiles | Measure-Object -Property Length -Sum).Sum

    $totalSize = ($items | Measure-Object -Property { $_.Size } -Sum).Sum
    $totalSize += $rootFilesSize

    # Add percentage
    $items = $items | ForEach-Object {
        $_.Percentage = if ($totalSize -gt 0) { [Math]::Round(($_.Size / $totalSize) * 100, 1) } else { 0 }
        $_
    }

    $result = @{
        ScanType = 'disk_usage'
        Path = $normalizedPath
        Timestamp = (Get-Date).ToString('o')
        Directories = @($items)
        RootFilesSize = $rootFilesSize
        RootFilesSizeFormatted = Format-FileSize $rootFilesSize
        Stats = @{
            TotalSize = $totalSize
            TotalSizeFormatted = Format-FileSize $totalSize
            DirectoryCount = $items.Count
            RootFileCount = $rootFiles.Count
        }
    }

    Stop-Timer $timer "Disk usage analysis"

    if ($JsonOutput) {
        return $result | ConvertTo-Json -Depth 10
    }

    # Visual output
    Write-Divider
    Write-Header "Disk Usage: $normalizedPath"

    Write-KeyValue "Total Size" $result.Stats.TotalSizeFormatted
    Write-KeyValue "Directories" $result.Stats.DirectoryCount
    Write-KeyValue "Files in Root" $result.Stats.RootFileCount

    Write-Divider
    Write-Host ""

    $barWidth = 30

    foreach ($item in ($items | Select-Object -First 15)) {
        $filled = [Math]::Round(($item.Percentage / 100) * $barWidth)
        $empty = $barWidth - $filled
        $bar = ('█' * $filled) + ('░' * $empty)

        $pctStr = "$($item.Percentage)%".PadLeft(6)
        $sizeStr = $item.SizeFormatted.PadLeft(10)

        Write-Host "  $bar " -NoNewline -ForegroundColor Cyan
        Write-Host "$pctStr " -NoNewline -ForegroundColor Yellow
        Write-Host "$sizeStr  " -NoNewline -ForegroundColor White
        Write-Host $item.Name -ForegroundColor Gray
    }

    if ($items.Count -gt 15) {
        Write-Host ""
        Write-LogInfo "... and $($items.Count - 15) more directories"
    }

    return $result
}

# Export functions
Export-ModuleMember -Function @(
    'Find-LargeFiles',
    'Get-DiskUsageSummary'
)
