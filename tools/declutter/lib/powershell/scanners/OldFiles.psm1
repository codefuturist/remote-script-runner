#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Old/Unused Files Scanner Module

.DESCRIPTION
    Finds files that haven't been accessed or modified in a specified timeframe.
    Useful for identifying stale downloads, temp files, and unused data.
#>

# Import core modules
$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot 'core/Platform.psm1') -Force
Import-Module (Join-Path $ModuleRoot 'core/Logger.psm1') -Force

function Find-OldFiles {
    <#
    .SYNOPSIS
        Finds files not accessed or modified within the specified number of days.

    .PARAMETER Path
        Path(s) to scan.

    .PARAMETER Days
        Number of days (default: 90). Files older than this are reported.

    .PARAMETER UseAccessTime
        Use last access time instead of modification time (default: true).

    .PARAMETER MinSize
        Minimum file size to consider (default: 0).

    .EXAMPLE
        Find-OldFiles -Path "~/Downloads" -Days 30

    .EXAMPLE
        Find-OldFiles -Path "D:\Projects" -Days 180 -UseAccessTime:$false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Path = $PWD.Path,

        [Alias('Age', 'OlderThan')]
        [int]$Days = 90,

        [switch]$UseAccessTime = $true,

        [string]$MinSize = '0',

        [switch]$IncludeHidden,

        [switch]$NoRecursive,

        [int]$Limit = 100,

        [switch]$JsonOutput
    )

    Write-LogStep "Scanning for files older than $Days days..."
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

    $minBytes = ConvertTo-Bytes $MinSize
    $cutoffDate = (Get-Date).AddDays(-$Days)

    Write-LogDebug "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd'))"
    Write-LogDebug "Using $(if ($UseAccessTime) {'access'} else {'modification'}) time"

    $allFiles = @()

    foreach ($p in $normalizedPaths) {
        $getParams = @{
            Path = $p
            File = $true
            Recurse = (-not $NoRecursive)
            ErrorAction = 'SilentlyContinue'
        }

        $files = Get-ChildItem @getParams | Where-Object {
            $_.Length -ge $minBytes -and
            (if ($UseAccessTime) { $_.LastAccessTime } else { $_.LastWriteTime }) -lt $cutoffDate
        }

        $allFiles += $files
    }

    Write-LogDebug "Found $($allFiles.Count) old files"

    # Sort by age (oldest first)
    $sortedFiles = if ($UseAccessTime) {
        $allFiles | Sort-Object LastAccessTime
    } else {
        $allFiles | Sort-Object LastWriteTime
    }

    # Limit results
    if ($Limit -gt 0) {
        $sortedFiles = $sortedFiles | Select-Object -First $Limit
    }

    # Build result
    $files = $sortedFiles | ForEach-Object {
        $timeValue = if ($UseAccessTime) { $_.LastAccessTime } else { $_.LastWriteTime }
        $daysOld = [Math]::Round(((Get-Date) - $timeValue).TotalDays)

        @{
            Path = $_.FullName
            Name = $_.Name
            Size = $_.Length
            SizeFormatted = Format-FileSize $_.Length
            LastAccessTime = $_.LastAccessTime.ToString('o')
            LastModifiedTime = $_.LastWriteTime.ToString('o')
            DaysOld = $daysOld
            Category = Get-FileCategory $_.FullName
            Suggestion = Get-OldFileSuggestion -DaysOld $daysOld -Category (Get-FileCategory $_.FullName)
        }
    }

    # Group by category for stats
    $byCategory = $files | Group-Object { $_.Category }

    $totalSize = ($sortedFiles | Measure-Object -Property Length -Sum).Sum

    $result = @{
        ScanType = 'old_files'
        Days = $Days
        UseAccessTime = $UseAccessTime.IsPresent
        CutoffDate = $cutoffDate.ToString('o')
        Timestamp = (Get-Date).ToString('o')
        Files = @($files)
        ByCategory = @($byCategory | ForEach-Object {
            @{
                Category = $_.Name
                Count = $_.Count
                Size = ($_.Group | Measure-Object -Property { $_.Size } -Sum).Sum
            }
        })
        Stats = @{
            TotalFiles = $files.Count
            TotalSize = $totalSize
            TotalSizeFormatted = Format-FileSize $totalSize
            OldestFile = if ($files.Count -gt 0) { $files[0].DaysOld } else { 0 }
        }
    }

    Stop-Timer $timer "Old files scan"
    return Format-OldFilesResult -Result $result -JsonOutput:$JsonOutput
}

