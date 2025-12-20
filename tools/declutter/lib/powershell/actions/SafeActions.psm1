#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Safe File Actions Module

.DESCRIPTION
    Safe file operations with dry-run, trash support, and undo capability.
    All operations are logged for auditing and restoration.
#>

# Import core modules
$ModuleRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $ModuleRoot 'core/Platform.psm1') -Force
Import-Module (Join-Path $ModuleRoot 'core/Logger.psm1') -Force

#region Configuration

# Action state
$script:DryRun = $false
$script:UseTrash = $true
$script:Journal = @()
$script:JournalPath = $null

function Set-ActionConfig {
    <#
    .SYNOPSIS
        Configures action behavior.
    #>
    param(
        [switch]$DryRun,
        [switch]$NoTrash,
        [string]$JournalPath
    )

    $script:DryRun = $DryRun.IsPresent
    $script:UseTrash = -not $NoTrash.IsPresent

    if ($JournalPath) {
        $script:JournalPath = $JournalPath
        # Load existing journal if present
        if (Test-Path $JournalPath) {
            $script:Journal = Get-Content $JournalPath | ConvertFrom-Json
        }
    }
    else {
        # Default journal location
        $dataDir = if (Test-IsWindows) {
            Join-Path $env:LOCALAPPDATA 'declutter'
        }
        else {
            Join-Path $env:HOME '.local/share/declutter'
        }

        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        }

        $script:JournalPath = Join-Path $dataDir 'journal.json'
    }

    if ($DryRun) {
        Show-DryRunBanner
    }
}

function Test-IsDryRun {
    return $script:DryRun
}

#endregion

#region Journal Operations

function Add-JournalEntry {
    <#
    .SYNOPSIS
        Adds an entry to the action journal.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('delete', 'move', 'rename', 'compress')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$Source,

        [string]$Destination,

        [hashtable]$Metadata
    )

    $entry = @{
        Id = [Guid]::NewGuid().ToString()
        Timestamp = (Get-Date).ToString('o')
        Action = $Action
        Source = $Source
        Destination = $Destination
        Metadata = $Metadata
        Reversible = $true
        Reversed = $false
    }

    $script:Journal += $entry

    # Save journal
    if ($script:JournalPath) {
        $script:Journal | ConvertTo-Json -Depth 10 | Set-Content $script:JournalPath
    }

    return $entry.Id
}

function Get-JournalHistory {
    <#
    .SYNOPSIS
        Gets recent journal entries.
    #>
    param(
        [int]$Count = 20
    )

    return $script:Journal |
           Where-Object { -not $_.Reversed } |
           Select-Object -Last $Count
}

function Undo-JournalEntry {
    <#
    .SYNOPSIS
        Reverses a journal entry.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    $entry = $script:Journal | Where-Object { $_.Id -eq $Id }

    if (-not $entry) {
        Write-LogError "Journal entry not found: $Id"
        return $false
    }

    if (-not $entry.Reversible) {
        Write-LogError "Action is not reversible"
        return $false
    }

    if ($entry.Reversed) {
        Write-LogWarn "Action already reversed"
        return $false
    }

    Write-LogStep "Undoing: $($entry.Action) on $($entry.Source)"

    $success = switch ($entry.Action) {
        'delete' {
            # Restore from trash
            if ($entry.Destination -and (Test-Path $entry.Destination)) {
                Move-Item -LiteralPath $entry.Destination -Destination $entry.Source -Force
                $true
            }
            else {
                Write-LogError "Cannot restore - file not in trash"
                $false
            }
        }
        'move' {
            if (Test-Path $entry.Destination) {
                Move-Item -LiteralPath $entry.Destination -Destination $entry.Source -Force
                $true
            }
            else {
                Write-LogError "File not found at destination"
                $false
            }
        }
        'rename' {
            if (Test-Path $entry.Destination) {
                Rename-Item -LiteralPath $entry.Destination -NewName (Split-Path $entry.Source -Leaf) -Force
                $true
            }
            else {
                Write-LogError "Renamed file not found"
                $false
            }
        }
        default {
            Write-LogError "Unknown action type: $($entry.Action)"
            $false
        }
    }

    if ($success) {
        $entry.Reversed = $true
        $script:Journal | ConvertTo-Json -Depth 10 | Set-Content $script:JournalPath
        Write-LogSuccess "Undo completed"
    }

    return $success
}

