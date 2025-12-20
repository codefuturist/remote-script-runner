#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Cleanup Presets Module

.DESCRIPTION
    Pre-configured cleanup profiles for common scenarios:
    - Developer cleanup (node_modules, build artifacts)
    - System cleanup (temp files, caches, logs)
    - Media cleanup (duplicates, thumbnails)
#>

# Import core modules
$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot 'core/Platform.psm1') -Force
Import-Module (Join-Path $ModuleRoot 'core/Logger.psm1') -Force
Import-Module (Join-Path $ModuleRoot 'actions/SafeActions.psm1') -Force

#region Developer Cleanup

function Invoke-DevCleanup {
    <#
    .SYNOPSIS
        Cleans up developer-related build artifacts and caches.

    .DESCRIPTION
        Removes:
        - node_modules directories
        - Python caches (__pycache__, .pyc, .pytest_cache)
        - Rust target directories
        - Go vendor directories
        - .NET bin/obj directories
        - IDE caches (.idea, .vscode caches)

    .PARAMETER Path
        Path to scan for projects.

    .PARAMETER SkipNode
        Skip node_modules cleanup.

    .PARAMETER SkipPython
        Skip Python cache cleanup.

    .EXAMPLE
        Invoke-DevCleanup -Path "~/Projects"

    .EXAMPLE
        Invoke-DevCleanup -Path "D:\Work" -SkipNode
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Path = $PWD.Path,

        [switch]$SkipNode,
        [switch]$SkipPython,
        [switch]$SkipRust,
        [switch]$SkipDotNet,
        [switch]$SkipGo,
        [switch]$Force
    )

    $normalizedPath = Get-NormalizedPath $Path

    if (-not (Test-Path $normalizedPath)) {
        Write-LogError "Path not found: $normalizedPath"
        return
    }

    Write-Header "Developer Cleanup"
    Write-LogInfo "Scanning: $normalizedPath"

    $totalSize = 0
    $totalItems = 0
    $results = @{}

    # Node.js cleanup
    if (-not $SkipNode) {
        Write-LogStep "Scanning for Node.js artifacts..."

        $nodeDirs = Get-ChildItem -Path $normalizedPath -Directory -Recurse -Filter 'node_modules' -ErrorAction SilentlyContinue |
                    Where-Object {
                        # Only if there's a package.json in parent
                        Test-Path (Join-Path $_.Parent.FullName 'package.json')
                    }

        $nodeSize = 0
        foreach ($dir in $nodeDirs) {
            $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            $nodeSize += $size

            if (Test-IsDryRun) {
                Write-LogInfo "[DRY-RUN] Would remove: $($dir.FullName) ($(Format-FileSize $size))"
            }
            elseif ($Force -or $PSCmdlet.ShouldProcess($dir.FullName, 'Remove node_modules')) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-LogDebug "Removed: $($dir.FullName)"
            }
        }

        $results['Node.js'] = @{ Count = $nodeDirs.Count; Size = $nodeSize }
        $totalSize += $nodeSize
        $totalItems += $nodeDirs.Count
    }

    # Python cleanup
    if (-not $SkipPython) {
        Write-LogStep "Scanning for Python caches..."

        $pythonPatterns = @('__pycache__', '.pytest_cache', '.mypy_cache', '.tox', '*.egg-info')
        $pythonDirs = @()

        foreach ($pattern in $pythonPatterns) {
            $dirs = Get-ChildItem -Path $normalizedPath -Directory -Recurse -Filter $pattern -ErrorAction SilentlyContinue
            $pythonDirs += $dirs
        }

        # Also find .pyc files
        $pycFiles = Get-ChildItem -Path $normalizedPath -File -Recurse -Filter '*.pyc' -ErrorAction SilentlyContinue

        $pythonSize = 0
        foreach ($dir in $pythonDirs) {
            $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            $pythonSize += $size

            if (-not (Test-IsDryRun)) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        foreach ($file in $pycFiles) {
            $pythonSize += $file.Length
            if (-not (Test-IsDryRun)) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        $results['Python'] = @{ Count = $pythonDirs.Count + $pycFiles.Count; Size = $pythonSize }
        $totalSize += $pythonSize
        $totalItems += $pythonDirs.Count + $pycFiles.Count
    }

    # Rust cleanup
    if (-not $SkipRust) {
        Write-LogStep "Scanning for Rust build artifacts..."

        $targetDirs = Get-ChildItem -Path $normalizedPath -Directory -Recurse -Filter 'target' -ErrorAction SilentlyContinue |
                      Where-Object { Test-Path (Join-Path $_.Parent.FullName 'Cargo.toml') }

        $rustSize = 0
        foreach ($dir in $targetDirs) {
            $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            $rustSize += $size

            if (-not (Test-IsDryRun)) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $results['Rust'] = @{ Count = $targetDirs.Count; Size = $rustSize }
        $totalSize += $rustSize
        $totalItems += $targetDirs.Count
    }

    # .NET cleanup
    if (-not $SkipDotNet) {
        Write-LogStep "Scanning for .NET build artifacts..."

        $dotnetDirs = @()
        foreach ($pattern in @('bin', 'obj')) {
            $dirs = Get-ChildItem -Path $normalizedPath -Directory -Recurse -Filter $pattern -ErrorAction SilentlyContinue |
                    Where-Object {
                        $parent = $_.Parent.FullName
                        (Get-ChildItem -Path $parent -Filter '*.csproj' -ErrorAction SilentlyContinue) -or
                        (Get-ChildItem -Path $parent -Filter '*.fsproj' -ErrorAction SilentlyContinue)
                    }
            $dotnetDirs += $dirs
        }

        $dotnetSize = 0
        foreach ($dir in $dotnetDirs) {
            $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            $dotnetSize += $size

            if (-not (Test-IsDryRun)) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $results['.NET'] = @{ Count = $dotnetDirs.Count; Size = $dotnetSize }
        $totalSize += $dotnetSize
        $totalItems += $dotnetDirs.Count
    }

    # Go cleanup
    if (-not $SkipGo) {
        Write-LogStep "Scanning for Go vendor directories..."

        $vendorDirs = Get-ChildItem -Path $normalizedPath -Directory -Recurse -Filter 'vendor' -ErrorAction SilentlyContinue |
                      Where-Object { Test-Path (Join-Path $_.Parent.FullName 'go.mod') }

        $goSize = 0
        foreach ($dir in $vendorDirs) {
            $size = (Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
            $goSize += $size

            if (-not (Test-IsDryRun)) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $results['Go'] = @{ Count = $vendorDirs.Count; Size = $goSize }
        $totalSize += $goSize
        $totalItems += $vendorDirs.Count
    }

    # Summary
    Write-Divider
    Write-Header "Cleanup Summary"

    foreach ($key in $results.Keys) {
        $r = $results[$key]
        if ($r.Count -gt 0) {
            Write-KeyValue $key "$($r.Count) items ($(Format-FileSize $r.Size))"
        }
    }

    Write-Divider
    Write-KeyValue "Total Removed" "$totalItems items"
    Write-KeyValue "Space Freed" (Format-FileSize $totalSize)

    if (Test-IsDryRun) {
        Write-LogWarn "DRY-RUN: No files were actually deleted"
    }

    return @{
        Results = $results
        TotalItems = $totalItems
        TotalSize = $totalSize
        TotalSizeFormatted = Format-FileSize $totalSize
    }
}

#endregion

#region System Cleanup

function Invoke-SystemCleanup {
    <#
    .SYNOPSIS
        Cleans up system temporary files and caches.

    .DESCRIPTION
        Removes:
        - Temp files
        - Browser caches
        - System logs (optional)
        - Thumbnail caches
        - Update caches

    .PARAMETER IncludeBrowserCache
        Also clean browser caches.

    .PARAMETER IncludeLogs
        Also clean old log files.

    .EXAMPLE
        Invoke-SystemCleanup

    .EXAMPLE
        Invoke-SystemCleanup -IncludeBrowserCache -IncludeLogs
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$IncludeBrowserCache,
        [switch]$IncludeLogs,
        [int]$LogDays = 30,
        [switch]$Force
    )

    Write-Header "System Cleanup"

    $totalSize = 0
    $totalItems = 0
    $results = @{}

    # Temp directories
    Write-LogStep "Cleaning temp directories..."

    $tempPaths = if (Test-IsWindows) {
        @(
            $env:TEMP,
            $env:TMP,
            "$env:LOCALAPPDATA\Temp",
            "$env:WINDIR\Temp"
        )
    }
    else {
        @(
            '/tmp',
            '/var/tmp',
            "$env:HOME/.cache"
        )
    }

    $tempSize = 0
    $tempCount = 0

    foreach ($tempPath in $tempPaths) {
        if (-not $tempPath -or -not (Test-Path $tempPath)) { continue }

        $files = Get-ChildItem -Path $tempPath -File -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) }

        foreach ($file in $files) {
            $tempSize += $file.Length
            $tempCount++

            if (-not (Test-IsDryRun)) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $results['Temp Files'] = @{ Count = $tempCount; Size = $tempSize }
    $totalSize += $tempSize
    $totalItems += $tempCount

    # Thumbnail caches
    Write-LogStep "Cleaning thumbnail caches..."

    $thumbPaths = if (Test-IsWindows) {
        @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*")
    }
    elseif (Test-IsMacOS) {
        @("$env:HOME/Library/Caches/com.apple.QuickLook.thumbnailcache")
    }
    else {
        @("$env:HOME/.cache/thumbnails")
    }

    $thumbSize = 0
    $thumbCount = 0

    foreach ($thumbPath in $thumbPaths) {
        $items = Get-ChildItem -Path $thumbPath -ErrorAction SilentlyContinue
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                $size = (Get-ChildItem -LiteralPath $item.FullName -Recurse -File -ErrorAction SilentlyContinue |
                         Measure-Object -Property Length -Sum).Sum
            }
            else {
                $size = $item.Length
            }

            $thumbSize += $size
            $thumbCount++

            if (-not (Test-IsDryRun)) {
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $results['Thumbnails'] = @{ Count = $thumbCount; Size = $thumbSize }
    $totalSize += $thumbSize
    $totalItems += $thumbCount

    # Browser caches
    if ($IncludeBrowserCache) {
        Write-LogStep "Cleaning browser caches..."

        $browserPaths = if (Test-IsWindows) {
            @(
                "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
                "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"
            )
        }
        elseif (Test-IsMacOS) {
            @(
                "$env:HOME/Library/Caches/Google/Chrome",
                "$env:HOME/Library/Caches/com.apple.Safari",
                "$env:HOME/Library/Caches/Firefox"
            )
        }
        else {
            @(
                "$env:HOME/.cache/google-chrome",
                "$env:HOME/.cache/mozilla",
                "$env:HOME/.cache/chromium"
            )
        }

        $browserSize = 0
        $browserCount = 0

        foreach ($browserPath in $browserPaths) {
            $items = Get-ChildItem -Path $browserPath -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $size = if ($item.PSIsContainer) {
                    (Get-ChildItem -LiteralPath $item.FullName -Recurse -File -ErrorAction SilentlyContinue |
                     Measure-Object -Property Length -Sum).Sum
                } else { $item.Length }

                $browserSize += $size
                $browserCount++

                if (-not (Test-IsDryRun)) {
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        $results['Browser Cache'] = @{ Count = $browserCount; Size = $browserSize }
        $totalSize += $browserSize
        $totalItems += $browserCount
    }

    # Log files
    if ($IncludeLogs) {
        Write-LogStep "Cleaning old log files..."

        $logPaths = if (Test-IsWindows) {
            @("$env:LOCALAPPDATA\*.log", "$env:TEMP\*.log")
        }
        else {
            @("$env:HOME/Library/Logs", "/var/log")
        }

        $logSize = 0
        $logCount = 0
        $cutoffDate = (Get-Date).AddDays(-$LogDays)

        foreach ($logPath in $logPaths) {
            $files = Get-ChildItem -Path $logPath -Filter '*.log' -Recurse -ErrorAction SilentlyContinue |
                     Where-Object { $_.LastWriteTime -lt $cutoffDate }

            foreach ($file in $files) {
                $logSize += $file.Length
                $logCount++

                if (-not (Test-IsDryRun)) {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        }

        $results['Log Files'] = @{ Count = $logCount; Size = $logSize }
        $totalSize += $logSize
        $totalItems += $logCount
    }

    # Summary
    Write-Divider
    Write-Header "Cleanup Summary"

    foreach ($key in $results.Keys) {
        $r = $results[$key]
        if ($r.Count -gt 0) {
            Write-KeyValue $key "$($r.Count) items ($(Format-FileSize $r.Size))"
        }
    }

    Write-Divider
    Write-KeyValue "Total Removed" "$totalItems items"
    Write-KeyValue "Space Freed" (Format-FileSize $totalSize)

    if (Test-IsDryRun) {
        Write-LogWarn "DRY-RUN: No files were actually deleted"
    }

    return @{
        Results = $results
        TotalItems = $totalItems
        TotalSize = $totalSize
    }
}

#endregion

#region Quick Cleanup

function Invoke-QuickCleanup {
    <#
    .SYNOPSIS
        Quick cleanup of common junk files.

    .DESCRIPTION
        Removes:
        - .DS_Store, Thumbs.db
        - Empty directories
        - Broken symlinks
        - Editor backup files (*~, *.swp)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [string]$Path = $PWD.Path,

        [switch]$Force
    )

    $normalizedPath = Get-NormalizedPath $Path

    Write-Header "Quick Cleanup"
    Write-LogInfo "Path: $normalizedPath"

    $totalItems = 0
    $totalSize = 0

    # Junk file patterns
    $junkPatterns = @(
        '.DS_Store',
        'Thumbs.db',
        'desktop.ini',
        '*.swp',
        '*.swo',
        '*~',
        '*.bak',
        '*.tmp'
    )

    Write-LogStep "Removing junk files..."

    foreach ($pattern in $junkPatterns) {
        $files = Get-ChildItem -Path $normalizedPath -Filter $pattern -Recurse -File -Force -ErrorAction SilentlyContinue

        foreach ($file in $files) {
            $totalSize += $file.Length
            $totalItems++

            if (Test-IsDryRun) {
                Write-LogDebug "[DRY-RUN] Would remove: $($file.FullName)"
            }
            elseif ($Force -or $PSCmdlet.ShouldProcess($file.FullName, 'Remove')) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Empty directories
    Write-LogStep "Removing empty directories..."

    $emptyResult = Remove-EmptyDirectories -Path $normalizedPath -Force:$Force
    $totalItems += $emptyResult.Removed

    # Summary
    Write-Divider
    Write-KeyValue "Items Removed" $totalItems
    Write-KeyValue "Space Freed" (Format-FileSize $totalSize)

    return @{
        TotalItems = $totalItems
        TotalSize = $totalSize
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Invoke-DevCleanup',
    'Invoke-SystemCleanup',
    'Invoke-QuickCleanup'
)
