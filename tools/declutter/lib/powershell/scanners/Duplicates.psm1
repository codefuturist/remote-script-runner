#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Duplicate Scanner Module

.DESCRIPTION
    Finds duplicate files using czkawka_cli or fallback hash-based detection.
    Supports exact and near-duplicate detection.
#>

# Import core modules
$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot 'core/Platform.psm1') -Force
Import-Module (Join-Path $ModuleRoot 'core/Logger.psm1') -Force

#region Duplicate Detection

function Find-DuplicateFiles {
    <#
    .SYNOPSIS
        Finds duplicate files in the specified path(s).

    .DESCRIPTION
        Uses czkawka_cli for duplicate detection when available, otherwise
        falls back to a PowerShell-native implementation using hash comparison.

    .PARAMETER Path
        One or more paths to scan for duplicates.

    .PARAMETER MinSize
        Minimum file size to consider (default: 1KB).

    .PARAMETER Algorithm
        Hash algorithm to use: MD5, SHA256, or XXHash (default: MD5).

    .PARAMETER IncludeHidden
        Include hidden files in the scan.

    .PARAMETER Recursive
        Scan subdirectories recursively (default: true).

    .EXAMPLE
        Find-DuplicateFiles -Path "C:\Users\Downloads" -MinSize 1MB

    .EXAMPLE
        Find-DuplicateFiles -Path @("D:\Photos", "E:\Backup\Photos")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Path,

        [Alias('MinimumSize')]
        [string]$MinSize = '1KB',

        [ValidateSet('MD5', 'SHA256', 'XXHash')]
        [string]$Algorithm = 'MD5',

        [switch]$IncludeHidden,

        [switch]$NoRecursive,

        [switch]$UseCzkawka,

        [switch]$JsonOutput
    )

    Write-LogStep "Scanning for duplicate files..."
    $timer = Start-Timer

    # Normalize paths
    $normalizedPaths = $Path | ForEach-Object { Get-NormalizedPath $_ }

    # Validate paths exist
    foreach ($p in $normalizedPaths) {
        if (-not (Test-Path $p)) {
            Write-LogError "Path not found: $p"
            return
        }
    }

    $minBytes = ConvertTo-Bytes $MinSize

    # Try czkawka first if available and requested
    if ($UseCzkawka -or (Test-CzkawkaInstalled)) {
        $result = Find-DuplicatesWithCzkawka -Paths $normalizedPaths -MinSize $minBytes -IncludeHidden:$IncludeHidden
        if ($null -ne $result) {
            Stop-Timer $timer "Duplicate scan"
            return Format-DuplicateResult -Result $result -JsonOutput:$JsonOutput
        }
    }

    # Fallback to native PowerShell implementation
    $result = Find-DuplicatesNative -Paths $normalizedPaths -MinSize $minBytes -Algorithm $Algorithm -IncludeHidden:$IncludeHidden -Recursive:(-not $NoRecursive)

    Stop-Timer $timer "Duplicate scan"
    return Format-DuplicateResult -Result $result -JsonOutput:$JsonOutput
}

#endregion

#region Czkawka Implementation

function Find-DuplicatesWithCzkawka {
    <#
    .SYNOPSIS
        Uses czkawka_cli for duplicate detection.
    #>
    param(
        [string[]]$Paths,
        [long]$MinSize,
        [switch]$IncludeHidden
    )

    $czkawkaPath = Get-CzkawkaPath
    if (-not $czkawkaPath) {
        Write-LogDebug "czkawka_cli not found, using native implementation"
        return $null
    }

    Write-LogDebug "Using czkawka_cli for duplicate detection"

    # Build command arguments
    $args = @('dup')

    # Add directories
    $args += '-d'
    $args += ($Paths -join ',')

    # Min size
    $args += '-s'
    $args += $MinSize.ToString()

    # Hash type
    $args += '-t'
    $args += 'HASH'

    # Output format (JSON for parsing)
    $args += '-f'
    $args += 'json'

    try {
        $output = & $czkawkaPath $args 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-LogWarn "czkawka returned non-zero exit code: $LASTEXITCODE"
            return $null
        }

        # Parse JSON output
        $jsonOutput = $output | Where-Object { $_ -match '^\s*[\[\{]' } | Out-String

        if ([string]::IsNullOrWhiteSpace($jsonOutput)) {
            return @{
                ScanType = 'duplicates'
                Tool = 'czkawka'
                Groups = @()
                Stats = @{
                    TotalGroups = 0
                    TotalDuplicates = 0
                    WastedSpace = 0
                }
            }
        }

        $parsed = $jsonOutput | ConvertFrom-Json
        return Convert-CzkawkaOutput -CzkawkaResult $parsed
    }
    catch {
        Write-LogWarn "Failed to run czkawka: $_"
        return $null
    }
}

