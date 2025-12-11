#!/usr/bin/env pwsh
#Requires -Version 5.1

<#
.SYNOPSIS
    Install packages from a profile or group
.DESCRIPTION
    RSR Package Manager - Install packages from predefined profiles or groups
    Supports: winget, choco, scoop (Windows), brew (macOS), apt/dnf/pacman (Linux)
.PARAMETER Profile
    Profile name or profile.group.subgroup path
.PARAMETER List
    List available profiles
.PARAMETER Groups
    List groups in a profile
.PARAMETER Info
    Show profile information
.PARAMETER Update
    Update package cache before installing
.PARAMETER Clean
    Clean package cache after installing
.PARAMETER Interactive
    Launch interactive wizard or show confirmation prompts
.PARAMETER Force
    Bypass all confirmation prompts
.EXAMPLE
    .\Install-PackageProfile.ps1 -List
.EXAMPLE
    .\Install-PackageProfile.ps1 -Profile core
.EXAMPLE
    .\Install-PackageProfile.ps1 -Profile development.languages.python
.EXAMPLE
    .\Install-PackageProfile.ps1 -Profile development -Groups
.EXAMPLE
    .\Install-PackageProfile.ps1 -Interactive
.EXAMPLE
    .\Install-PackageProfile.ps1 -Profile core -Force
#>

[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(Position = 0, ParameterSetName = 'Install')]
    [string]$Profile,
    
    [Parameter(ParameterSetName = 'List')]
    [switch]$List,
    
    [Parameter(ParameterSetName = 'Groups')]
    [string]$Groups,
    
    [Parameter(ParameterSetName = 'Info')]
    [string]$Info,
    
    [Parameter(ParameterSetName = 'Install')]
    [switch]$Update,
    
    [Parameter(ParameterSetName = 'Install')]
    [switch]$Clean,
    
    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,
    
    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Force
)

# Determine script root and load RSR module
$ScriptRoot = Split-Path -Parent $PSScriptRoot
$RSRModulePath = Join-Path $ScriptRoot "lib\powershell"

# Import RSR module
if (-not (Get-Module -Name RSR -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $RSRModulePath "RSR.psd1") -Force
}

#region Main Logic

try {
    switch ($PSCmdlet.ParameterSetName) {
        'Interactive' {
            # Set environment for interactive mode
            if ($Force) {
                $env:RSR_PKG_AUTO_INSTALL = '1'
                $env:RSR_PKG_CONFIRM = '0'
            }
            
            $success = Start-RSRPackageWizard
            exit ($success ? 0 : 1)
        }
        
        'List' {
            Write-RSRHeader "Available Package Profiles"
            $profiles = Get-RSRPackageProfiles
            
            if ($profiles.Count -eq 0) {
                Write-RSRWarn "No profiles found"
                exit 0
            }
            
            foreach ($p in $profiles) {
                Write-Host ""
                Write-Host "  $($p.Name)" -ForegroundColor Cyan
                if ($p.Description) {
                    Write-Host "    $($p.Description)" -ForegroundColor Gray
                }
            }
            Write-Host ""
        }
        
        'Groups' {
            Write-RSRHeader "Groups in Profile: $Groups"
            $groups = Get-RSRPackageGroups -Profile $Groups
            
            if ($groups.Count -eq 0) {
                Write-RSRWarn "No groups found in profile: $Groups"
                exit 0
            }
            
            foreach ($g in $groups) {
                Write-Host ""
                Write-Host "  $($g.Path)" -ForegroundColor Cyan
                if ($g.Description) {
                    Write-Host "    $($g.Description)" -ForegroundColor Gray
                }
                if ($g.Packages.Count -gt 0) {
                    Write-Host "    Packages: $($g.Packages.Count)" -ForegroundColor Gray
                }
            }
            Write-Host ""
        }
        
        'Info' {
            $profileInfo = Get-RSRPackageProfileInfo -Profile $Info
            
            Write-RSRHeader "Profile Information: $Info"
            Write-Host ""
            Write-Host "  Name:        " -NoNewline; Write-Host $profileInfo.Name -ForegroundColor Cyan
            Write-Host "  Description: " -NoNewline; Write-Host $profileInfo.Description -ForegroundColor Gray
            Write-Host "  Version:     " -NoNewline; Write-Host $profileInfo.Version -ForegroundColor Gray
            Write-Host "  Category:    " -NoNewline; Write-Host $profileInfo.Category -ForegroundColor Gray
            Write-Host ""
            
            if ($profileInfo.Packages.Count -gt 0) {
                Write-Host "  Packages ($($profileInfo.Packages.Count)):" -ForegroundColor Yellow
                foreach ($pkg in $profileInfo.Packages) {
                    Write-Host "    - $pkg" -ForegroundColor Gray
                }
                Write-Host ""
            }
            
            if ($profileInfo.Groups.Count -gt 0) {
                Write-Host "  Groups ($($profileInfo.Groups.Count)):" -ForegroundColor Yellow
                foreach ($grp in $profileInfo.Groups) {
                    Write-Host "    - $($grp.Path)" -ForegroundColor Gray
                    if ($grp.Description) {
                        Write-Host "      $($grp.Description)" -ForegroundColor DarkGray
                    }
                }
                Write-Host ""
            }
        }
        
        'Install' {
            if (-not $Profile) {
                Write-RSRError "Profile parameter is required"
                Write-Host "Usage: .\Install-PackageProfile.ps1 -Profile <profile>"
                Write-Host "       .\Install-PackageProfile.ps1 -List"
                Write-Host "       .\Install-PackageProfile.ps1 -Interactive"
                exit 1
            }
            
            # Set environment for force mode
            if ($Force) {
                $env:RSR_PKG_AUTO_INSTALL = '1'
                $env:RSR_PKG_CONFIRM = '0'
            }
            
            # Detect package manager
            $mgr = Get-RSRPackageManager
            Write-RSRInfo "Detected package manager: $mgr"
            
            if ($mgr -eq 'unknown') {
                Write-RSRError "No supported package manager found"
                Write-RSRInfo "Supported: winget, choco, scoop (Windows), brew (macOS), apt/dnf/pacman (Linux)"
                exit 1
            }
            
            # Update cache if requested
            if ($Update) {
                Update-RSRPackageCache
            }
            
            # Install profile or group with Force parameter
            $success = Install-RSRPackageProfile -Profile $Profile -Force:$Force -Interactive
            
            # Clean cache if requested
            if ($Clean) {
                Clear-RSRPackageCache
            }
            
            if ($success) {
                Write-RSROk "Profile installation completed successfully"
                exit 0
            } else {
                Write-RSRError "Profile installation completed with errors"
                exit 1
            }
        }
    }
}
catch {
    Write-RSRError "Error: $_"
    exit 1
}

#endregion