function Undo-LastAction {
    <#
    .SYNOPSIS
        Undoes the most recent reversible action.
    #>
    param(
        [int]$Count = 1
    )

    $entries = $script:Journal |
               Where-Object { $_.Reversible -and -not $_.Reversed } |
               Select-Object -Last $Count

    foreach ($entry in $entries) {
        Undo-JournalEntry -Id $entry.Id
    }
}

#endregion

#region Delete Operations

function Remove-SafeItem {
    <#
    .SYNOPSIS
        Safely deletes a file or directory (moves to trash by default).

    .PARAMETER Path
        Path to delete.

    .PARAMETER Permanent
        Permanently delete instead of moving to trash.

    .PARAMETER Force
        Skip confirmation prompts.

    .EXAMPLE
        Remove-SafeItem -Path "C:\temp\old_file.txt"

    .EXAMPLE
        Remove-SafeItem -Path "D:\large_folder" -Permanent
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('FullName')]
        [string]$Path,

        [switch]$Permanent,

        [switch]$Force
    )

    process {
        $normalizedPath = Get-NormalizedPath $Path

        # Safety check
        if (-not (Test-IsSafePath $normalizedPath)) {
            Write-LogError "Refusing to delete protected path: $normalizedPath"
            return $false
        }

        if (-not (Test-Path $normalizedPath)) {
            Write-LogWarn "Path not found: $normalizedPath"
            return $false
        }

        # Get metadata for journaling
        $item = Get-Item -LiteralPath $normalizedPath -Force
        $metadata = @{
            Size = if ($item.PSIsContainer) {
                (Get-ChildItem -LiteralPath $normalizedPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                 Measure-Object -Property Length -Sum).Sum
            } else { $item.Length }
            IsDirectory = $item.PSIsContainer
            CreatedTime = $item.CreationTime.ToString('o')
            ModifiedTime = $item.LastWriteTime.ToString('o')
        }

        # Dry run
        if (Test-IsDryRun) {
            Write-LogInfo "[DRY-RUN] Would delete: $normalizedPath"
            return $true
        }

        # Confirmation
        if (-not $Force -and -not $PSCmdlet.ShouldProcess($normalizedPath, 'Delete')) {
            return $false
        }

        try {
            $destination = $null

            if ($Permanent -or -not $script:UseTrash) {
                # Permanent delete
                Remove-Item -LiteralPath $normalizedPath -Recurse -Force
                Write-LogSuccess "Permanently deleted: $normalizedPath"
            }
            else {
                # Move to trash
                $trashResult = Move-ToTrash -Path $normalizedPath

                if ($trashResult) {
                    $destination = Get-TrashPath
                    Write-LogSuccess "Moved to trash: $normalizedPath"
                }
                else {
                    Write-LogError "Failed to move to trash: $normalizedPath"
                    return $false
                }
            }

            # Journal entry
            Add-JournalEntry -Action 'delete' -Source $normalizedPath -Destination $destination -Metadata $metadata

            return $true
        }
        catch {
            Write-LogError "Failed to delete: $_"
            return $false
        }
    }
}