function Convert-CzkawkaOutput {
    <#
    .SYNOPSIS
        Converts czkawka JSON output to our standard format.
    #>
    param($CzkawkaResult)

    $groups = @()
    $totalDuplicates = 0
    $wastedSpace = 0

    # czkawka outputs duplicate groups
    if ($CzkawkaResult -is [array]) {
        foreach ($group in $CzkawkaResult) {
            if ($group.files -and $group.files.Count -gt 1) {
                $files = @()
                foreach ($file in $group.files) {
                    $files += @{
                        Path = $file.path
                        Size = $file.size
                        ModifiedTime = $file.modified_date
                    }
                }

                $groups += @{
                    Hash = $group.hash
                    Size = $group.size
                    Files = $files
                    DuplicateCount = $files.Count - 1
                }

                $totalDuplicates += $files.Count - 1
                $wastedSpace += $group.size * ($files.Count - 1)
            }
        }
    }

    return @{
        ScanType = 'duplicates'
        Tool = 'czkawka'
        Groups = $groups
        Stats = @{
            TotalGroups = $groups.Count
            TotalDuplicates = $totalDuplicates
            WastedSpace = $wastedSpace
            WastedSpaceFormatted = Format-FileSize $wastedSpace
        }
    }
}

#endregion

#region Native PowerShell Implementation

function Find-DuplicatesNative {
    <#
    .SYNOPSIS
        PowerShell-native duplicate detection using file hashing.
    #>
    param(
        [string[]]$Paths,
        [long]$MinSize,
        [string]$Algorithm,
        [switch]$IncludeHidden,
        [switch]$Recursive
    )

    Write-LogDebug "Using native PowerShell duplicate detection"

    # Collect all files
    $allFiles = @()

    foreach ($path in $Paths) {
        $getParams = @{
            Path = $path
            File = $true
            Recurse = $Recursive
            ErrorAction = 'SilentlyContinue'
        }

        if (-not $IncludeHidden) {
            $getParams['Attributes'] = '!Hidden'
        }

        $files = Get-ChildItem @getParams | Where-Object { $_.Length -ge $MinSize }
        $allFiles += $files
    }

    Write-LogInfo "Found $($allFiles.Count) files to analyze"

    if ($allFiles.Count -eq 0) {
        return @{
            ScanType = 'duplicates'
            Tool = 'native'
            Groups = @()
            Stats = @{
                TotalGroups = 0
                TotalDuplicates = 0
                WastedSpace = 0
            }
        }
    }

    # Phase 1: Group by size (quick filter)
    Write-LogStep "Phase 1: Grouping by file size..."
    $sizeGroups = $allFiles | Group-Object Length | Where-Object { $_.Count -gt 1 }

    $candidateCount = ($sizeGroups | Measure-Object -Property Count -Sum).Sum
    Write-LogDebug "Found $candidateCount files with matching sizes in $($sizeGroups.Count) groups"

    if ($sizeGroups.Count -eq 0) {
        return @{
            ScanType = 'duplicates'
            Tool = 'native'
            Groups = @()
            Stats = @{
                TotalGroups = 0
                TotalDuplicates = 0
                WastedSpace = 0
            }
        }
    }

    # Phase 2: Partial hash (first 4KB)
    Write-LogStep "Phase 2: Computing partial hashes..."
    $partialHashGroups = @{}
    $processed = 0

    foreach ($group in $sizeGroups) {
        foreach ($file in $group.Group) {
            $processed++
            if ($processed % 100 -eq 0) {
                Write-Progress2 -Current $processed -Total $candidateCount -Label "Partial hashing..."
            }

            $partialHash = Get-PartialFileHash -Path $file.FullName
            if ($partialHash) {
                $key = "$($file.Length)_$partialHash"
                if (-not $partialHashGroups.ContainsKey($key)) {
                    $partialHashGroups[$key] = @()
                }
                $partialHashGroups[$key] += $file
            }
        }
    }

    # Filter to groups with multiple files
    $candidates = $partialHashGroups.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
    $candidateFiles = ($candidates | ForEach-Object { $_.Value } | Measure-Object).Count

    Write-LogDebug "Found $candidateFiles files with matching partial hashes"

    # Phase 3: Full hash
    Write-LogStep "Phase 3: Computing full hashes..."
    $fullHashGroups = @{}
    $processed = 0

    foreach ($entry in $candidates) {
        foreach ($file in $entry.Value) {
            $processed++
            Write-Progress2 -Current $processed -Total $candidateFiles -Label "Full hashing..."

            $fullHash = Get-FileHashFast -Path $file.FullName -Algorithm $Algorithm
            if ($fullHash) {
                if (-not $fullHashGroups.ContainsKey($fullHash)) {
                    $fullHashGroups[$fullHash] = @()
                }
                $fullHashGroups[$fullHash] += $file
            }
        }
    }

    # Build result
    $groups = @()
    $totalDuplicates = 0
    $wastedSpace = 0

    foreach ($entry in $fullHashGroups.GetEnumerator()) {
        if ($entry.Value.Count -gt 1) {
            $files = $entry.Value | ForEach-Object {
                @{
                    Path = $_.FullName
                    Size = $_.Length
                    ModifiedTime = $_.LastWriteTime.ToString('o')
                    AccessTime = $_.LastAccessTime.ToString('o')
                }
            }

            # Sort by modified time (oldest first - good candidate for deletion)
            $sortedFiles = $files | Sort-Object { [DateTime]$_.ModifiedTime }

            $fileSize = $entry.Value[0].Length

            $groups += @{
                Hash = $entry.Key
                Size = $fileSize
                SizeFormatted = Format-FileSize $fileSize
                Files = $sortedFiles
                DuplicateCount = $sortedFiles.Count - 1
                Recommendation = 'keep_newest'
            }

            $totalDuplicates += $sortedFiles.Count - 1
            $wastedSpace += $fileSize * ($sortedFiles.Count - 1)
        }
    }

    # Sort groups by wasted space (largest first)
    $groups = $groups | Sort-Object { $_.Size * $_.DuplicateCount } -Descending

    return @{
        ScanType = 'duplicates'
        Tool = 'native'
        Timestamp = (Get-Date).ToString('o')
        Groups = $groups
        Stats = @{
            TotalGroups = $groups.Count
            TotalDuplicates = $totalDuplicates
            WastedSpace = $wastedSpace
            WastedSpaceFormatted = Format-FileSize $wastedSpace
        }
    }
}

