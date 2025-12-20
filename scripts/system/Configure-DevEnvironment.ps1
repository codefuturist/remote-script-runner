#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Configure Windows environment for optimal WSL/development experience
.DESCRIPTION
    Detects and helps configure:
    - Proxy settings for corporate environments
    - Windows Defender exclusions for performance
    - Network configuration for WSL
    - Developer mode settings
.PARAMETER DetectProxy
    Detect and display current proxy settings
.PARAMETER ConfigureDefender
    Add WSL/development folder exclusions to Windows Defender
.PARAMETER EnableDevMode
    Enable Windows Developer Mode
.PARAMETER CheckAll
    Run all diagnostics
.EXAMPLE
    .\Configure-DevEnvironment.ps1 -CheckAll
.EXAMPLE
    .\Configure-DevEnvironment.ps1 -ConfigureDefender
#>

[CmdletBinding(DefaultParameterSetName = 'Check')]
param(
    [switch]$DetectProxy,
    [switch]$ConfigureDefender,
    [switch]$EnableDevMode,
    [switch]$CheckAll
)

$ErrorActionPreference = 'Stop'

# =============================================================================
# UI Helpers
# =============================================================================

$Script:Colors = @{
    Title     = 'Cyan'
    Success   = 'Green'
    Warning   = 'Yellow'
    Error     = 'Red'
    Info      = 'White'
    Muted     = 'DarkGray'
    Highlight = 'Magenta'
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "┌─ $Text " -ForegroundColor $Script:Colors.Highlight -NoNewline
    Write-Host ("─" * [math]::Max(0, 50 - $Text.Length)) -ForegroundColor $Script:Colors.Muted
}

function Write-Step {
    param(
        [string]$Text,
        [ValidateSet('pending', 'running', 'success', 'warning', 'error', 'skip')]
        [string]$Status = 'pending'
    )
    $icons = @{
        pending = '○'
        running = '◐'
        success = '✓'
        warning = '⚠'
        error   = '✗'
        skip    = '○'
    }
    $colors = @{
        pending = $Script:Colors.Muted
        running = $Script:Colors.Info
        success = $Script:Colors.Success
        warning = $Script:Colors.Warning
        error   = $Script:Colors.Error
        skip    = $Script:Colors.Muted
    }
    Write-Host "  $($icons[$Status]) " -ForegroundColor $colors[$Status] -NoNewline
    Write-Host $Text -ForegroundColor $(if ($Status -eq 'skip') { $Script:Colors.Muted } else { $Script:Colors.Info })
}

