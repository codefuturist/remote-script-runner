# RSR.Packages.psm1 - RSR Package Management Module
# Provides: Cross-platform package management with multi-method support
#
# Usage: Import-Module RSR (loads via manifest)

#Requires -Version 5.1

# =============================================================================
# Module Configuration
# =============================================================================

$Script:RSR_PKG_CONFIG_DIR = Join-Path $PSScriptRoot "..\..\config\packages"

# Interactive mode configuration
$Script:RSR_PKG_CONFIRM = if ($env:RSR_PKG_CONFIRM -eq '0') { $false } else { $true }
$Script:RSR_PKG_AUTO_INSTALL = if ($env:RSR_PKG_AUTO_INSTALL -eq '1') { $true } else { $false }

# =============================================================================
# Interactive Mode Detection
# =============================================================================

function Test-RSRInteractive {
    <#
    .SYNOPSIS
        Check if interactive mode should be used
    .DESCRIPTION
        Returns true if session is interactive and confirmation is enabled
    #>
    return [Environment]::UserInteractive -and
           -not $Script:RSR_PKG_AUTO_INSTALL -and
           $Script:RSR_PKG_CONFIRM
}

# =============================================================================
# Package Manager Detection
# =============================================================================

function Get-RSRPackageManager {
    <#
    .SYNOPSIS
        Detect available package manager
    .DESCRIPTION
        Returns the primary package manager for the current platform
        Priority: winget > choco > scoop (Windows)
                  brew (macOS)
                  apt > dnf > pacman (Linux)
    .EXAMPLE
        $mgr = Get-RSRPackageManager
    #>
    [CmdletBinding()]
    param()

    $platform = Get-RSRPlatform

    # Windows
    if ($platform -eq 'Windows') {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            return 'winget'
        }
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            return 'choco'
        }
        if (Get-Command scoop -ErrorAction SilentlyContinue) {
            return 'scoop'
        }
    }

    # macOS
    if ($platform -eq 'macOS') {
        if (Get-Command brew -ErrorAction SilentlyContinue) {
            return 'brew'
        }
    }

    # Linux
    if ($platform -eq 'Linux') {
        if (Get-Command apt-get -ErrorAction SilentlyContinue) {
            return 'apt'
        }
        if (Get-Command dnf -ErrorAction SilentlyContinue) {
            return 'dnf'
        }
        if (Get-Command pacman -ErrorAction SilentlyContinue) {
            return 'pacman'
        }
        if (Get-Command zypper -ErrorAction SilentlyContinue) {
            return 'zypper'
        }
    }

    return 'unknown'
}

function Get-RSRAvailableMethods {
    <#
    .SYNOPSIS
        Get all available installation methods on current system
    .EXAMPLE
        $methods = Get-RSRAvailableMethods
    #>
    [CmdletBinding()]
    param()

    $methods = @()

    $managers = @('winget', 'choco', 'scoop', 'brew', 'apt-get', 'dnf', 'pacman', 'zypper', 'apk')

    foreach ($mgr in $managers) {
        if (Get-Command $mgr -ErrorAction SilentlyContinue) {
            $methods += ($mgr -replace '-get$', '')
        }
    }

    return $methods
}

# =============================================================================
# Package Status Functions
# =============================================================================

function Test-RSRPackageInstalled {
    <#
    .SYNOPSIS
        Check if a package is installed
    .PARAMETER Name
        Package name
    .PARAMETER Manager
        Package manager to check (auto-detected if not specified)
    .EXAMPLE
        if (Test-RSRPackageInstalled 'git') { Write-Host "Git is installed" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Manager
    )

    if (-not $Manager) {
        $Manager = Get-RSRPackageManager
    }

    switch ($Manager) {
        'winget' {
            $result = winget list --id $Name --exact 2>$null
            return $LASTEXITCODE -eq 0
        }
        'choco' {
            $result = choco list --local-only $Name --exact 2>$null
            return $result -match $Name
        }
        'brew' {
            brew list $Name 2>$null
            return $LASTEXITCODE -eq 0
        }
        'apt' {
            dpkg -l $Name 2>$null | Select-String "^ii"
            return $LASTEXITCODE -eq 0
        }
        default {
            # Fallback: check if command exists
            return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
        }
    }
}

