#Requires -Version 5.1
<#
.SYNOPSIS
    Declutter - Cross-Platform Utilities Module

.DESCRIPTION
    Platform detection and abstraction layer for Windows/macOS/Linux compatibility.
    Provides unified APIs for file operations, trash management, and system queries.
#>

# Strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Platform Detection

function Get-Platform {
    <#
    .SYNOPSIS
        Detects the current operating system platform.
    #>
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        return 'Windows'
    }
    elseif ($IsMacOS) {
        return 'macOS'
    }
    elseif ($IsLinux) {
        return 'Linux'
    }
    else {
        # PowerShell 5.1 on Windows
        if ([System.Environment]::OSVersion.Platform -eq 'Win32NT') {
            return 'Windows'
        }
        return 'Unknown'
    }
}

function Test-IsWindows {
    return (Get-Platform) -eq 'Windows'
}

function Test-IsMacOS {
    return (Get-Platform) -eq 'macOS'
}

function Test-IsLinux {
    return (Get-Platform) -eq 'Linux'
}

function Test-IsUnix {
    $platform = Get-Platform
    return $platform -eq 'macOS' -or $platform -eq 'Linux'
}

#endregion

#region Path Utilities

function Get-NormalizedPath {
    <#
    .SYNOPSIS
        Normalizes a path for the current platform.
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Path
    )

    process {
        # Expand environment variables and user home
        $expanded = [Environment]::ExpandEnvironmentVariables($Path)

        # Handle ~ for home directory
        if ($expanded.StartsWith('~')) {
            $home = if (Test-IsWindows) { $env:USERPROFILE } else { $env:HOME }
            $expanded = Join-Path $home $expanded.Substring(1).TrimStart('/', '\')
        }

        # Resolve to absolute path
        try {
            $resolved = [System.IO.Path]::GetFullPath($expanded)
            return $resolved
        }
        catch {
            return $expanded
        }
    }
}

function Get-SafePath {
    <#
    .SYNOPSIS
        Returns path with proper separators for the platform.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-IsWindows) {
        return $Path -replace '/', '\'
    }
    else {
        return $Path -replace '\\', '/'
    }
}

function Test-IsSafePath {
    <#
    .SYNOPSIS
        Checks if a path is safe to operate on (not system-critical).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $normalizedPath = Get-NormalizedPath $Path

    # Define dangerous paths per platform
    $dangerousPaths = if (Test-IsWindows) {
        @(
            'C:\Windows',
            'C:\Windows\System32',
            'C:\Program Files',
            'C:\Program Files (x86)',
            'C:\ProgramData',
            $env:SystemRoot,
            $env:windir
        )
    }
    else {
        @(
            '/',
            '/bin',
            '/sbin',
            '/usr',
            '/etc',
            '/var',
            '/System',
            '/Library',
            '/Applications',
            '/private',
            (Join-Path $env:HOME '.ssh'),
            (Join-Path $env:HOME '.gnupg')
        )
    }

    foreach ($dangerous in $dangerousPaths) {
        if ($null -eq $dangerous) { continue }
        $dangerous = Get-NormalizedPath $dangerous
        if ($normalizedPath -eq $dangerous -or $normalizedPath.StartsWith("$dangerous$([IO.Path]::DirectorySeparatorChar)")) {
            return $false
        }
    }

    return $true
}

#endregion

#region File Size Utilities

function Format-FileSize {
    <#
    .SYNOPSIS
        Converts bytes to human-readable format.
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [long]$Bytes
    )

    process {
        $units = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
        $unitIndex = 0
        $size = [double]$Bytes

        while ($size -ge 1024 -and $unitIndex -lt ($units.Count - 1)) {
            $size /= 1024
            $unitIndex++
        }

        if ($unitIndex -eq 0) {
            return "{0} {1}" -f [math]::Round($size, 0), $units[$unitIndex]
        }
        return "{0:N2} {1}" -f $size, $units[$unitIndex]
    }
}