function Write-Info {
    param([string]$Text)
    Write-Host "  ℹ $Text" -ForegroundColor $Script:Colors.Muted
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# =============================================================================
# Proxy Detection
# =============================================================================

function Get-ProxySettings {
    Write-Section "Proxy Configuration"

    # System proxy (WinHTTP)
    try {
        $winhttp = netsh winhttp show proxy 2>&1
        if ($winhttp -match 'Direct access') {
            Write-Step "WinHTTP: Direct connection (no proxy)" -Status success
        }
        elseif ($winhttp -match 'Proxy Server') {
            $proxyMatch = $winhttp | Select-String -Pattern 'Proxy Server\s*:\s*(.+)'
            if ($proxyMatch) {
                Write-Step "WinHTTP Proxy: $($proxyMatch.Matches.Groups[1].Value)" -Status warning
            }
        }
    }
    catch {
        Write-Step "Could not detect WinHTTP proxy" -Status skip
    }

    # Internet Explorer/Edge proxy settings
    try {
        $ieSettings = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
        if ($ieSettings.ProxyEnable -eq 1) {
            Write-Step "IE Proxy: $($ieSettings.ProxyServer)" -Status warning
            if ($ieSettings.ProxyOverride) {
                Write-Info "Bypass: $($ieSettings.ProxyOverride)"
            }
        }
        else {
            Write-Step "IE Proxy: Disabled" -Status success
        }
    }
    catch {
        Write-Step "Could not detect IE proxy settings" -Status skip
    }

    # Environment variables
    $envProxy = $env:HTTP_PROXY, $env:HTTPS_PROXY, $env:http_proxy, $env:https_proxy | Where-Object { $_ }
    if ($envProxy) {
        Write-Step "Environment proxy detected" -Status warning
        foreach ($p in $envProxy) {
            Write-Info "  $p"
        }
    }
    else {
        Write-Step "No environment proxy variables set" -Status success
    }

    # WSL proxy guidance
    Write-Host ""
    Write-Info "To configure proxy in WSL, add to ~/.bashrc or /etc/environment:"
    Write-Info '  export HTTP_PROXY="http://proxy.example.com:8080"'
    Write-Info '  export HTTPS_PROXY="http://proxy.example.com:8080"'
    Write-Info '  export NO_PROXY="localhost,127.0.0.1,.local"'
}

# =============================================================================
# Windows Defender Configuration
# =============================================================================

function Add-DefenderExclusions {
    Write-Section "Windows Defender Exclusions"

    if (-not (Test-IsAdmin)) {
        Write-Step "Administrator privileges required" -Status error
        Write-Info "Please run PowerShell as Administrator"
        return
    }

    # Common development paths to exclude
    $exclusions = @(
        # WSL
        "$env:LOCALAPPDATA\Packages\*CanonicalGroupLimited*"
        "$env:LOCALAPPDATA\lxss"
        "\\wsl$"
        "\\wsl.localhost"

        # Development folders
        "$env:USERPROFILE\source"
        "$env:USERPROFILE\projects"
        "$env:USERPROFILE\Developer"
        "$env:USERPROFILE\dev"
        "$env:USERPROFILE\repos"
        "$env:USERPROFILE\git"
        "$env:USERPROFILE\.vscode"

        # Package managers
        "$env:USERPROFILE\scoop"
        "$env:LOCALAPPDATA\npm"
        "$env:APPDATA\npm"
        "$env:USERPROFILE\.nuget"
        "$env:USERPROFILE\.cargo"
        "$env:USERPROFILE\.rustup"
        "$env:USERPROFILE\go"

        # Build tools
        "$env:LOCALAPPDATA\Temp\*"
    )

    # Process exclusions
    $processExclusions = @(
        "wsl.exe"
        "wslhost.exe"
        "node.exe"
        "python.exe"
        "python3.exe"
        "git.exe"
        "code.exe"
        "devenv.exe"
        "msbuild.exe"
        "dotnet.exe"
        "pwsh.exe"
        "powershell.exe"
    )

    Write-Step "Adding folder exclusions..." -Status running

    $addedCount = 0
    foreach ($path in $exclusions) {
        # Check if path-like pattern exists
        $testPath = $path -replace '\*', ''
        if (Test-Path $testPath -ErrorAction SilentlyContinue) {
            try {
                Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
                $addedCount++
            }
            catch {
                # Already exists or other issue
            }
        }
    }

    Write-Step "Added $addedCount folder exclusions" -Status success

    Write-Step "Adding process exclusions..." -Status running

    $processCount = 0
    foreach ($proc in $processExclusions) {
        try {
            Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
            $processCount++
        }
        catch {
            # Already exists
        }
    }

    Write-Step "Added $processCount process exclusions" -Status success

    Write-Host ""
    Write-Info "Exclusions help improve build and development performance"
    Write-Info "Review exclusions: Get-MpPreference | Select-Object -ExpandProperty ExclusionPath"
}

function Show-DefenderExclusions {
    Write-Section "Current Windows Defender Exclusions"

    try {
        $prefs = Get-MpPreference

        Write-Step "Path Exclusions:" -Status pending
        if ($prefs.ExclusionPath) {
            foreach ($path in $prefs.ExclusionPath) {
                Write-Info "  $path"
            }
        }
        else {
            Write-Info "  (none)"
        }

        Write-Host ""
        Write-Step "Process Exclusions:" -Status pending
        if ($prefs.ExclusionProcess) {
            foreach ($proc in $prefs.ExclusionProcess) {
                Write-Info "  $proc"
            }
        }
        else {
            Write-Info "  (none)"
        }
    }
    catch {
        Write-Step "Could not retrieve Defender settings" -Status warning
        Write-Info "Run as Administrator to view exclusions"
    }
}

# =============================================================================
# Developer Mode
# =============================================================================

function Test-DeveloperMode {
    try {
        $devMode = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue
        return $devMode.AllowDevelopmentWithoutDevLicense -eq 1
    }
    catch {
        return $false
    }
}

function Enable-DeveloperMode {
    Write-Section "Windows Developer Mode"

    if (Test-DeveloperMode) {
        Write-Step "Developer Mode already enabled" -Status success
        return
    }

    if (-not (Test-IsAdmin)) {
        Write-Step "Administrator privileges required" -Status error
        Write-Info "Please run PowerShell as Administrator"
        Write-Host ""
        Write-Info "Alternatively, enable via Settings > Update & Security > For Developers"
        return
    }

    Write-Step "Enabling Developer Mode..." -Status running

    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }

        Set-ItemProperty -Path $regPath -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 -Type DWord
        Set-ItemProperty -Path $regPath -Name 'AllowAllTrustedApps' -Value 1 -Type DWord

        Write-Step "Developer Mode enabled" -Status success
        Write-Info "Benefits: Symlink creation, sideload apps, SSH server"
    }
    catch {
        Write-Step ("Failed to enable Developer Mode: " + $_.Exception.Message) -Status error
    }
}