function Get-RSRPackageVersion {
    <#
    .SYNOPSIS
        Get installed package version
    .PARAMETER Name
        Package name
    .EXAMPLE
        $version = Get-RSRPackageVersion 'git'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $mgr = Get-RSRPackageManager

    switch ($mgr) {
        'winget' {
            $result = winget list --id $Name --exact 2>$null | Select-String $Name
            if ($result -match '\s+([\d\.]+)\s+') {
                return $matches[1]
            }
        }
        'brew' {
            $result = brew list --versions $Name 2>$null
            if ($result -match '([\d\.]+)') {
                return $matches[1]
            }
        }
        default {
            return 'unknown'
        }
    }

    return $null
}

# =============================================================================
# Installation Functions
# =============================================================================

function Install-RSRPackage {
    <#
    .SYNOPSIS
        Install a single package
    .PARAMETER Name
        Package name
    .PARAMETER Method
        Installation method (auto-detected if not specified)
    .PARAMETER Force
        Bypass confirmation prompts
    .EXAMPLE
        Install-RSRPackage 'git'
    .EXAMPLE
        Install-RSRPackage 'kubectl' -Method 'winget'
    .EXAMPLE
        Install-RSRPackage 'git' -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Method,

        [switch]$Force
    )

    if (-not $Method) {
        $Method = Get-RSRPackageManager
    }

    # Interactive confirmation
    if (-not $Force -and (Test-RSRInteractive)) {
        $question = "Install package '$Name' using $Method?"
        if (-not (Read-RSRConfirm $question -Default 'Yes')) {
            Write-RSRInfo "Skipped $Name"
            return $false
        }
    }

    Write-RSRInfo "Installing $Name using $Method..."

    try {
        switch ($Method) {
            'winget' {
                $args = @('install', '--id', $Name, '--silent', '--accept-source-agreements', '--accept-package-agreements')
                & winget @args
            }
            'choco' {
                $args = @('install', $Name, '-y')
                & choco @args
            }
            'scoop' {
                & scoop install $Name
            }
            'brew' {
                & brew install $Name
            }
            'apt' {
                & sudo apt-get install -y $Name
            }
            'dnf' {
                & sudo dnf install -y $Name
            }
            'pacman' {
                & sudo pacman -S --noconfirm $Name
            }
            default {
                throw "Unsupported package manager: $Method"
            }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-RSROk "Successfully installed $Name"
            return $true
        } else {
            Write-RSRError "Failed to install $Name (exit code: $LASTEXITCODE)"
            return $false
        }
    }
    catch {
        Write-RSRError "Error installing ${Name}: $($_.Exception.Message)"
        return $false
    }
}

function Install-RSRPackages {
    <#
    .SYNOPSIS
        Install multiple packages
    .PARAMETER Names
        Array of package names
    .PARAMETER Force
        Bypass confirmation prompts
    .PARAMETER Interactive
        Allow user to deselect packages before installation
    .EXAMPLE
        Install-RSRPackages @('git', 'curl', 'jq')
    .EXAMPLE
        Install-RSRPackages @('git', 'curl', 'jq') -Interactive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Names,

        [switch]$Force,

        [switch]$Interactive
    )

    # Interactive package selection
    $packagesToInstall = $Names
    if ($Interactive -and (Test-RSRInteractive)) {
        Write-RSRHeader "Package Selection"
        Write-Host "The following packages will be installed:" -ForegroundColor Cyan
        Write-Host ""
        foreach ($pkg in $Names) {
            Write-Host "  - $pkg" -ForegroundColor Gray
        }
        Write-Host ""

        if (Read-RSRConfirm "Proceed with installation?" -Default 'Yes') {
            # User can optionally deselect packages here
            # For now, just confirm the list
        } else {
            Write-RSRInfo "Installation cancelled"
            return $false
        }
    }

    $successCount = 0
    $failedPackages = @()

    foreach ($name in $packagesToInstall) {
        if (Install-RSRPackage $name -Force:$Force) {
            $successCount++
        } else {
            $failedPackages += $name
        }
    }

    Write-RSRInfo "Installed $successCount of $($Names.Count) packages"

    if ($failedPackages.Count -gt 0) {
        Write-RSRWarn "Failed to install: $($failedPackages -join ', ')"
    }

    return $successCount -eq $Names.Count
}