function ConvertTo-Bytes {
    <#
    .SYNOPSIS
        Converts human-readable size string to bytes.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Size
    )

    $Size = $Size.Trim().ToUpper()

    if ($Size -match '^([\d.]+)\s*(TB|GB|MB|KB|B)?$') {
        $number = [double]$Matches[1]
        $unit = if ($Matches[2]) { $Matches[2] } else { 'B' }

        switch ($unit) {
            'TB' { return [long]($number * 1TB) }
            'GB' { return [long]($number * 1GB) }
            'MB' { return [long]($number * 1MB) }
            'KB' { return [long]($number * 1KB) }
            'B'  { return [long]$number }
        }
    }

    throw "Invalid size format: $Size"
}

#endregion

#region Trash Operations

function Get-TrashPath {
    <#
    .SYNOPSIS
        Gets the platform-specific trash/recycle bin path.
    #>
    if (Test-IsWindows) {
        # Windows Recycle Bin is virtual, return $null
        return $null
    }
    elseif (Test-IsMacOS) {
        return Join-Path $env:HOME '.Trash'
    }
    else {
        # Linux uses freedesktop.org trash spec
        $xdgDataHome = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $env:HOME '.local/share' }
        return Join-Path $xdgDataHome 'Trash'
    }
}

function Move-ToTrash {
    <#
    .SYNOPSIS
        Moves a file or directory to the trash/recycle bin.
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [switch]$Force
    )

    process {
        if (-not (Test-Path $Path)) {
            Write-Warning "Path not found: $Path"
            return $false
        }

        if (Test-IsWindows) {
            # Use Shell.Application COM object for proper Recycle Bin
            try {
                $shell = New-Object -ComObject Shell.Application
                $item = Get-Item -LiteralPath $Path
                $folder = $shell.Namespace(0).ParseName($item.FullName)

                if ($null -eq $folder) {
                    # Fallback: use namespace parent folder
                    $parentPath = Split-Path $item.FullName -Parent
                    $fileName = Split-Path $item.FullName -Leaf
                    $folder = $shell.Namespace($parentPath)
                    $folderItem = $folder.ParseName($fileName)
                    $folderItem.InvokeVerb('delete')
                }
                else {
                    $folder.InvokeVerb('delete')
                }

                # Release COM object
                [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
                return $true
            }
            catch {
                Write-Warning "Failed to move to Recycle Bin: $_"
                return $false
            }
        }
        elseif (Test-IsMacOS) {
            # Use AppleScript or trash command
            if (Get-Command 'trash' -ErrorAction SilentlyContinue) {
                & trash $Path
                return $LASTEXITCODE -eq 0
            }
            else {
                # Fallback to .Trash folder
                $trashPath = Get-TrashPath
                $fileName = Split-Path $Path -Leaf
                $destPath = Join-Path $trashPath $fileName

                # Handle name conflicts
                $counter = 1
                while (Test-Path $destPath) {
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                    $ext = [System.IO.Path]::GetExtension($fileName)
                    $destPath = Join-Path $trashPath "$baseName ($counter)$ext"
                    $counter++
                }

                Move-Item -LiteralPath $Path -Destination $destPath -Force:$Force
                return $true
            }
        }
        else {
            # Linux - use trash-cli or freedesktop spec
            if (Get-Command 'trash-put' -ErrorAction SilentlyContinue) {
                & trash-put $Path
                return $LASTEXITCODE -eq 0
            }
            elseif (Get-Command 'gio' -ErrorAction SilentlyContinue) {
                & gio trash $Path
                return $LASTEXITCODE -eq 0
            }
            else {
                # Manual trash implementation
                $trashPath = Get-TrashPath
                $filesDir = Join-Path $trashPath 'files'
                $infoDir = Join-Path $trashPath 'info'

                New-Item -ItemType Directory -Path $filesDir -Force | Out-Null
                New-Item -ItemType Directory -Path $infoDir -Force | Out-Null

                $fileName = Split-Path $Path -Leaf
                $destPath = Join-Path $filesDir $fileName

                # Handle conflicts
                $counter = 1
                while (Test-Path $destPath) {
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
                    $ext = [System.IO.Path]::GetExtension($fileName)
                    $destPath = Join-Path $filesDir "$baseName.$counter$ext"
                    $counter++
                }

                # Create .trashinfo file
                $infoFile = Join-Path $infoDir "$([System.IO.Path]::GetFileName($destPath)).trashinfo"
                $trashInfo = @"
[Trash Info]
Path=$((Get-Item $Path).FullName)
DeletionDate=$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
"@
                Set-Content -Path $infoFile -Value $trashInfo

                Move-Item -LiteralPath $Path -Destination $destPath -Force:$Force
                return $true
            }
        }
    }
}

