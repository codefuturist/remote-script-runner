<#
.SYNOPSIS
    Windows System Update Script

.DESCRIPTION
    Comprehensive update system for Windows supporting multiple package managers
    and Windows Update.

.PARAMETER Check
    Check for available updates only

.PARAMETER List
    List all available updates

.PARAMETER All
    Update all sources (winget, choco, Windows Update)

.PARAMETER DryRun
    Show what would be updated without making changes

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER IncludeWindowsUpdate
    Include Windows Update (requires admin)

.PARAMETER NoWinget
    Skip winget updates

.PARAMETER NoChoco
    Skip Chocolatey updates

.PARAMETER IncludeLanguage
    Include language package managers (pip, npm, cargo, gem)

.PARAMETER LanguageManager
    Specify specific language manager to update

.EXAMPLE
    .\System-Update.ps1 -Check

.EXAMPLE
    .\System-Update.ps1 -All -Force

.EXAMPLE
    .\System-Update.ps1 -IncludeWindowsUpdate -Force

.NOTES
    Version: 1.0.0
    Author: codefuturist
    Platform: Windows (PowerShell 5.1+)
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$List,
    [switch]$All,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$IncludeWindowsUpdate,
    [switch]$NoWinget,
    [switch]$NoChoco,
    [switch]$IncludeLanguage,
    [string[]]$LanguageManager
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = "1.0.0"
$ScriptName = "Windows System Update"

# =============================================================================
# Helper Functions
# =============================================================================

function Write-Header {
    param([string]$Text)
    Write-Host "`n$Text" -ForegroundColor Cyan -NoNewline
    Write-Host " v$ScriptVersion" -ForegroundColor Gray
    Write-Host ("=" * 70) -ForegroundColor DarkGray
}

function Write-Info {
    param([string]$Message)
    Write-Host "▸ " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "⚠ " -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor Yellow
}

function Write-ErrorCustom {
    param([string]$Message)
    Write-Host "✗ " -ForegroundColor Red -NoNewline
    Write-Host $Message -ForegroundColor Red
}