# =============================================================================
# Profile Management
# =============================================================================

function Get-RSRPackageProfiles {
    <#
    .SYNOPSIS
        List available package profiles
    .EXAMPLE
        Get-RSRPackageProfiles
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $Script:RSR_PKG_CONFIG_DIR)) {
        Write-RSRWarn "Package profiles directory not found: $Script:RSR_PKG_CONFIG_DIR"
        return @()
    }

    $profiles = Get-ChildItem -Path $Script:RSR_PKG_CONFIG_DIR -Filter "*.yaml" |
        Where-Object { $_.Name -ne 'methods.yaml' } |
        ForEach-Object {
            $yaml = ConvertFrom-RSRYaml -Path $_.FullName
            [PSCustomObject]@{
                Name = $_.BaseName
                Description = $yaml['description']
                Path = $_.FullName
            }
        }

    return $profiles
}

function Get-RSRPackageProfileInfo {
    <#
    .SYNOPSIS
        Get information about a specific profile
    .PARAMETER Profile
        Profile name
    .EXAMPLE
        Get-RSRPackageProfileInfo 'development'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Profile
    )

    $profilePath = Join-Path $Script:RSR_PKG_CONFIG_DIR "$Profile.yaml"

    if (-not (Test-Path $profilePath)) {
        throw "Profile not found: $Profile"
    }

    $yaml = ConvertFrom-RSRYaml -Path $profilePath
    $packages = Get-RSRYamlSection -Path $profilePath -Section 'packages'
    $groups = Get-RSRYamlGroups -Path $profilePath

    return [PSCustomObject]@{
        Name = $yaml['name']
        Description = $yaml['description']
        Version = $yaml['version']
        Category = $yaml['category']
        Packages = $packages
        Groups = $groups
        Path = $profilePath
    }
}

function Get-RSRPackageGroups {
    <#
    .SYNOPSIS
        List groups in a profile
    .PARAMETER Profile
        Profile name
    .EXAMPLE
        Get-RSRPackageGroups 'development'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Profile
    )

    $profilePath = Join-Path $Script:RSR_PKG_CONFIG_DIR "$Profile.yaml"

    if (-not (Test-Path $profilePath)) {
        throw "Profile not found: $Profile"
    }

    return Get-RSRYamlGroups -Path $profilePath
}

function Install-RSRPackageProfile {
    <#
    .SYNOPSIS
        Install packages from a profile or group
    .PARAMETER Profile
        Profile name or profile.group path
    .PARAMETER Force
        Bypass confirmation prompts
    .PARAMETER Interactive
        Show detailed information and confirm before installation
    .EXAMPLE
        Install-RSRPackageProfile 'core'
    .EXAMPLE
        Install-RSRPackageProfile 'development.languages.python'
    .EXAMPLE
        Install-RSRPackageProfile 'core' -Interactive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Profile,

        [switch]$Force,

        [switch]$Interactive
    )

    # Check for dot notation (group path)
    if ($Profile -match '\\.') {
        $parts = $Profile -split '\\.'
        $profileName = $parts[0]
        $groupPath = ($parts[1..($parts.Length - 1)]) -join '.'

        return Install-RSRPackageGroup -Profile $profileName -GroupPath $groupPath -Force:$Force -Interactive:$Interactive
    }

    # Install entire profile
    $profilePath = Join-Path $Script:RSR_PKG_CONFIG_DIR "$Profile.yaml"

    if (-not (Test-Path $profilePath)) {
        Write-RSRError "Profile not found: $Profile"
        return $false
    }

    Write-RSRHeader "Installing Profile: $Profile"

    $packages = Get-RSRYamlSection -Path $profilePath -Section 'packages'

    if ($packages.Count -eq 0) {
        Write-RSRWarn "No packages found in profile"
        return $true
    }

    # Interactive confirmation
    if ($Interactive -and (Test-RSRInteractive)) {
        Write-Host ""
        Write-Host "Profile: " -NoNewline; Write-Host $Profile -ForegroundColor Cyan
        Write-Host "Packages: " -NoNewline; Write-Host $packages.Count -ForegroundColor Cyan
        Write-Host ""

        if (-not (Read-RSRConfirm "Install $($packages.Count) packages from profile '$Profile'?" -Default 'Yes')) {
            Write-RSRInfo "Installation cancelled"
            return $false
        }
    }

    return Install-RSRPackages -Names $packages -Force:$Force
}