#endregion

#region Hash Utilities

function Get-FileHashFast {
    <#
    .SYNOPSIS
        Gets file hash using the fastest available algorithm.
    #>
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [ValidateSet('MD5', 'SHA256', 'SHA1', 'XXHash')]
        [string]$Algorithm = 'MD5'
    )

    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $null
        }

        try {
            # Use built-in Get-FileHash for standard algorithms
            if ($Algorithm -ne 'XXHash') {
                $hash = Get-FileHash -LiteralPath $Path -Algorithm $Algorithm
                return $hash.Hash.ToLower()
            }
            else {
                # Check for xxhash command
                if (Get-Command 'xxhsum' -ErrorAction SilentlyContinue) {
                    $result = & xxhsum $Path 2>$null
                    return ($result -split '\s+')[0]
                }
                # Fallback to MD5
                return Get-FileHashFast -Path $Path -Algorithm MD5
            }
        }
        catch {
            Write-Warning "Failed to hash file $Path : $_"
            return $null
        }
    }
}

function Get-PartialFileHash {
    <#
    .SYNOPSIS
        Gets hash of first N bytes of a file (for quick duplicate detection).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$Bytes = 4096
    )

    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $buffer = New-Object byte[] $Bytes
        $bytesRead = $stream.Read($buffer, 0, $Bytes)
        $stream.Close()

        if ($bytesRead -gt 0) {
            $md5 = [System.Security.Cryptography.MD5]::Create()
            $hashBytes = $md5.ComputeHash($buffer, 0, $bytesRead)
            return [BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
        }
    }
    catch {
        Write-Warning "Failed to get partial hash for $Path : $_"
    }

    return $null
}

#endregion

#region External Tool Detection

function Test-CzkawkaInstalled {
    <#
    .SYNOPSIS
        Checks if czkawka_cli is installed and available.
    #>
    return $null -ne (Get-Command 'czkawka_cli' -ErrorAction SilentlyContinue)
}