function Write-Debug-Custom {
    param([string]$Message)
    if ($VerbosePreference -ne 'SilentlyContinue') {
        Write-Host "  $Message" -ForegroundColor DarkGray
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Confirm-Action {
    param(
        [string]$Message,
        [string]$Default = 'N'
    )

    if ($Force) {
        return $true
    }

    $prompt = if ($Default -eq 'Y') { '[Y/n]' } else { '[y/N]' }
    $response = Read-Host "$Message $prompt"

    if ([string]::IsNullOrWhiteSpace($response)) {
        $response = $Default
    }

    return $response -match '^[Yy]'
}

# =============================================================================
# Winget Functions
# =============================================================================

function Test-WingetAvailable {
    return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
}

function Get-WingetUpdates {
    if (-not (Test-WingetAvailable)) {
        Write-Debug-Custom "winget not available"
        return @()
    }

    Write-Info "Checking winget updates..."

    try {
        $output = winget upgrade 2>&1 | Out-String

        # Parse winget output to extract update info
        $lines = $output -split "`n" | Where-Object { $_ -match '^\S' -and $_ -notmatch '^(Name|-)' }

        $updates = @()
        foreach ($line in $lines) {
            if ($line -match '(\S+)\s+(\S+)\s+<\s+(\S+)') {
                $updates += [PSCustomObject]@{
                    Name = $matches[1].Trim()
                    Current = $matches[2].Trim()
                    Available = $matches[3].Trim()
                    Source = 'winget'
                }
            }
        }

        return $updates
    }
    catch {
        Write-Warning-Custom "Failed to check winget updates: $_"
        return @()
    }
}

function Update-Winget {
    if (-not (Test-WingetAvailable)) {
        Write-Debug-Custom "winget not available, skipping"
        return
    }

    $updates = Get-WingetUpdates

    if ($updates.Count -eq 0) {
        Write-Success "winget: All packages up to date"
        return
    }

    Write-Warning-Custom "winget: $($updates.Count) package(s) can be upgraded"

    if ($DryRun) {
        Write-Info "Would upgrade:"
        $updates | ForEach-Object {
            Write-Host "  $($_.Name) ($($_.Current) → $($_.Available))" -ForegroundColor Cyan
        }
        return
    }

    if (-not $Force) {
        if (-not (Confirm-Action "Upgrade all winget packages?" "Y")) {
            Write-Info "winget updates skipped"
            return
        }
    }

    Write-Info "Upgrading winget packages..."

    try {
        winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
        Write-Success "winget upgrades completed"
    }
    catch {
        Write-ErrorCustom "winget upgrade failed: $_"
    }
}

# =============================================================================
# Chocolatey Functions
# =============================================================================

function Test-ChocoAvailable {
    return $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
}

function Get-ChocoUpdates {
    if (-not (Test-ChocoAvailable)) {
        Write-Debug-Custom "Chocolatey not available"
        return @()
    }

    Write-Info "Checking Chocolatey updates..."

    try {
        $output = choco outdated --limit-output 2>&1 | Out-String

        $updates = @()
        $lines = $output -split "`n" | Where-Object { $_ -match '\S' }

        foreach ($line in $lines) {
            $parts = $line -split '\|'
            if ($parts.Count -ge 3) {
                $updates += [PSCustomObject]@{
                    Name = $parts[0].Trim()
                    Current = $parts[1].Trim()
                    Available = $parts[2].Trim()
                    Source = 'chocolatey'
                }
            }
        }

        return $updates
    }
    catch {
        Write-Warning-Custom "Failed to check Chocolatey updates: $_"
        return @()
    }
}

function Update-Chocolatey {
    if (-not (Test-ChocoAvailable)) {
        Write-Debug-Custom "Chocolatey not available, skipping"
        return
    }

    if (-not (Test-IsAdmin)) {
        Write-Warning-Custom "Chocolatey updates require administrator privileges"
        return
    }

    $updates = Get-ChocoUpdates

    if ($updates.Count -eq 0) {
        Write-Success "Chocolatey: All packages up to date"
        return
    }

    Write-Warning-Custom "Chocolatey: $($updates.Count) package(s) can be upgraded"

    if ($DryRun) {
        Write-Info "Would upgrade:"
        $updates | ForEach-Object {
            Write-Host "  $($_.Name) ($($_.Current) → $($_.Available))" -ForegroundColor Cyan
        }
        return
    }

    if (-not $Force) {
        if (-not (Confirm-Action "Upgrade all Chocolatey packages?" "Y")) {
            Write-Info "Chocolatey updates skipped"
            return
        }
    }

    Write-Info "Upgrading Chocolatey packages..."

    try {
        choco upgrade all -y
        Write-Success "Chocolatey upgrades completed"
    }
    catch {
        Write-ErrorCustom "Chocolatey upgrade failed: $_"
    }
}

# =============================================================================
# Windows Update Functions
# =============================================================================

function Test-WindowsUpdateAvailable {
    try {
        $module = Get-Module -ListAvailable -Name PSWindowsUpdate
        return $null -ne $module
    }
    catch {
        return $false
    }
}

function Get-WindowsUpdates {
    if (-not (Test-WindowsUpdateAvailable)) {
        Write-Warning-Custom "PSWindowsUpdate module not installed"
        Write-Info "Install with: Install-Module PSWindowsUpdate -Force"
        return @()
    }

    if (-not (Test-IsAdmin)) {
        Write-Warning-Custom "Checking Windows Update requires administrator privileges"
        return @()
    }

    Write-Info "Checking Windows Update (this may take a moment)..."

    try {
        Import-Module PSWindowsUpdate -ErrorAction Stop
        $updates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction Stop
        return $updates
    }
    catch {
        Write-Warning-Custom "Failed to check Windows Update: $_"
        return @()
    }
}

function Update-Windows {
    if (-not (Test-WindowsUpdateAvailable)) {
        Write-Warning-Custom "PSWindowsUpdate module not installed"
        Write-Info "Install with: Install-Module PSWindowsUpdate -Force"
        return
    }

    if (-not (Test-IsAdmin)) {
        Write-ErrorCustom "Windows Update requires administrator privileges"
        return
    }

    $updates = Get-WindowsUpdates

    if ($updates.Count -eq 0) {
        Write-Success "Windows Update: System is up to date"
        return
    }

    Write-Warning-Custom "Windows Update: $($updates.Count) update(s) available"

    if ($DryRun) {
        Write-Info "Available updates:"
        $updates | ForEach-Object {
            Write-Host "  $($_.Title)" -ForegroundColor Cyan
            Write-Host "    KB: $($_.KBArticleIDs -join ', ')" -ForegroundColor DarkGray
        }
        return
    }

    if (-not $Force) {
        Write-Warning-Custom "Windows Update installation may require a restart"
        if (-not (Confirm-Action "Install Windows updates?" "N")) {
            Write-Info "Windows Update skipped"
            return
        }
    }

    Write-Info "Installing Windows updates..."
    Write-Warning-Custom "This may take a while..."

    try {
        Import-Module PSWindowsUpdate
        Get-WindowsUpdate -MicrosoftUpdate -Install -AcceptAll -AutoReboot:$false
        Write-Success "Windows updates completed"

        # Check if reboot is required
        $rebootRequired = Get-WURebootStatus
        if ($rebootRequired) {
            Write-Warning-Custom "System restart is required to complete updates"

            if ($Force -or (Confirm-Action "Restart now?" "N")) {
                Write-Warning-Custom "Restarting system in 10 seconds..."
                Start-Sleep -Seconds 10
                Restart-Computer -Force
            }
        }
    }
    catch {
        Write-ErrorCustom "Windows Update failed: $_"
    }
}

# =============================================================================
# Language Package Manager Functions
# =============================================================================

function Update-PipPackages {
    if (-not (Get-Command pip -ErrorAction SilentlyContinue) -and
        -not (Get-Command pip3 -ErrorAction SilentlyContinue)) {
        Write-Debug-Custom "pip not installed, skipping"
        return
    }

    $pipCmd = if (Get-Command pip3 -ErrorAction SilentlyContinue) { 'pip3' } else { 'pip' }

    Write-Info "Checking pip packages..."

    try {
        $outdated = & $pipCmd list --outdated --format=freeze 2>&1 | Where-Object { $_ -match '==' }

        if ($outdated.Count -eq 0) {
            Write-Success "pip: All packages up to date"
            return
        }

        Write-Warning-Custom "pip: $($outdated.Count) package(s) can be upgraded"

        if ($DryRun) {
            & $pipCmd list --outdated
            return
        }

        # Update pip first
        & $pipCmd install --upgrade pip | Out-Null

        # Update packages
        $packages = $outdated | ForEach-Object { ($_ -split '==')[0] }
        $packages | ForEach-Object {
            Write-Debug-Custom "Updating pip package: $_"
            & $pipCmd install --upgrade $_ 2>&1 | Out-Null
        }

        Write-Success "pip updates completed"
    }
    catch {
        Write-Warning-Custom "pip update failed: $_"
    }
}

function Update-NpmPackages {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        Write-Debug-Custom "npm not installed, skipping"
        return
    }

    Write-Info "Checking global npm packages..."

    try {
        $outdated = npm outdated -g --depth=0 --json 2>&1 | ConvertFrom-Json

        if ($null -eq $outdated -or $outdated.PSObject.Properties.Count -eq 0) {
            Write-Success "npm: All packages up to date"
            return
        }

        Write-Warning-Custom "npm: $($outdated.PSObject.Properties.Count) package(s) can be upgraded"

        if ($DryRun) {
            npm outdated -g --depth=0
            return
        }

        npm update -g 2>&1 | Out-Null
        Write-Success "npm updates completed"
    }
    catch {
        Write-Warning-Custom "npm update failed: $_"
    }
}

function Update-CargoPackages {
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        Write-Debug-Custom "cargo not installed, skipping"
        return
    }

    # Check for cargo-update
    $cargoUpdate = cargo install --list 2>&1 | Select-String "cargo-update"

    if (-not $cargoUpdate) {
        Write-Warning-Custom "cargo-update not installed. Install with: cargo install cargo-update"
        return
    }

    Write-Info "Checking cargo packages..."

    if ($DryRun) {
        cargo install-update -l
        return
    }

    try {
        cargo install-update -a 2>&1 | Out-Null
        Write-Success "cargo updates completed"
    }
    catch {
        Write-Warning-Custom "cargo update failed: $_"
    }
}