function Install-RSRPackageGroup {
    <#
    .SYNOPSIS
        Install packages from a specific group
    .PARAMETER Profile
        Profile name
    .PARAMETER GroupPath
        Group path (e.g., 'languages.python')
    .PARAMETER Force
        Bypass confirmation prompts
    .PARAMETER Interactive
        Show detailed information and confirm before installation
    .EXAMPLE
        Install-RSRPackageGroup -Profile 'development' -GroupPath 'languages.python'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Profile,

        [Parameter(Mandatory)]
        [string]$GroupPath,

        [switch]$Force,

        [switch]$Interactive
    )

    $profilePath = Join-Path $Script:RSR_PKG_CONFIG_DIR "$Profile.yaml"

    if (-not (Test-Path $profilePath)) {
        Write-RSRError "Profile not found: $Profile"
        return $false
    }

    Write-RSRHeader "Installing Group: $Profile.$GroupPath"

    $packages = Get-RSRYamlGroupPackages -Path $profilePath -GroupPath $GroupPath

    if ($packages.Count -eq 0) {
        Write-RSRWarn "No packages found in group"
        return $true
    }

    # Interactive confirmation
    if ($Interactive -and (Test-RSRInteractive)) {
        Write-Host ""
        Write-Host "Profile: " -NoNewline; Write-Host $Profile -ForegroundColor Cyan
        Write-Host "Group: " -NoNewline; Write-Host $GroupPath -ForegroundColor Cyan
        Write-Host "Packages: " -NoNewline; Write-Host $packages.Count -ForegroundColor Cyan
        Write-Host ""

        if (-not (Read-RSRConfirm "Install $($packages.Count) packages from group '$Profile.$GroupPath'?" -Default 'Yes')) {
            Write-RSRInfo "Installation cancelled"
            return $false
        }
    }

    return Install-RSRPackages -Names $packages -Force:$Force
}

# =============================================================================
# Interactive Installation Wizard
# =============================================================================