function Get-CzkawkaPath {
    <#
    .SYNOPSIS
        Gets the path to czkawka_cli executable.
    #>
    $cmd = Get-Command 'czkawka_cli' -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    # Check common installation paths
    $possiblePaths = @()

    if (Test-IsWindows) {
        $possiblePaths += @(
            "$env:USERPROFILE\scoop\shims\czkawka_cli.exe",
            "$env:LOCALAPPDATA\Programs\czkawka\czkawka_cli.exe",
            "C:\Program Files\czkawka\czkawka_cli.exe",
            "$env:USERPROFILE\.cargo\bin\czkawka_cli.exe"
        )
    }
    else {
        $possiblePaths += @(
            '/usr/local/bin/czkawka_cli',
            '/usr/bin/czkawka_cli',
            "$env:HOME/.cargo/bin/czkawka_cli",
            '/opt/homebrew/bin/czkawka_cli'
        )
    }

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Install-Czkawka {
    <#
    .SYNOPSIS
        Provides installation instructions for czkawka.
    #>
    $platform = Get-Platform

    Write-Host "`nCzkawka is required for advanced duplicate detection." -ForegroundColor Yellow
    Write-Host "Installation instructions:" -ForegroundColor Cyan

    switch ($platform) {
        'Windows' {
            Write-Host @"

  Option 1 - Using Scoop (recommended):
    scoop bucket add extras
    scoop install czkawka

  Option 2 - Using Cargo:
    cargo install czkawka_cli

  Option 3 - Download binary:
    https://github.com/qarmin/czkawka/releases

"@
        }
        'macOS' {
            Write-Host @"

  Option 1 - Using Homebrew:
    brew install czkawka

  Option 2 - Using Cargo:
    cargo install czkawka_cli

"@
        }
        'Linux' {
            Write-Host @"

  Option 1 - Using package manager:
    # Arch Linux
    sudo pacman -S czkawka-cli

    # Fedora
    sudo dnf install czkawka-cli

  Option 2 - Using Cargo:
    cargo install czkawka_cli

  Option 3 - Using Flatpak (GUI only):
    flatpak install com.github.qarmin.czkawka

"@
        }
    }
}

#endregion

#region File Type Detection

function Get-FileCategory {
    <#
    .SYNOPSIS
        Categorizes a file based on its extension.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $ext = [System.IO.Path]::GetExtension($Path).TrimStart('.').ToLower()

    $categories = @{
        'documents' = @('pdf', 'doc', 'docx', 'txt', 'md', 'rtf', 'odt', 'pages', 'tex', 'epub', 'xls', 'xlsx', 'ppt', 'pptx')
        'images'    = @('jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'tiff', 'ico', 'heic', 'raw', 'cr2', 'nef', 'psd')
        'videos'    = @('mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg', '3gp')
        'audio'     = @('mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a', 'wma', 'aiff', 'opus', 'alac')
        'code'      = @('js', 'ts', 'jsx', 'tsx', 'py', 'go', 'rs', 'java', 'c', 'cpp', 'h', 'hpp', 'rb', 'php', 'swift', 'kt', 'scala', 'sh', 'bash', 'zsh', 'ps1', 'psm1', 'cs', 'fs', 'vb')
        'data'      = @('json', 'yaml', 'yml', 'xml', 'csv', 'sql', 'toml', 'ini', 'env', 'log')
        'archives'  = @('zip', 'tar', 'gz', 'bz2', 'xz', '7z', 'rar', 'tgz', 'tbz2', 'cab')
        'executables' = @('exe', 'msi', 'dmg', 'pkg', 'deb', 'rpm', 'app', 'bin', 'bat', 'cmd', 'com')
    }

    foreach ($category in $categories.Keys) {
        if ($ext -in $categories[$category]) {
            return $category
        }
    }

    return 'other'
}

function Get-ProjectType {
    <#
    .SYNOPSIS
        Detects the type of project in a directory.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path -PathType Container)) {
        return 'unknown'
    }

    $markers = @{
        'nodejs'      = @('package.json')
        'rust'        = @('Cargo.toml')
        'go'          = @('go.mod')
        'python'      = @('requirements.txt', 'pyproject.toml', 'setup.py', 'Pipfile')
        'ruby'        = @('Gemfile')
        'java-maven'  = @('pom.xml')
        'java-gradle' = @('build.gradle', 'build.gradle.kts')
        'dotnet'      = @('*.csproj', '*.fsproj', '*.sln')
        'php'         = @('composer.json')
        'elixir'      = @('mix.exs')
    }

    foreach ($type in $markers.Keys) {
        foreach ($marker in $markers[$type]) {
            $markerPath = Join-Path $Path $marker
            if ($marker.Contains('*')) {
                if (Get-ChildItem -Path $Path -Filter $marker -ErrorAction SilentlyContinue) {
                    return $type
                }
            }
            elseif (Test-Path $markerPath) {
                return $type
            }
        }
    }

    if (Test-Path (Join-Path $Path '.git')) {
        return 'git-repo'
    }

    return 'unknown'
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Get-Platform',
    'Test-IsWindows',
    'Test-IsMacOS',
    'Test-IsLinux',
    'Test-IsUnix',
    'Get-NormalizedPath',
    'Get-SafePath',
    'Test-IsSafePath',
    'Format-FileSize',
    'ConvertTo-Bytes',
    'Get-TrashPath',
    'Move-ToTrash',
    'Get-FileHashFast',
    'Get-PartialFileHash',
    'Test-CzkawkaInstalled',
    'Get-CzkawkaPath',
    'Install-Czkawka',
    'Get-FileCategory',
    'Get-ProjectType'
)