function Get-OldFileSuggestion {
    <#
    .SYNOPSIS
        Suggests action for an old file based on age and category.
    #>
    param(
        [int]$DaysOld,
        [string]$Category
    )

    # Very old files
    if ($DaysOld -gt 365) {
        switch ($Category) {
            'documents' { return 'archive' }
            'images'    { return 'archive' }
            'videos'    { return 'archive_or_delete' }
            'code'      { return 'review' }
            default     { return 'delete' }
        }
    }

    # Moderately old
    if ($DaysOld -gt 180) {
        switch ($Category) {
            'archives'    { return 'delete' }
            'executables' { return 'delete' }
            'data'        { return 'review' }
            default       { return 'archive' }
        }
    }

    return 'review'
}

function Format-OldFilesResult {
    param(
        $Result,
        [switch]$JsonOutput
    )

    if ($JsonOutput) {
        return $Result | ConvertTo-Json -Depth 10
    }

    Write-Divider
    Write-Header "Old Files Report (>$($Result.Days) days)"

    if ($Result.Stats.TotalFiles -eq 0) {
        Write-LogSuccess "No old files found!"
        return $Result
    }

    Write-KeyValue "Files Found" $Result.Stats.TotalFiles
    Write-KeyValue "Total Size" $Result.Stats.TotalSizeFormatted
    Write-KeyValue "Oldest File" "$($Result.Stats.OldestFile) days old"

    # Category breakdown
    Write-Divider
    Write-LogInfo "By category:"

    foreach ($cat in ($Result.ByCategory | Sort-Object { $_.Size } -Descending)) {
        $sizeStr = (Format-FileSize $cat.Size).PadLeft(10)
        Write-Host "  $sizeStr  $($cat.Category) ($($cat.Count) files)" -ForegroundColor Gray
    }

    Write-Divider
    Write-LogInfo "Oldest files:"
    Write-Host ""

    $showCount = [Math]::Min(15, $Result.Files.Count)

    for ($i = 0; $i -lt $showCount; $i++) {
        $file = $Result.Files[$i]

        $ageStr = "$($file.DaysOld)d".PadLeft(6)
        $sizeStr = $file.SizeFormatted.PadLeft(10)

        $ageColor = if ($file.DaysOld -gt 365) { 'Red' } elseif ($file.DaysOld -gt 180) { 'Yellow' } else { 'Gray' }

        Write-Host "  " -NoNewline
        Write-Host $ageStr -NoNewline -ForegroundColor $ageColor
        Write-Host " $sizeStr  " -NoNewline -ForegroundColor Cyan
        Write-Host $file.Path -ForegroundColor White
    }

    if ($Result.Files.Count -gt $showCount) {
        Write-Host ""
        Write-LogInfo "... and $($Result.Files.Count - $showCount) more files"
    }

    return $Result
}