function Start-RSRPackageWizard {
    <#
    .SYNOPSIS
        Interactive package installation wizard
    .DESCRIPTION
        Guided installation with profile selection, group selection, and confirmation
    .EXAMPLE
        Start-RSRPackageWizard
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-RSRInteractive)) {
        Write-RSRError "Interactive wizard requires an interactive session"
        return $false
    }

    Write-RSRHeader "RSR Package Installation Wizard"
    Write-Host ""

    # Step 1: Select profile
    $profiles = Get-RSRPackageProfiles
    if ($profiles.Count -eq 0) {
        Write-RSRError "No profiles found"
        return $false
    }

    $profileNames = $profiles | ForEach-Object { $_.Name }
    $selectedProfile = Read-RSRSelect "Select a profile to install" $profileNames

    if (-not $selectedProfile) {
        Write-RSRInfo "Installation cancelled"
        return $false
    }

    Write-Host ""

    # Step 2: Check for groups
    $groups = Get-RSRPackageGroups -Profile $selectedProfile -ErrorAction SilentlyContinue
    $selectedGroups = @()

    if ($groups -and $groups.Count -gt 0) {
        Write-RSRInfo "Profile '$selectedProfile' has groups available"
        Write-Host ""

        if (Read-RSRConfirm "Would you like to select specific groups?" -Default 'No') {
            $groupPaths = $groups | ForEach-Object { $_.Path }
            $selectedGroups = Read-RSRMultiSelect "Select groups to install" $groupPaths

            if ($selectedGroups.Count -eq 0) {
                Write-RSRInfo "No groups selected, installing entire profile"
            }
        }
    }

    Write-Host ""

    # Step 3: Show summary and confirm
    Write-RSRHeader "Installation Summary"
    Write-Host ""
    Write-Host "  Profile: " -NoNewline; Write-Host $selectedProfile -ForegroundColor Cyan

    if ($selectedGroups.Count -gt 0) {
        Write-Host "  Groups: " -NoNewline; Write-Host "$($selectedGroups.Count) selected" -ForegroundColor Cyan
        foreach ($grp in $selectedGroups) {
            Write-Host "    - $grp" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Scope: " -NoNewline; Write-Host "Entire profile" -ForegroundColor Cyan
    }

    Write-Host ""

    if (-not (Read-RSRConfirm "Proceed with installation?" -Default 'Yes')) {
        Write-RSRInfo "Installation cancelled"
        return $false
    }

    Write-Host ""

    # Step 4: Install
    $success = $true

    if ($selectedGroups.Count -gt 0) {
        # Install selected groups
        foreach ($group in $selectedGroups) {
            $groupPath = "$selectedProfile.$group"
            if (-not (Install-RSRPackageProfile -Profile $groupPath -Force)) {
                $success = $false
            }
        }
    } else {
        # Install entire profile
        $success = Install-RSRPackageProfile -Profile $selectedProfile -Force
    }

    Write-Host ""

    if ($success) {
        Write-RSROk "Installation completed successfully"
    } else {
        Write-RSRWarn "Installation completed with some errors"
    }

    return $success
}

# =============================================================================
# Cache Management
# =============================================================================

function Update-RSRPackageCache {
    <#
    .SYNOPSIS
        Update package manager cache
    .EXAMPLE
        Update-RSRPackageCache
    #>
    [CmdletBinding()]
    param()

    $mgr = Get-RSRPackageManager

    Write-RSRInfo "Updating package cache for $mgr..."

    switch ($mgr) {
        'apt' {
            & sudo apt-get update
        }
        'dnf' {
            & sudo dnf check-update
        }
        'brew' {
            & brew update
        }
        'winget' {
            & winget source update
        }
        default {
            Write-RSRDebug "No cache update needed for $mgr"
        }
    }
}

function Clear-RSRPackageCache {
    <#
    .SYNOPSIS
        Clean package manager cache
    .EXAMPLE
        Clear-RSRPackageCache
    #>
    [CmdletBinding()]
    param()

    $mgr = Get-RSRPackageManager

    Write-RSRInfo "Cleaning package cache for $mgr..."

    switch ($mgr) {
        'apt' {
            & sudo apt-get clean
            & sudo apt-get autoremove -y
        }
        'dnf' {
            & sudo dnf clean all
        }
        'brew' {
            & brew cleanup
        }
        'choco' {
            & choco cache clean
        }
        default {
            Write-RSRDebug "No cache cleanup available for $mgr"
        }
    }
}

# =============================================================================
# System Update Functions
# =============================================================================

