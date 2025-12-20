#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Declutter tool for Windows.

.DESCRIPTION
    Sets up the Declutter tool:
    - Verifies PowerShell version
    - Checks for optional dependencies
    - Creates PowerShell profile alias (optional)
    - Adds to PATH (optional)

.PARAMETER AddToPath
    Add the bin\windows directory to the user PATH.

.PARAMETER CreateAlias
    Add a 'declutter' alias to the PowerShell profile.

.EXAMPLE
    .\install.ps1

.EXAMPLE
    .\install.ps1 -AddToPath -CreateAlias
#>

[CmdletBinding()]
param(
    [switch]$AddToPath,
    [switch]$CreateAlias,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# Colors
function Write-Step { param($msg) Write-Host "▶ $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "✓ $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "⚠ $msg" -ForegroundColor Yellow }
function Write-Info { param($msg) Write-Host "  $msg" -ForegroundColor Gray }

# Header
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║              Declutter Installer for Windows                 ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

$ScriptRoot = $PSScriptRoot
$BinDir = Join-Path $ScriptRoot 'bin\windows'
$DeclutterScript = Join-Path $BinDir 'declutter.ps1'

# Verify structure
Write-Step "Verifying installation..."

if (-not (Test-Path $DeclutterScript)) {
    throw "declutter.ps1 not found at: $DeclutterScript"
}

Write-Success "Installation files found"

# Check PowerShell version
Write-Step "Checking PowerShell version..."
$psVersion = $PSVersionTable.PSVersion
Write-Info "PowerShell $($psVersion.ToString())"

if ($psVersion.Major -lt 5) {
    throw "PowerShell 5.1 or later is required. Current: $psVersion"
}
Write-Success "PowerShell version OK"

# Check for optional dependencies
Write-Step "Checking optional dependencies..."

$dependencies = @(
    @{ Name = 'czkawka_cli'; Purpose = 'Advanced duplicate/image detection'; Required = $false }
    @{ Name = 'fd'; Purpose = 'Fast file finding'; Required = $false }
    @{ Name = 'fzf'; Purpose = 'Interactive selection'; Required = $false }
)

foreach ($dep in $dependencies) {
    $cmd = Get-Command $dep.Name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Success "$($dep.Name) - $($dep.Purpose)"
    }
    else {
        Write-Warn "$($dep.Name) not found - $($dep.Purpose)"
    }
}

# Add to PATH
if ($AddToPath) {
    Write-Step "Adding to PATH..."

    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')

    if ($userPath -notlike "*$BinDir*") {
        $newPath = "$userPath;$BinDir"
        [Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
        $env:PATH = "$env:PATH;$BinDir"
        Write-Success "Added to user PATH: $BinDir"
        Write-Info "Restart your terminal for PATH changes to take effect"
    }
    else {
        Write-Info "Already in PATH"
    }
}

# Create alias
if ($CreateAlias) {
    Write-Step "Creating PowerShell alias..."

    # Ensure profile exists
    if (-not (Test-Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
        Write-Info "Created PowerShell profile: $PROFILE"
    }

    $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    $aliasLine = "Set-Alias -Name declutter -Value '$DeclutterScript'"

    if ($profileContent -notmatch 'declutter') {
        Add-Content -Path $PROFILE -Value "`n# Declutter tool`n$aliasLine"
        Write-Success "Added 'declutter' alias to profile"
        Write-Info "Restart your terminal or run: . `$PROFILE"
    }
    else {
        Write-Info "Alias already exists in profile"
    }
}

# Create data directories
Write-Step "Creating data directories..."

$dataDirs = @(
    (Join-Path $env:LOCALAPPDATA 'declutter'),
    (Join-Path $env:LOCALAPPDATA 'declutter\cache'),
    (Join-Path $env:LOCALAPPDATA 'declutter\journal'),
    (Join-Path $env:LOCALAPPDATA 'declutter\reports')
)

foreach ($dir in $dataDirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}
Write-Success "Data directories created"

# Summary
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Success "Installation complete!"
Write-Host ""

Write-Host "Usage:" -ForegroundColor Cyan
if ($AddToPath) {
    Write-Host "  declutter help" -ForegroundColor White
}
else {
    Write-Host "  & '$DeclutterScript' help" -ForegroundColor White
}

Write-Host ""
Write-Host "Quick start:" -ForegroundColor Cyan
Write-Host "  declutter quick ~\Downloads     # Quick cleanup" -ForegroundColor Gray
Write-Host "  declutter duplicates ~\Photos   # Find duplicates" -ForegroundColor Gray
Write-Host "  declutter dev -DryRun ~\Code    # Preview dev cleanup" -ForegroundColor Gray
Write-Host ""

# Install czkawka if not present
if (-not (Get-Command 'czkawka_cli' -ErrorAction SilentlyContinue)) {
    Write-Host "Recommended: Install czkawka for advanced features:" -ForegroundColor Yellow
    Write-Host "  scoop install czkawka" -ForegroundColor Gray
    Write-Host "  # or download from: https://github.com/qarmin/czkawka/releases" -ForegroundColor Gray
    Write-Host ""
}