# =============================================================================
# WSL Network Check
# =============================================================================

function Test-WSLNetworking {
    Write-Section "WSL Network Configuration"

    # Check if WSL is installed
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Step "WSL not installed" -Status skip
        return
    }

    # Check WSL network mode
    $wslConfig = Join-Path $env:USERPROFILE ".wslconfig"
    if (Test-Path $wslConfig) {
        $config = Get-Content $wslConfig -Raw
        if ($config -match 'networkingMode\s*=\s*mirrored') {
            Write-Step "WSL networking: Mirrored mode" -Status success
            Write-Info "WSL shares Windows network stack"
        }
        elseif ($config -match 'networkingMode\s*=\s*nat') {
            Write-Step "WSL networking: NAT mode" -Status success
        }
        else {
            Write-Step "WSL networking: Default (NAT)" -Status success
        }
    }
    else {
        Write-Step "No .wslconfig found (using defaults)" -Status pending
    }

    # Test connectivity from WSL
    try {
        $distros = wsl.exe --list --quiet 2>&1 | Where-Object { $_ -and $_.Trim() }
        if ($distros) {
            $defaultDistro = $distros[0] -replace '\x00', ''
            Write-Step "Testing connectivity from $defaultDistro..." -Status running

            $pingResult = wsl.exe -d $defaultDistro -- ping -c 1 -W 3 8.8.8.8 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Step "Internet connectivity: OK" -Status success
            }
            else {
                Write-Step "Internet connectivity: Failed" -Status warning
                Write-Info "Check firewall and proxy settings"
            }

            # DNS test
            $dnsResult = wsl.exe -d $defaultDistro -- host google.com 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Step "DNS resolution: OK" -Status success
            }
            else {
                Write-Step "DNS resolution: Issues detected" -Status warning
                Write-Info "Consider adding 'dnsTunneling=true' to .wslconfig"
            }
        }
    }
    catch {
        Write-Step "Could not test WSL networking" -Status skip
    }

    # Firewall check
    Write-Host ""
    Write-Info "If WSL has network issues, check Windows Firewall rules:"
    Write-Info "  Get-NetFirewallRule | Where-Object { `$_.DisplayName -like '*WSL*' }"
}

# =============================================================================
# Main
# =============================================================================

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        Windows Development Environment Diagnostics         ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($CheckAll -or (-not $DetectProxy -and -not $ConfigureDefender -and -not $EnableDevMode)) {
    Get-ProxySettings
    Show-DefenderExclusions
    Test-WSLNetworking

    Write-Host ""
    Write-Section "Developer Mode Status"
    if (Test-DeveloperMode) {
        Write-Step "Developer Mode: Enabled" -Status success
    }
    else {
        Write-Step "Developer Mode: Disabled" -Status warning
        Write-Info "Enable with: .\Configure-DevEnvironment.ps1 -EnableDevMode"
    }

    Write-Host ""
    Write-Section "Recommendations"
    if (-not (Test-IsAdmin)) {
        Write-Info "Run as Administrator to configure Defender exclusions"
    }
}
else {
    if ($DetectProxy) {
        Get-ProxySettings
    }

    if ($ConfigureDefender) {
        Add-DefenderExclusions
    }

    if ($EnableDevMode) {
        Enable-DeveloperMode
    }
}

Write-Host ""