function Update-GemPackages {
    if (-not (Get-Command gem -ErrorAction SilentlyContinue)) {
        Write-Debug-Custom "gem not installed, skipping"
        return
    }

    Write-Info "Checking Ruby gems..."

    try {
        $outdated = gem outdated 2>&1

        if ($outdated -match "No gems") {
            Write-Success "gem: All packages up to date"
            return
        }

        if ($DryRun) {
            gem outdated
            return
        }

        gem update 2>&1 | Out-Null
        Write-Success "gem updates completed"
    }
    catch {
        Write-Warning-Custom "gem update failed: $_"
    }
}

function Update-LanguageManagers {
    $managers = $LanguageManager

    if ($managers.Count -eq 0) {
        # Auto-detect
        if (Get-Command pip -ErrorAction SilentlyContinue) { $managers += 'pip' }
        if (Get-Command pip3 -ErrorAction SilentlyContinue) { $managers += 'pip' }
        if (Get-Command npm -ErrorAction SilentlyContinue) { $managers += 'npm' }
        if (Get-Command cargo -ErrorAction SilentlyContinue) { $managers += 'cargo' }
        if (Get-Command gem -ErrorAction SilentlyContinue) { $managers += 'gem' }
        $managers = $managers | Select-Object -Unique
    }

    if ($managers.Count -eq 0) {
        Write-Debug-Custom "No language package managers found"
        return
    }

    Write-Info "Updating language package managers: $($managers -join ', ')"
    Write-Host ""

    foreach ($mgr in $managers) {
        switch ($mgr.ToLower()) {
            'pip' { Update-PipPackages }
            'npm' { Update-NpmPackages }
            'cargo' { Update-CargoPackages }
            'gem' { Update-GemPackages }
            default { Write-Warning-Custom "Unknown language manager: $mgr" }
        }
    }
}

