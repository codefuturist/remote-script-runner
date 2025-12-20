#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Shared UI helper functions for RSR Windows scripts
.DESCRIPTION
    Provides consistent UI elements across all RSR Windows scripts:
    - Colored status messages
    - Banners and sections
    - Interactive menus
    - Confirmation prompts
.NOTES
    Import with: . "$PSScriptRoot\..\RSR-UIHelpers.ps1"
#>

# =============================================================================
# Color Configuration
# =============================================================================

$Script:RSRColors = @{
    Title     = 'Cyan'
    Success   = 'Green'
    Warning   = 'Yellow'
    Error     = 'Red'
    Info      = 'White'
    Muted     = 'DarkGray'
    Highlight = 'Magenta'
}

# =============================================================================
# Output Functions
# =============================================================================

function Write-RSRBanner {
    <#
    .SYNOPSIS
        Display a banner with title
    #>
    param([string]$Text)

    $width = 60
    $border = "═" * $width
    Write-Host ""
    Write-Host "╔$border╗" -ForegroundColor $Script:RSRColors.Title
    $padding = [math]::Max(0, ($width - $Text.Length) / 2)
    $paddedText = (" " * [math]::Floor($padding)) + $Text + (" " * [math]::Ceiling($padding))
    Write-Host "║$paddedText║" -ForegroundColor $Script:RSRColors.Title
    Write-Host "╚$border╝" -ForegroundColor $Script:RSRColors.Title
    Write-Host ""
}

function Write-RSRSection {
    <#
    .SYNOPSIS
        Display a section header
    #>
    param([string]$Text)

    Write-Host ""
    Write-Host "┌─ $Text " -ForegroundColor $Script:RSRColors.Highlight -NoNewline
    Write-Host ("─" * [math]::Max(0, 50 - $Text.Length)) -ForegroundColor $Script:RSRColors.Muted
}

function Write-RSRStatus {
    <#
    .SYNOPSIS
        Display a status message with icon
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('success', 'warning', 'error', 'info', 'pending', 'running', 'skip')]
        [string]$Type = 'info'
    )

    $icons = @{
        success = '✓'
        warning = '⚠'
        error   = '✗'
        info    = 'ℹ'
        pending = '○'
        running = '◐'
        skip    = '○'
    }

    $colors = @{
        success = $Script:RSRColors.Success
        warning = $Script:RSRColors.Warning
        error   = $Script:RSRColors.Error
        info    = $Script:RSRColors.Title
        pending = $Script:RSRColors.Muted
        running = $Script:RSRColors.Info
        skip    = $Script:RSRColors.Muted
    }

    Write-Host "  $($icons[$Type]) " -ForegroundColor $colors[$Type] -NoNewline
    Write-Host $Message -ForegroundColor $(if ($Type -eq 'skip') { $Script:RSRColors.Muted } else { $Script:RSRColors.Info })
}

function Write-RSRInfo {
    <#
    .SYNOPSIS
        Display an info message (muted)
    #>
    param([string]$Text)
    Write-Host "    $Text" -ForegroundColor $Script:RSRColors.Muted
}

function Write-RSRSuccess {
    <#
    .SYNOPSIS
        Display a success message
    #>
    param([string]$Text)
    Write-RSRStatus -Message $Text -Type success
}

function Write-RSRWarning {
    <#
    .SYNOPSIS
        Display a warning message
    #>
    param([string]$Text)
    Write-RSRStatus -Message $Text -Type warning
}

function Write-RSRError {
    <#
    .SYNOPSIS
        Display an error message
    #>
    param([string]$Text)
    Write-RSRStatus -Message $Text -Type error
}

# =============================================================================
# Interactive Functions
# =============================================================================

function Show-RSRMenu {
    <#
    .SYNOPSIS
        Display an interactive menu and return selection
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string[]]$Options,

        [int]$Default = 0
    )

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor $Script:RSRColors.Highlight
    Write-Host ""

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $marker = if ($i -eq $Default) { "›" } else { " " }
        $num = $i + 1
        $color = if ($i -eq $Default) { $Script:RSRColors.Info } else { $Script:RSRColors.Muted }
        Write-Host "  $marker [$num] $($Options[$i])" -ForegroundColor $color
    }

    Write-Host ""
    $choice = Read-Host "  Select option (1-$($Options.Count), default: $($Default + 1))"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        return $Default
    }

    $selected = [int]$choice - 1
    if ($selected -ge 0 -and $selected -lt $Options.Count) {
        return $selected
    }
    return $Default
}

function Confirm-RSRAction {
    <#
    .SYNOPSIS
        Ask for confirmation with Y/N prompt
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [bool]$Default = $true,

        [switch]$Force
    )

    if ($Force) { return $true }

    $defaultHint = if ($Default) { "Y/n" } else { "y/N" }
    $response = Read-Host "  $Message [$defaultHint]"

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default
    }
    return $response -match '^[Yy]'
}

# =============================================================================
# System Detection Helpers
# =============================================================================

function Test-RSRAdmin {
    <#
    .SYNOPSIS
        Check if running as Administrator
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RSRWindowsBuild {
    <#
    .SYNOPSIS
        Get Windows build number
    #>
    return [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
}

function Test-RSRWSLInstalled {
    <#
    .SYNOPSIS
        Check if WSL is installed
    #>
    try {
        $wslPath = Get-Command wsl.exe -ErrorAction SilentlyContinue
        return $null -ne $wslPath
    }
    catch {
        return $false
    }
}

function Get-RSRInstalledDistros {
    <#
    .SYNOPSIS
        Get list of installed WSL distributions
    #>
    try {
        $output = wsl.exe --list --quiet 2>&1
        return $output | Where-Object { $_ -and $_.Trim() } | ForEach-Object { $_.Trim() -replace '\x00', '' }
    }
    catch {
        return @()
    }
}

# =============================================================================
# Export Functions
# =============================================================================

Export-ModuleMember -Function @(
    'Write-RSRBanner'
    'Write-RSRSection'
    'Write-RSRStatus'
    'Write-RSRInfo'
    'Write-RSRSuccess'
    'Write-RSRWarning'
    'Write-RSRError'
    'Show-RSRMenu'
    'Confirm-RSRAction'
    'Test-RSRAdmin'
    'Get-RSRWindowsBuild'
    'Test-RSRWSLInstalled'
    'Get-RSRInstalledDistros'
)