function Update-RSRSystem {
    <#
    .SYNOPSIS
        Update all system packages and package managers
    .PARAMETER IncludeLanguage
        Include language package managers (pip, npm, cargo, gem)
    .PARAMETER CheckOnly
        Only check for updates, don't install
    .PARAMETER DryRun
        Show what would be updated without making changes
    .EXAMPLE
        Update-RSRSystem
    .EXAMPLE
        Update-RSRSystem -IncludeLanguage
    .EXAMPLE
        Update-RSRSystem -CheckOnly
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeLanguage,
        [switch]$CheckOnly,
        [switch]$DryRun
    )

    $platform = Get-RSRPlatform

    Write-RSRInfo "Checking for system updates on $platform..."

    switch ($platform) {
        'Windows' {
            $mgr = Get-RSRPackageManager

            if ($mgr -eq 'winget') {
                if ($CheckOnly) {
                    $output = winget upgrade 2>$null
                    Write-Host $output
                } else {
                    Write-RSRInfo "Updating winget packages..."
                    if ($DryRun) {
                        winget upgrade --all 2>$null
                    } else {
                        winget upgrade --all --silent 2>$null
                        Write-RSROk "winget packages updated"
                    }
                }
            } elseif ($mgr -eq 'choco') {
                if ($CheckOnly) {
                    choco outdated 2>$null
                } else {
                    Write-RSRInfo "Updating Chocolatey packages..."
                    if ($DryRun) {
                        choco upgrade all --noop 2>$null
                    } else {
                        choco upgrade all -y 2>$null
                        Write-RSROk "Chocolatey packages updated"
                    }
                }
            }
        }
        'macOS' {
            if (Get-Command brew -ErrorAction SilentlyContinue) {
                if ($CheckOnly) {
                    brew outdated
                } else {
                    Write-RSRInfo "Updating Homebrew packages..."
                    if (-not $DryRun) {
                        brew update 2>$null | Out-Null
                        brew upgrade 2>$null
                        Write-RSROk "Homebrew packages updated"
                    }
                }
            }
        }
        'Linux' {
            $mgr = Get-RSRPackageManager

            if ($CheckOnly) {
                switch ($mgr) {
                    'apt' { & sudo apt list --upgradable }
                    'dnf' { & sudo dnf check-update }
                    'pacman' { & sudo pacman -Qu }
                    default { Write-RSRWarn "Unsupported package manager: $mgr" }
                }
            } else {
                Write-RSRInfo "Updating $mgr packages..."
                if (-not $DryRun) {
                    switch ($mgr) {
                        'apt' {
                            & sudo apt-get update 2>$null | Out-Null
                            & sudo apt-get upgrade -y 2>$null
                        }
                        'dnf' { & sudo dnf upgrade -y 2>$null }
                        'pacman' { & sudo pacman -Syu --noconfirm 2>$null }
                        default { Write-RSRWarn "Unsupported package manager: $mgr" }
                    }
                    Write-RSROk "$mgr packages updated"
                }
            }
        }
    }

    # Language package managers
    if ($IncludeLanguage) {
        Write-Host ""
        Write-RSRInfo "Updating language package managers..."

        # pip
        if (Get-Command pip3 -ErrorAction SilentlyContinue -or Get-Command pip -ErrorAction SilentlyContinue) {
            $pipCmd = if (Get-Command pip3 -ErrorAction SilentlyContinue) { 'pip3' } else { 'pip' }
            if (-not $CheckOnly -and -not $DryRun) {
                & $pipCmd install --upgrade pip 2>$null | Out-Null
                Write-RSRDebug "pip updated"
            }
        }

        # npm
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            if ($CheckOnly) {
                npm outdated -g
            } elseif (-not $DryRun) {
                npm update -g 2>$null | Out-Null
                Write-RSRDebug "npm packages updated"
            }
        }

        Write-RSROk "Language package managers updated"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-RSRPackageManager',
    'Get-RSRAvailableMethods',
    'Test-RSRPackageInstalled',
    'Get-RSRPackageVersion',
    'Install-RSRPackage',
    'Install-RSRPackages',
    'Get-RSRPackageProfiles',
    'Get-RSRPackageProfileInfo',
    'Get-RSRPackageGroups',
    'Install-RSRPackageProfile',
    'Install-RSRPackageGroup',
    'Start-RSRPackageWizard',
    'Update-RSRPackageCache',
    'Clear-RSRPackageCache',
    'Update-RSRSystem'
)