# =============================================================================
# Main Logic
# =============================================================================

function Show-Usage {
    Write-Host @"
$ScriptName v$ScriptVersion

Update Windows packages using winget, Chocolatey, and Windows Update.

Usage:
    .\System-Update.ps1 [OPTIONS]

Options:
    -Check                  Check for available updates only
    -List                   List all available updates
    -All                    Update all sources
    -DryRun                 Show what would be updated
    -Force                  Skip confirmation prompts
    -IncludeWindowsUpdate   Include Windows Update
    -NoWinget               Skip winget updates
    -NoChoco                Skip Chocolatey updates
    -IncludeLanguage        Include language package managers
    -LanguageManager <mgr>  Specific language manager (pip, npm, cargo, gem)

Examples:
    .\System-Update.ps1 -Check
    .\System-Update.ps1 -All -Force
    .\System-Update.ps1 -IncludeWindowsUpdate -Force
    .\System-Update.ps1 -IncludeLanguage -LanguageManager pip,npm

Requirements:
    - winget (Windows 10+)
    - Chocolatey (optional): https://chocolatey.org/install
    - PSWindowsUpdate module (optional): Install-Module PSWindowsUpdate
    - Admin rights for Chocolatey and Windows Update

"@
}

function Invoke-UpdateCheck {
    Write-Header "System Update Check"
    Write-Host ""

    $allUpdates = @()

    if (-not $NoWinget) {
        $wingetUpdates = Get-WingetUpdates
        $allUpdates += $wingetUpdates
        if ($wingetUpdates.Count -gt 0) {
            Write-Warning-Custom "winget: $($wingetUpdates.Count) update(s) available"
        } else {
            Write-Success "winget: Up to date"
        }
    }

    if (-not $NoChoco) {
        $chocoUpdates = Get-ChocoUpdates
        $allUpdates += $chocoUpdates
        if ($chocoUpdates.Count -gt 0) {
            Write-Warning-Custom "Chocolatey: $($chocoUpdates.Count) update(s) available"
        } else {
            Write-Success "Chocolatey: Up to date"
        }
    }

    if ($IncludeWindowsUpdate) {
        $windowsUpdates = Get-WindowsUpdates
        if ($windowsUpdates.Count -gt 0) {
            Write-Warning-Custom "Windows Update: $($windowsUpdates.Count) update(s) available"
        } else {
            Write-Success "Windows Update: Up to date"
        }
    }

    Write-Host ""
    Write-Info "Total updates available: $($allUpdates.Count)"
}