function Remove-EmptyDirectories {
    <#
    .SYNOPSIS
        Removes empty directories recursively.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [switch]$Force
    )

    $normalizedPath = Get-NormalizedPath $Path

    if (-not (Test-Path $normalizedPath -PathType Container)) {
        Write-LogError "Directory not found: $normalizedPath"
        return
    }

    Write-LogStep "Scanning for empty directories..."

    # Find empty directories (bottom-up)
    $emptyDirs = @()

    do {
        $found = Get-ChildItem -Path $normalizedPath -Directory -Recurse |
                 Where-Object {
                     (Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0
                 }

        $emptyDirs += $found

        foreach ($dir in $found) {
            if (Test-IsDryRun) {
                Write-LogInfo "[DRY-RUN] Would remove: $($dir.FullName)"
            }
            elseif ($Force -or $PSCmdlet.ShouldProcess($dir.FullName, 'Remove empty directory')) {
                Remove-Item -LiteralPath $dir.FullName -Force
                Write-LogDebug "Removed: $($dir.FullName)"
            }
        }
    } while ($found.Count -gt 0 -and -not (Test-IsDryRun))

    Write-LogSuccess "Removed $($emptyDirs.Count) empty directories"

    return @{
        Removed = $emptyDirs.Count
        Directories = $emptyDirs | ForEach-Object { $_.FullName }
    }
}

#endregion

#region Move Operations

function Move-SafeItem {
    <#
    .SYNOPSIS
        Safely moves a file or directory with conflict handling.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('FullName')]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [string]$Destination,

        [switch]$Force,

        [ValidateSet('Skip', 'Rename', 'Overwrite')]
        [string]$ConflictAction = 'Rename'
    )

    process {
        $sourcePath = Get-NormalizedPath $Path
        $destPath = Get-NormalizedPath $Destination

        if (-not (Test-Path $sourcePath)) {
            Write-LogError "Source not found: $sourcePath"
            return $false
        }

        # Safety check
        if (-not (Test-IsSafePath $sourcePath)) {
            Write-LogError "Refusing to move protected path: $sourcePath"
            return $false
        }

        # Handle destination directory
        if (Test-Path $destPath -PathType Container) {
            $fileName = Split-Path $sourcePath -Leaf
            $destPath = Join-Path $destPath $fileName
        }
        else {
            # Ensure parent directory exists
            $parentDir = Split-Path $destPath -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
        }

        # Handle conflicts
        if (Test-Path $destPath) {
            switch ($ConflictAction) {
                'Skip' {
                    Write-LogWarn "Skipping (destination exists): $destPath"
                    return $false
                }
                'Rename' {
                    $counter = 1
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($destPath)
                    $ext = [System.IO.Path]::GetExtension($destPath)
                    $dir = Split-Path $destPath -Parent

                    while (Test-Path $destPath) {
                        $destPath = Join-Path $dir "$baseName ($counter)$ext"
                        $counter++
                    }
                    Write-LogDebug "Renamed to: $destPath"
                }
                'Overwrite' {
                    # Will overwrite
                }
            }
        }

        # Dry run
        if (Test-IsDryRun) {
            Write-LogInfo "[DRY-RUN] Would move: $sourcePath -> $destPath"
            return $true
        }

        try {
            Move-Item -LiteralPath $sourcePath -Destination $destPath -Force:$Force

            # Journal entry
            Add-JournalEntry -Action 'move' -Source $sourcePath -Destination $destPath

            Write-LogSuccess "Moved: $sourcePath -> $destPath"
            return $true
        }
        catch {
            Write-LogError "Failed to move: $_"
            return $false
        }
    }
}

#endregion

#region Rename Operations

function Rename-SafeItem {
    <#
    .SYNOPSIS
        Safely renames a file with pattern support.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
        [Alias('FullName')]
        [string]$Path,

        [Parameter(Mandatory, Position = 1)]
        [string]$NewName,

        [switch]$Force
    )

    process {
        $sourcePath = Get-NormalizedPath $Path

        if (-not (Test-Path $sourcePath)) {
            Write-LogError "Path not found: $sourcePath"
            return $false
        }

        $item = Get-Item -LiteralPath $sourcePath
        $parentDir = Split-Path $sourcePath -Parent
        $destPath = Join-Path $parentDir $NewName

        # Conflict check
        if ((Test-Path $destPath) -and -not $Force) {
            Write-LogError "Destination already exists: $destPath"
            return $false
        }

        # Dry run
        if (Test-IsDryRun) {
            Write-LogInfo "[DRY-RUN] Would rename: $($item.Name) -> $NewName"
            return $true
        }

        try {
            Rename-Item -LiteralPath $sourcePath -NewName $NewName -Force:$Force

            # Journal entry
            Add-JournalEntry -Action 'rename' -Source $sourcePath -Destination $destPath

            Write-LogSuccess "Renamed: $($item.Name) -> $NewName"
            return $true
        }
        catch {
            Write-LogError "Failed to rename: $_"
            return $false
        }
    }
}