#endregion

#region Output Formatting

function Format-DuplicateResult {
    <#
    .SYNOPSIS
        Formats the duplicate scan result for output.
    #>
    param(
        $Result,
        [switch]$JsonOutput
    )

    if ($JsonOutput) {
        return $Result | ConvertTo-Json -Depth 10
    }

    # Human-readable output
    Write-Divider
    Write-Header "Duplicate Scan Results"

    if ($Result.Stats.TotalGroups -eq 0) {
        Write-LogSuccess "No duplicates found!"
        return $Result
    }

    Write-KeyValue "Tool Used" $Result.Tool
    Write-KeyValue "Duplicate Groups" $Result.Stats.TotalGroups
    Write-KeyValue "Total Duplicates" $Result.Stats.TotalDuplicates
    Write-KeyValue "Wasted Space" $Result.Stats.WastedSpaceFormatted

    Write-Divider

    # Show top duplicate groups
    $showCount = [Math]::Min(10, $Result.Groups.Count)
    Write-LogInfo "Top $showCount duplicate groups by wasted space:"
    Write-Host ""

    for ($i = 0; $i -lt $showCount; $i++) {
        $group = $Result.Groups[$i]
        $wasted = Format-FileSize ($group.Size * $group.DuplicateCount)

        Write-Host "  Group $($i + 1): " -NoNewline -ForegroundColor White
        Write-Host "$($group.SizeFormatted) × $($group.Files.Count) files " -NoNewline -ForegroundColor Cyan
        Write-Host "(wasting $wasted)" -ForegroundColor Yellow

        foreach ($file in $group.Files) {
            Write-Host "    • $($file.Path)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    if ($Result.Groups.Count -gt $showCount) {
        Write-LogInfo "... and $($Result.Groups.Count - $showCount) more groups"
    }

    return $Result
}

#endregion

#region Similar Image Detection

function Find-SimilarImages {
    <#
    .SYNOPSIS
        Finds visually similar images using czkawka or perceptual hashing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path,

        [ValidateRange(1, 40)]
        [int]$Similarity = 5,

        [switch]$IncludeHidden,

        [switch]$JsonOutput
    )

    Write-LogStep "Scanning for similar images..."
    $timer = Start-Timer

    # This requires czkawka
    if (-not (Test-CzkawkaInstalled)) {
        Write-LogError "Similar image detection requires czkawka_cli"
        Install-Czkawka
        return $null
    }

    $czkawkaPath = Get-CzkawkaPath
    $normalizedPaths = $Path | ForEach-Object { Get-NormalizedPath $_ }

    $args = @('image')
    $args += '-d'
    $args += ($normalizedPaths -join ',')
    $args += '-s'
    $args += $Similarity.ToString()
    $args += '-f'
    $args += 'json'

    try {
        $output = & $czkawkaPath $args 2>&1
        $jsonOutput = $output | Where-Object { $_ -match '^\s*[\[\{]' } | Out-String

        if ([string]::IsNullOrWhiteSpace($jsonOutput)) {
            $result = @{
                ScanType = 'similar_images'
                Groups = @()
                Stats = @{ TotalGroups = 0 }
            }
        }
        else {
            $parsed = $jsonOutput | ConvertFrom-Json
            $result = @{
                ScanType = 'similar_images'
                Groups = $parsed
                Stats = @{ TotalGroups = $parsed.Count }
            }
        }

        Stop-Timer $timer "Similar image scan"

        if ($JsonOutput) {
            return $result | ConvertTo-Json -Depth 10
        }

        return $result
    }
    catch {
        Write-LogError "Failed to scan for similar images: $_"
        return $null
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Find-DuplicateFiles',
    'Find-SimilarImages'
)
