# RSR.psm1 - RSR PowerShell Module Root
# This is the main entry point for the RSR PowerShell module
#
# Usage: Import-Module RSR
#
# The module manifest (RSR.psd1) handles loading nested modules

#Requires -Version 5.1

# =============================================================================
# Module Variables
# =============================================================================

$Script:RSR_VERSION = '2.0.0'
$Script:RSR_MODULE_ROOT = $PSScriptRoot

# Export version info
$RSR_VERSION = $Script:RSR_VERSION

# Exit codes (matching shell library)
$RSR_EXIT_SUCCESS = 0
$RSR_EXIT_ERROR = 1
$RSR_EXIT_USAGE = 2
$RSR_EXIT_DEPENDENCY = 3
$RSR_EXIT_PERMISSION = 4
$RSR_EXIT_NOT_FOUND = 5
$RSR_EXIT_ALREADY_EXISTS = 6
$RSR_EXIT_TIMEOUT = 7
$RSR_EXIT_CANCELLED = 8

# =============================================================================
# Module Information
# =============================================================================

function Get-RSRModuleInfo {
    <#
    .SYNOPSIS
        Get RSR module information
    .DESCRIPTION
        Returns information about the loaded RSR module and its components
    .EXAMPLE
        Get-RSRModuleInfo
    #>
    [CmdletBinding()]
    param()

    $modules = @(
        @{ Name = 'Core'; Loaded = $null -ne (Get-Command 'Write-RSRLog' -ErrorAction SilentlyContinue) }
        @{ Name = 'Validate'; Loaded = $null -ne (Get-Command 'Test-RSRUsername' -ErrorAction SilentlyContinue) }
        @{ Name = 'Interactive'; Loaded = $null -ne (Get-Command 'Read-RSRConfirm' -ErrorAction SilentlyContinue) }
        @{ Name = 'Users'; Loaded = $null -ne (Get-Command 'Get-RSRUsers' -ErrorAction SilentlyContinue) }
        @{ Name = 'Docker'; Loaded = $null -ne (Get-Command 'Get-RSRDockerContainers' -ErrorAction SilentlyContinue) }
        @{ Name = 'SSH'; Loaded = $null -ne (Get-Command 'Get-RSRSSHServerStatus' -ErrorAction SilentlyContinue) }
    )

    [PSCustomObject]@{
        Version = $Script:RSR_VERSION
        ModuleRoot = $Script:RSR_MODULE_ROOT
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Platform = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } elseif ($IsLinux) { 'Linux' } else { 'Windows' }
        Modules = $modules
    }
}

# =============================================================================
# Module Initialization
# =============================================================================

Write-Verbose "RSR PowerShell Module v$Script:RSR_VERSION loaded from $Script:RSR_MODULE_ROOT"