function Invoke-UpdateList {
    Write-Header "Available Updates"
    Write-Host ""

    if (-not $NoWinget) {
        $wingetUpdates = Get-WingetUpdates
        if ($wingetUpdates.Count -gt 0) {
            Write-Host "winget:" -ForegroundColor Yellow
            $wingetUpdates | ForEach-Object {
                Write-Host "  $($_.Name)" -ForegroundColor Cyan -NoNewline
                Write-Host " ($($_.Current) → $($_.Available))" -ForegroundColor Gray
            }
            Write-Host ""
        }
    }

    if (-not $NoChoco) {
        $chocoUpdates = Get-ChocoUpdates
        if ($chocoUpdates.Count -gt 0) {
            Write-Host "Chocolatey:" -ForegroundColor Yellow
            $chocoUpdates | ForEach-Object {
                Write-Host "  $($_.Name)" -ForegroundColor Cyan -NoNewline
                Write-Host " ($($_.Current) → $($_.Available))" -ForegroundColor Gray
            }
            Write-Host ""
        }
    }

    if ($IncludeWindowsUpdate) {
        $windowsUpdates = Get-WindowsUpdates
        if ($windowsUpdates.Count -gt 0) {
            Write-Host "Windows Update:" -ForegroundColor Yellow
            $windowsUpdates | ForEach-Object {
                Write-Host "  $($_.Title)" -ForegroundColor Cyan
            }
            Write-Host ""
        }
    }
}

function Invoke-UpdateAll {
    Write-Header "System Update"
    Write-Host ""

    if (-not $NoWinget) {
        Update-Winget
        Write-Host ""
    }

    if (-not $NoChoco) {
        Update-Chocolatey
        Write-Host ""
    }

    if ($IncludeWindowsUpdate) {
        Update-Windows
        Write-Host ""
    }

    if ($IncludeLanguage -or $LanguageManager.Count -gt 0) {
        Update-LanguageManagers
        Write-Host ""
    }

    Write-Success "Update process completed!"
}

# =============================================================================
# Entry Point
# =============================================================================

try {
    # Show header
    if (-not $Check -and -not $List) {
        Write-Header $ScriptName
        Write-Host ""
    }

    # Handle parameters
    if ($Check) {
        Invoke-UpdateCheck
    }
    elseif ($List) {
        Invoke-UpdateList
    }
    elseif ($All) {
        Invoke-UpdateAll
    }
    else {
        # Interactive mode
        if ($PSCmdlet.MyInvocation.BoundParameters.Count -eq 0) {
            Show-Usage
            Write-Host ""

            if (Confirm-Action "Run update check?" "Y") {
                Invoke-UpdateCheck
                Write-Host ""

                if (Confirm-Action "Proceed with updates?" "N") {
                    $All = $true
                    Invoke-UpdateAll
                }
            }
        }
        else {
            # Manual mode based on flags
            Invoke-UpdateAll
        }
    }
}
catch {
    Write-ErrorCustom "An error occurred: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    exit 1
}

