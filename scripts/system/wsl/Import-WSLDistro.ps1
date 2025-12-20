#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Import WSL distributions from backup files
.DESCRIPTION
    Imports WSL distros from .tar or .tar.gz files created by Export-WSLDistro.ps1
    or any standard WSL export. Supports custom installation locations.
.PARAMETER InputFile
    Path to the .tar or .tar.gz file to import
.PARAMETER Name
    Name for the imported distribution (default: derived from filename)
.PARAMETER InstallLocation
    Directory where the distro VHD will be stored (default: %LOCALAPPDATA%\WSL\<name>)
.PARAMETER SetDefault
    Set the imported distro as the default
.PARAMETER WSLVersion
    WSL version to use (1 or 2, default: 2)
.EXAMPLE
    .\Import-WSLDistro.ps1 -InputFile .\Ubuntu_20241220.tar
.EXAMPLE
    .\Import-WSLDistro.ps1 -InputFile .\backup.tar.gz -Name MyUbuntu -SetDefault
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string]$InputFile,

    [string]$Name,

    [string]$InstallLocation,

    [switch]$SetDefault,

    [ValidateSet(1, 2)]
    [int]$WSLVersion = 2
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# UI Helpers
# =============================================================================

$Script:Colors = @{
    Success   = 'Green'
    Warning   = 'Yellow'
    Error     = 'Red'
    Info      = 'White'
    Muted     = 'DarkGray'
    Highlight = 'Cyan'
}

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('success', 'warning', 'error', 'info', 'pending')]
        [string]$Type = 'info'
    )
    $icons = @{ success = '✓'; warning = '⚠'; error = '✗'; info = 'ℹ'; pending = '○' }
    $colors = @{ success = 'Green'; warning = 'Yellow'; error = 'Red'; info = 'Cyan'; pending = 'DarkGray' }
    Write-Host "  $($icons[$Type]) " -ForegroundColor $colors[$Type] -NoNewline
    Write-Host $Message
}

function Write-Banner {
    param([string]$Text)
    Write-Host ""
    Write-Host "  $Text" -ForegroundColor $Script:Colors.Highlight
    Write-Host "  $('─' * $Text.Length)" -ForegroundColor $Script:Colors.Muted
}

# =============================================================================
# Core Functions
# =============================================================================

function Test-DistroExists {
    param([string]$DistroName)

    $output = wsl.exe --list --quiet 2>&1
    $distros = $output | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() -replace '\x00', '' }
    return $DistroName -in $distros
}

function Expand-GzipFile {
    param(
        [string]$InputPath,
        [string]$OutputPath
    )

    $inputStream = [System.IO.File]::OpenRead($InputPath)
    $gzipStream = New-Object System.IO.Compression.GZipStream($inputStream, [System.IO.Compression.DecompressionMode]::Decompress)
    $outputStream = [System.IO.File]::Create($OutputPath)

    $gzipStream.CopyTo($outputStream)

    $outputStream.Close()
    $gzipStream.Close()
    $inputStream.Close()
}

# =============================================================================
# Main
# =============================================================================

Write-Banner "WSL Distribution Import"

# Check WSL availability
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Status "WSL is not installed" -Type error
    exit 1
}

# Resolve input file
$inputPath = Resolve-Path $InputFile
$fileInfo = Get-Item $inputPath
$isCompressed = $fileInfo.Extension -eq '.gz' -or $fileInfo.Name -match '\.tar\.gz$'

Write-Host ""
Write-Status "Input: $($fileInfo.Name)" -Type info

# Derive name if not provided
if (-not $Name) {
    # Extract name from filename (e.g., "Ubuntu_20241220.tar" -> "Ubuntu")
    $baseName = $fileInfo.BaseName
    if ($baseName -match '\.tar$') { $baseName = $baseName -replace '\.tar$', '' }
    if ($baseName -match '_\d{8}') { $baseName = $baseName -replace '_\d{8}.*$', '' }
    $Name = $baseName
}

Write-Status "Distribution name: $Name" -Type info

# Check if distro already exists
if (Test-DistroExists $Name) {
    Write-Status "Distribution '$Name' already exists" -Type error
    Write-Host ""
    Write-Host "  Options:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    • Use -Name to specify a different name" -ForegroundColor $Script:Colors.Muted
    Write-Host "    • Unregister existing: wsl --unregister $Name" -ForegroundColor $Script:Colors.Muted
    exit 1
}

# Set install location
if (-not $InstallLocation) {
    $InstallLocation = Join-Path $env:LOCALAPPDATA "WSL\$Name"
}

Write-Status "Install location: $InstallLocation" -Type info

# Create install directory
if (-not (Test-Path $InstallLocation)) {
    New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
}

# Handle compressed files
$importFile = $inputPath
$tempFile = $null

if ($isCompressed) {
    Write-Status "Decompressing archive..." -Type pending
    $tempFile = Join-Path $env:TEMP "wsl_import_temp.tar"

    try {
        Expand-GzipFile -InputPath $inputPath -OutputPath $tempFile
        $importFile = $tempFile
        Write-Status "Decompression complete" -Type success
    }
    catch {
        Write-Status "Decompression failed: $_" -Type error
        exit 1
    }
}

# Import the distribution
Write-Status "Importing distribution (this may take a while)..." -Type pending

try {
    $result = wsl.exe --import $Name $InstallLocation $importFile --version $WSLVersion 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Import failed: $result"
    }

    Write-Status "Distribution imported successfully" -Type success

    # Set as default if requested
    if ($SetDefault) {
        wsl.exe --set-default $Name 2>&1 | Out-Null
        Write-Status "Set as default distribution" -Type success
    }

    # Cleanup temp file
    if ($tempFile -and (Test-Path $tempFile)) {
        Remove-Item $tempFile -Force
    }

    # Show next steps
    Write-Host ""
    Write-Host "  Next steps:" -ForegroundColor $Script:Colors.Highlight
    Write-Host "    • Enter distro: wsl -d $Name" -ForegroundColor $Script:Colors.Muted
    Write-Host "    • Configure: .\Set-WSLDistroConfig.ps1 -Distro $Name" -ForegroundColor $Script:Colors.Muted

    # Note about imported distros defaulting to root
    Write-Host ""
    Write-Host "  ⚠ Note: Imported distros default to root user." -ForegroundColor $Script:Colors.Warning
    Write-Host "    To set a default user, run inside WSL:" -ForegroundColor $Script:Colors.Muted
    Write-Host "    echo '[user]' | sudo tee /etc/wsl.conf" -ForegroundColor $Script:Colors.Muted
    Write-Host "    echo 'default=yourusername' | sudo tee -a /etc/wsl.conf" -ForegroundColor $Script:Colors.Muted
}
catch {
    Write-Status "Import failed: $_" -Type error

    # Cleanup temp file
    if ($tempFile -and (Test-Path $tempFile)) {
        Remove-Item $tempFile -Force
    }

    exit 1
}

