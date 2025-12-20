#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Export WSL distributions for backup or migration
.DESCRIPTION
    Exports WSL distros to .tar files for backup, migration, or cloning.
    Supports compression and automatic naming with timestamps.
.PARAMETER Distro
    Name of the distribution to export
.PARAMETER OutputPath
    Output file path (default: current directory with timestamp)
.PARAMETER Compress
    Compress the export using gzip
.PARAMETER All
    Export all installed distributions
.PARAMETER ListOnly
    Only list available distributions without exporting
.EXAMPLE
    .\Export-WSLDistro.ps1 -Distro Ubuntu
.EXAMPLE
    .\Export-WSLDistro.ps1 -All -Compress
.EXAMPLE
    .\Export-WSLDistro.ps1 -ListOnly
#>

[CmdletBinding(DefaultParameterSetName = 'Single')]
param(
    [Parameter(ParameterSetName = 'Single', Mandatory)]
    [string]$Distro,

    [Parameter(ParameterSetName = 'Single')]
    [Parameter(ParameterSetName = 'All')]
    [string]$OutputPath,

    [Parameter(ParameterSetName = 'Single')]
    [Parameter(ParameterSetName = 'All')]
    [switch]$Compress,

    [Parameter(ParameterSetName = 'All')]
    [switch]$All,

    [Parameter(ParameterSetName = 'List')]
    [switch]$ListOnly
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

function Get-InstalledDistros {
    <#
    .SYNOPSIS
        Get list of installed WSL distributions with details
    #>
    try {
        $output = wsl.exe --list --verbose 2>&1 | Out-String
        $lines = $output -split "`r?`n" | Where-Object { $_ -match '\S' }

        $distros = @()
        $headerSkipped = $false

        foreach ($line in $lines) {
            # Skip header line
            if (-not $headerSkipped -and $line -match '^\s*NAME\s+STATE\s+VERSION') {
                $headerSkipped = $true
                continue
            }

            # Parse distro line: "* Ubuntu    Running    2" or "  Debian    Stopped    1"
            if ($line -match '^\s*(\*)?\s*(\S+)\s+(Running|Stopped)\s+(\d)') {
                $distros += [PSCustomObject]@{
                    Name      = $Matches[2]
                    IsDefault = [bool]$Matches[1]
                    State     = $Matches[3]
                    Version   = [int]$Matches[4]
                }
            }
        }

        return $distros
    }
    catch {
        return @()
    }
}

function Export-SingleDistro {
    <#
    .SYNOPSIS
        Export a single WSL distribution
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DistroName,

        [string]$OutputDir,

        [switch]$UseCompression
    )

    # Generate output filename
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $extension = if ($UseCompression) { '.tar.gz' } else { '.tar' }
    $fileName = "${DistroName}_${timestamp}${extension}"

    if (-not $OutputDir) {
        $OutputDir = Get-Location
    }

    $outputFile = Join-Path $OutputDir $fileName

    # Check if distro exists
    $distros = Get-InstalledDistros
    $distroInfo = $distros | Where-Object { $_.Name -eq $DistroName }

    if (-not $distroInfo) {
        Write-Status "Distribution '$DistroName' not found" -Type error
        return $null
    }

    Write-Status "Exporting $DistroName (WSL $($distroInfo.Version))..." -Type pending

    # Stop distro if running for clean export
    if ($distroInfo.State -eq 'Running') {
        Write-Status "Stopping $DistroName for clean export..." -Type info
        wsl.exe --terminate $DistroName 2>&1 | Out-Null
        Start-Sleep -Seconds 2
    }

    try {
        if ($UseCompression) {
            # Export to temp file then compress
            $tempFile = Join-Path $env:TEMP "${DistroName}_temp.tar"

            Write-Status "Creating export..." -Type pending
            $result = wsl.exe --export $DistroName $tempFile 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "WSL export failed: $result"
            }

            Write-Status "Compressing..." -Type pending

            # Use .NET compression
            $inputStream = [System.IO.File]::OpenRead($tempFile)
            $outputStream = [System.IO.File]::Create($outputFile)
            $gzipStream = New-Object System.IO.Compression.GZipStream($outputStream, [System.IO.Compression.CompressionLevel]::Optimal)

            $inputStream.CopyTo($gzipStream)

            $gzipStream.Close()
            $outputStream.Close()
            $inputStream.Close()

            Remove-Item $tempFile -Force
        }
        else {
            $result = wsl.exe --export $DistroName $outputFile 2>&1

            if ($LASTEXITCODE -ne 0) {
                throw "WSL export failed: $result"
            }
        }

        $fileInfo = Get-Item $outputFile
        $sizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
        $sizeMB = [math]::Round($fileInfo.Length / 1MB, 0)
        $sizeDisplay = if ($sizeGB -ge 1) { "${sizeGB} GB" } else { "${sizeMB} MB" }

        Write-Status "Exported: $outputFile ($sizeDisplay)" -Type success

        return [PSCustomObject]@{
            Distro     = $DistroName
            OutputFile = $outputFile
            Size       = $fileInfo.Length
            Compressed = $UseCompression
        }
    }
    catch {
        Write-Status "Export failed: $_" -Type error
        return $null
    }
}

# =============================================================================
# Main
# =============================================================================

Write-Banner "WSL Distribution Export"

# Check WSL availability
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Status "WSL is not installed" -Type error
    exit 1
}

$distros = Get-InstalledDistros

if ($distros.Count -eq 0) {
    Write-Status "No WSL distributions found" -Type warning
    exit 0
}

# List mode
if ($ListOnly) {
    Write-Host ""
    Write-Host "  Installed Distributions:" -ForegroundColor $Script:Colors.Highlight
    Write-Host ""

    foreach ($d in $distros) {
        $marker = if ($d.IsDefault) { '*' } else { ' ' }
        $stateColor = if ($d.State -eq 'Running') { 'Green' } else { 'DarkGray' }
        Write-Host "  $marker $($d.Name)" -ForegroundColor White -NoNewline
        Write-Host " ($($d.State), WSL $($d.Version))" -ForegroundColor $stateColor
    }

    Write-Host ""
    Write-Host "  * = default distribution" -ForegroundColor $Script:Colors.Muted
    exit 0
}

# Export mode
$results = @()

if ($All) {
    Write-Host ""
    Write-Status "Exporting all $($distros.Count) distributions..." -Type info
    Write-Host ""

    foreach ($d in $distros) {
        $result = Export-SingleDistro -DistroName $d.Name -OutputDir $OutputPath -UseCompression:$Compress
        if ($result) { $results += $result }
    }
}
else {
    Write-Host ""
    $result = Export-SingleDistro -DistroName $Distro -OutputDir $OutputPath -UseCompression:$Compress
    if ($result) { $results += $result }
}

# Summary
if ($results.Count -gt 0) {
    Write-Host ""
    Write-Status "Exported $($results.Count) distribution(s)" -Type success

    $totalSize = ($results | Measure-Object -Property Size -Sum).Sum
    $totalGB = [math]::Round($totalSize / 1GB, 2)
    Write-Host "  Total size: $totalGB GB" -ForegroundColor $Script:Colors.Muted

    Write-Host ""
    Write-Host "  To restore, use: Import-WSLDistro.ps1" -ForegroundColor $Script:Colors.Muted
}

