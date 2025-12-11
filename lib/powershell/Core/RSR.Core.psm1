# RSR.Core.psm1 - RSR Core PowerShell Module
# Provides: logging, platform detection, command utilities
#
# Usage: Import-Module RSR (loads via manifest)

#Requires -Version 5.1

# =============================================================================
# Module Variables
# =============================================================================

$Script:RSR_DEBUG = $env:RSR_DEBUG -eq '1'
$Script:RSR_VERBOSE = $env:RSR_VERBOSE -eq '1'
$Script:RSR_NO_COLOR = $env:RSR_NO_COLOR -eq '1'

# =============================================================================
# Logging Functions
# =============================================================================

function Write-RSRLog {
    <#
    .SYNOPSIS
        Write a log message with level and formatting
    .PARAMETER Message
        The message to log
    .PARAMETER Level
        Log level: Info, Success, Warning, Error, Debug
    .EXAMPLE
        Write-RSRLog "Operation completed" -Level Success
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    $colors = @{
        'Info'    = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Debug'   = 'DarkGray'
    }

    $symbols = @{
        'Info'    = '▸'
        'Success' = '✓'
        'Warning' = '⚠'
        'Error'   = '✗'
        'Debug'   = '[debug]'
    }

    # Skip debug if not enabled
    if ($Level -eq 'Debug' -and -not $Script:RSR_DEBUG) {
        return
    }

    if ($Script:RSR_NO_COLOR) {
        Write-Host "$($symbols[$Level]) $Message"
    } else {
        Write-Host "$($symbols[$Level]) " -ForegroundColor $colors[$Level] -NoNewline
        Write-Host $Message
    }
}

function Write-RSRInfo {
    <#
    .SYNOPSIS
        Write an info message
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-RSRLog $Message -Level Info
}

function Write-RSROk {
    <#
    .SYNOPSIS
        Write a success message
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-RSRLog $Message -Level Success
}

function Write-RSRWarn {
    <#
    .SYNOPSIS
        Write a warning message
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-RSRLog $Message -Level Warning
}

function Write-RSRError {
    <#
    .SYNOPSIS
        Write an error message
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-RSRLog $Message -Level Error
}

function Write-RSRDebug {
    <#
    .SYNOPSIS
        Write a debug message (only shown when RSR_DEBUG=1)
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Message)
    Write-RSRLog $Message -Level Debug
}

function Write-RSRHeader {
    <#
    .SYNOPSIS
        Write a section header
    .PARAMETER Title
        The header title
    .EXAMPLE
        Write-RSRHeader "Configuration"
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string]$Title)

    Write-Host ""
    if ($Script:RSR_NO_COLOR) {
        Write-Host "=== $Title ==="
    } else {
        Write-Host "═══ $Title ═══" -ForegroundColor Cyan
    }
    Write-Host ""
}

# =============================================================================
# Platform Detection
# =============================================================================

function Get-RSRPlatform {
    <#
    .SYNOPSIS
        Get the current platform (Windows, Linux, macOS)
    .EXAMPLE
        $platform = Get-RSRPlatform
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell Core/7+
        if ($IsWindows) { return 'Windows' }
        if ($IsLinux) { return 'Linux' }
        if ($IsMacOS) { return 'macOS' }
    }

    # Windows PowerShell 5.1
    return 'Windows'
}

function Get-RSRArchitecture {
    <#
    .SYNOPSIS
        Get the CPU architecture (amd64, arm64, etc.)
    .EXAMPLE
        $arch = Get-RSRArchitecture
    #>
    [CmdletBinding()]
    param()

    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture

    switch ($arch) {
        'X64' { return 'amd64' }
        'Arm64' { return 'arm64' }
        'X86' { return 'i386' }
        'Arm' { return 'arm' }
        default { return $arch.ToString().ToLower() }
    }
}

function Get-RSRDistro {
    <#
    .SYNOPSIS
        Get the Linux distribution name (Linux only)
    .EXAMPLE
        $distro = Get-RSRDistro
    #>
    [CmdletBinding()]
    param()

    if ((Get-RSRPlatform) -ne 'Linux') {
        return 'N/A'
    }

    if (Test-Path '/etc/os-release') {
        $osRelease = Get-Content '/etc/os-release' | ConvertFrom-StringData
        return $osRelease.ID
    }

    return 'unknown'
}

# =============================================================================
# Command Utilities
# =============================================================================

function Test-RSRCommand {
    <#
    .SYNOPSIS
        Test if a command exists
    .PARAMETER Name
        The command name to test
    .EXAMPLE
        if (Test-RSRCommand 'docker') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-RSRDownload {
    <#
    .SYNOPSIS
        Download a file from URL
    .PARAMETER Url
        The URL to download
    .PARAMETER OutFile
        Optional output file path. If not specified, returns content as string.
    .EXAMPLE
        $content = Invoke-RSRDownload 'https://example.com/file.txt'
        Invoke-RSRDownload 'https://example.com/file.zip' -OutFile './file.zip'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Url,

        [string]$OutFile
    )

    $params = @{
        Uri = $Url
        UseBasicParsing = $true
    }

    if ($OutFile) {
        $params.OutFile = $OutFile
        Invoke-WebRequest @params
    } else {
        (Invoke-WebRequest @params).Content
    }
}

# =============================================================================
# Permission Utilities
# =============================================================================

function Test-RSRRoot {
    <#
    .SYNOPSIS
        Test if running with elevated/root privileges
    .EXAMPLE
        if (Test-RSRRoot) { ... }
    #>
    [CmdletBinding()]
    param()

    switch (Get-RSRPlatform) {
        'Windows' {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        default {
            # Linux/macOS
            return (id -u) -eq 0
        }
    }
}

function Assert-RSRRoot {
    <#
    .SYNOPSIS
        Assert that the script is running with elevated privileges
    .PARAMETER Message
        Custom error message
    .EXAMPLE
        Assert-RSRRoot "This operation requires administrator privileges"
    #>
    [CmdletBinding()]
    param(
        [string]$Message = 'This operation requires administrator/root privileges'
    )

    if (-not (Test-RSRRoot)) {
        throw $Message
    }
}

# =============================================================================
# Export
# =============================================================================

Export-ModuleMember -Function @(
    'Write-RSRLog',
    'Write-RSRInfo',
    'Write-RSROk',
    'Write-RSRWarn',
    'Write-RSRError',
    'Write-RSRDebug',
    'Write-RSRHeader',
    'Get-RSRPlatform',
    'Get-RSRArchitecture',
    'Get-RSRDistro',
    'Test-RSRCommand',
    'Invoke-RSRDownload',
    'Test-RSRRoot',
    'Assert-RSRRoot'
)