function Find-TempFiles {
    <#
    .SYNOPSIS
        Finds temporary and cache files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Path = $PWD.Path,

        [switch]$IncludeSystem,

        [switch]$JsonOutput
    )

    Write-LogStep "Scanning for temporary files..."
    $timer = Start-Timer

    # Temp file patterns
    $tempPatterns = @(
        '*.tmp',
        '*.temp',
        '*.bak',
        '*.old',
        '*~',
        '*.swp',
        '*.swo',
        '*.log',
        'Thumbs.db',
        '.DS_Store',
        'desktop.ini',
        '*.cache',
        '*.pyc',
        '__pycache__',
        '.pytest_cache',
        '.mypy_cache',
        'node_modules/.cache',
        '.sass-cache',
        '.parcel-cache'
    )

    $normalizedPaths = $Path | ForEach-Object { Get-NormalizedPath $_ }

    $allFiles = @()

    foreach ($p in $normalizedPaths) {
        foreach ($pattern in $tempPatterns) {
            $files = Get-ChildItem -Path $p -Filter $pattern -Recurse -ErrorAction SilentlyContinue
            $allFiles += $files
        }
    }

    # Include system temp if requested
    if ($IncludeSystem) {
        $systemTempPaths = @()

        if (Test-IsWindows) {
            $systemTempPaths += $env:TEMP
            $systemTempPaths += $env:TMP
            $systemTempPaths += "$env:LOCALAPPDATA\Temp"
        }
        else {
            $systemTempPaths += '/tmp'
            $systemTempPaths += "$env:HOME/Library/Caches"  # macOS
            $systemTempPaths += "$env:HOME/.cache"  # Linux
        }

        foreach ($tempPath in $systemTempPaths) {
            if (Test-Path $tempPath) {
                $files = Get-ChildItem -Path $tempPath -Recurse -File -ErrorAction SilentlyContinue
                $allFiles += $files
            }
        }
    }

    # Remove duplicates
    $uniqueFiles = $allFiles | Sort-Object FullName -Unique

    $files = $uniqueFiles | ForEach-Object {
        @{
            Path = $_.FullName
            Name = $_.Name
            Size = $_.Length
            SizeFormatted = Format-FileSize $_.Length
            ModifiedTime = $_.LastWriteTime.ToString('o')
            Type = Get-TempFileType $_.Name
        }
    } | Sort-Object { $_.Size } -Descending

    $totalSize = ($uniqueFiles | Measure-Object -Property Length -Sum).Sum

    $result = @{
        ScanType = 'temp_files'
        Timestamp = (Get-Date).ToString('o')
        Files = @($files)
        Stats = @{
            TotalFiles = $files.Count
            TotalSize = $totalSize
            TotalSizeFormatted = Format-FileSize $totalSize
        }
    }

    Stop-Timer $timer "Temp files scan"

    if ($JsonOutput) {
        return $result | ConvertTo-Json -Depth 10
    }

    Write-Divider
    Write-Header "Temporary Files Report"

    Write-KeyValue "Files Found" $result.Stats.TotalFiles
    Write-KeyValue "Total Size" $result.Stats.TotalSizeFormatted

    if ($files.Count -gt 0) {
        Write-Divider
        Write-LogInfo "Files found:"

        $showCount = [Math]::Min(20, $files.Count)
        for ($i = 0; $i -lt $showCount; $i++) {
            $file = $files[$i]
            $sizeStr = $file.SizeFormatted.PadLeft(10)
            Write-Host "  $sizeStr  $($file.Path)" -ForegroundColor Gray
        }

        if ($files.Count -gt $showCount) {
            Write-LogInfo "... and $($files.Count - $showCount) more"
        }
    }

    return $result
}

function Get-TempFileType {
    param([string]$FileName)

    switch -Wildcard ($FileName) {
        '*.tmp'          { return 'temporary' }
        '*.bak'          { return 'backup' }
        '*.log'          { return 'log' }
        '*.cache'        { return 'cache' }
        '*.pyc'          { return 'python_bytecode' }
        '__pycache__'    { return 'python_cache' }
        '.DS_Store'      { return 'macos_metadata' }
        'Thumbs.db'      { return 'windows_thumbnail' }
        'desktop.ini'    { return 'windows_config' }
        '*~'             { return 'editor_backup' }
        '*.swp'          { return 'vim_swap' }
        default          { return 'other' }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Find-OldFiles',
    'Find-TempFiles'
)