function Rename-ByPattern {
    <#
    .SYNOPSIS
        Renames multiple files using a pattern.

    .PARAMETER Path
        Directory containing files to rename.

    .PARAMETER Filter
        Filter pattern for files to include.

    .PARAMETER Pattern
        Rename pattern using placeholders:
        {original} - Original filename (without extension)
        {ext} - File extension
        {date} - Date (yyyy-MM-dd)
        {datetime} - Date and time
        {counter} - Auto-increment number

    .EXAMPLE
        Rename-ByPattern -Path "~/Photos" -Filter "*.jpg" -Pattern "{date}_{original}"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$Filter = '*',

        [Parameter(Mandatory)]
        [string]$Pattern,

        [switch]$Recurse,

        [switch]$Force
    )

    $normalizedPath = Get-NormalizedPath $Path

    $files = Get-ChildItem -Path $normalizedPath -Filter $Filter -File -Recurse:$Recurse

    $counter = 1
    $date = Get-Date -Format 'yyyy-MM-dd'
    $datetime = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'

    foreach ($file in $files) {
        $original = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $ext = $file.Extension

        $newName = $Pattern
        $newName = $newName -replace '\{original\}', $original
        $newName = $newName -replace '\{ext\}', $ext.TrimStart('.')
        $newName = $newName -replace '\{date\}', $date
        $newName = $newName -replace '\{datetime\}', $datetime
        $newName = $newName -replace '\{counter\}', $counter.ToString('D4')
        $newName = $newName -replace '\{counter:(\d+)\}', { param($m) $counter.ToString('D' + $m.Groups[1].Value) }

        # Add extension if not in pattern
        if (-not $newName.EndsWith($ext)) {
            $newName += $ext
        }

        Rename-SafeItem -Path $file.FullName -NewName $newName -Force:$Force
        $counter++
    }
}

#endregion

#region Organize Operations

function Move-ToCategory {
    <#
    .SYNOPSIS
        Organizes files into category folders.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$Destination,

        [switch]$Recurse,

        [switch]$Force
    )

    $sourcePath = Get-NormalizedPath $Path
    $destPath = if ($Destination) { Get-NormalizedPath $Destination } else { $sourcePath }

    if (-not (Test-Path $sourcePath)) {
        Write-LogError "Path not found: $sourcePath"
        return
    }

    Write-LogStep "Organizing files by category..."

    $files = Get-ChildItem -Path $sourcePath -File -Recurse:$Recurse
    $moved = 0

    foreach ($file in $files) {
        $category = Get-FileCategory $file.FullName

        if ($category -ne 'other') {
            $categoryDir = Join-Path $destPath $category

            if (-not (Test-Path $categoryDir)) {
                if (-not (Test-IsDryRun)) {
                    New-Item -ItemType Directory -Path $categoryDir -Force | Out-Null
                }
            }

            if (Move-SafeItem -Path $file.FullName -Destination $categoryDir -Force:$Force) {
                $moved++
            }
        }
    }

    Write-LogSuccess "Organized $moved files into category folders"

    return @{
        MovedCount = $moved
        Destination = $destPath
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Set-ActionConfig',
    'Test-IsDryRun',
    'Add-JournalEntry',
    'Get-JournalHistory',
    'Undo-JournalEntry',
    'Undo-LastAction',
    'Remove-SafeItem',
    'Remove-EmptyDirectories',
    'Move-SafeItem',
    'Rename-SafeItem',
    'Rename-ByPattern',
    'Move-ToCategory'
)
