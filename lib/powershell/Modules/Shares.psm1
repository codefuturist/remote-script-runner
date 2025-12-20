#Requires -Version 5.1
<#
.SYNOPSIS
    RSR Network Share Management Module for Windows

.DESCRIPTION
    PowerShell module for managing network shares including SMB/CIFS mapped drives,
    UNC paths, and persistent drive mappings. Provides functions for mounting,
    unmounting, discovery, and credential management.

.NOTES
    Version: 1.0.0
    Author:  codefuturist
    License: MIT
#>

# =============================================================================
# Module Configuration
# =============================================================================

$Script:ShareConfigDir = Join-Path $env:APPDATA 'RSR\shares'
$Script:CredentialsDir = Join-Path $Script:ShareConfigDir 'creds'
$Script:SavedSharesFile = Join-Path $Script:ShareConfigDir 'shares.json'

# =============================================================================
# Initialization
# =============================================================================

function Initialize-RSRShareModule {
    <#
    .SYNOPSIS
        Initialize the share management module
    #>

    # Create config directories
    if (-not (Test-Path $Script:ShareConfigDir)) {
        New-Item -ItemType Directory -Path $Script:ShareConfigDir -Force | Out-Null
    }

    if (-not (Test-Path $Script:CredentialsDir)) {
        New-Item -ItemType Directory -Path $Script:CredentialsDir -Force | Out-Null
    }

    # Initialize saved shares file
    if (-not (Test-Path $Script:SavedSharesFile)) {
        @{ shares = @() } | ConvertTo-Json | Set-Content $Script:SavedSharesFile
    }
}

# =============================================================================
# Share Type Detection
# =============================================================================

function Get-RSRShareType {
    <#
    .SYNOPSIS
        Detect the type of network share from path

    .PARAMETER Path
        The share path to analyze

    .EXAMPLE
        Get-RSRShareType -Path "\\server\share"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path
    )

    switch -Regex ($Path) {
        '^\\\\' { return 'smb' }
        '^//' { return 'smb' }
        '^smb://' { return 'smb' }
        '^https?://' { return 'webdav' }
        '^dav(s)?://' { return 'webdav' }
        default {
            # Check for NFS-style path (server:/path)
            if ($Path -match '^[^:]+:/.+') {
                return 'nfs'
            }
            return $null
        }
    }
}

function Test-RSRSharePath {
    <#
    .SYNOPSIS
        Validate share path format
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Type
    )

    if (-not $Type) {
        $Type = Get-RSRShareType -Path $Path
    }

    if (-not $Type) {
        return $false
    }

    switch ($Type) {
        'smb' {
            return $Path -match '^(\\\\|//|smb://)[^\\/:]+[\\/:].+'
        }
        'webdav' {
            return $Path -match '^(https?|davs?)://.+'
        }
        'nfs' {
            return $Path -match '^[^:]+:/.+'
        }
        default {
            return $false
        }
    }
}

# =============================================================================
# Share Path Parsing
# =============================================================================

function ConvertTo-RSRUNCPath {
    <#
    .SYNOPSIS
        Convert various share path formats to UNC path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Already UNC
    if ($Path -match '^\\\\') {
        return $Path
    }

    # Forward slash style
    if ($Path -match '^//(.+)') {
        return '\\' + ($Matches[1] -replace '/', '\')
    }

    # SMB URL
    if ($Path -match '^smb://(.+)') {
        return '\\' + ($Matches[1] -replace '/', '\')
    }

    return $Path
}

function Split-RSRSharePath {
    <#
    .SYNOPSIS
        Parse UNC path into components

    .EXAMPLE
        Split-RSRSharePath "\\server\share\folder"
        # Returns: @{ Server = 'server'; Share = 'share'; SubPath = 'folder' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $uncPath = ConvertTo-RSRUNCPath -Path $Path

    if ($uncPath -match '^\\\\([^\\]+)\\([^\\]+)(.*)$') {
        return @{
            Server = $Matches[1]
            Share = $Matches[2]
            SubPath = $Matches[3].TrimStart('\')
            FullPath = "\\$($Matches[1])\$($Matches[2])"
        }
    }

    return $null
}

# =============================================================================
# Credential Management
# =============================================================================

function Get-RSRShareCredential {
    <#
    .SYNOPSIS
        Get credentials for a share from storage or environment

    .PARAMETER Name
        Share name to get credentials for

    .PARAMETER Prompt
        Prompt for credentials if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Prompt
    )

    $credFile = Join-Path $Script:CredentialsDir "$Name.xml"

    # Try stored credentials
    if (Test-Path $credFile) {
        try {
            $cred = Import-Clixml $credFile
            return $cred
        }
        catch {
            Write-Warning "Failed to load stored credentials for '$Name'"
        }
    }

    # Try environment variables
    $envUser = [Environment]::GetEnvironmentVariable("${Name}_USER", 'User')
    $envPass = [Environment]::GetEnvironmentVariable("${Name}_PASS", 'User')

    if (-not $envUser) {
        $envUser = $env:SMB_USER
        $envPass = $env:SMB_PASS
    }

    if ($envUser -and $envPass) {
        $secPass = ConvertTo-SecureString $envPass -AsPlainText -Force
        return New-Object System.Management.Automation.PSCredential($envUser, $secPass)
    }

    # Prompt if requested
    if ($Prompt) {
        return Get-Credential -Message "Enter credentials for share '$Name'"
    }

    return $null
}

function Set-RSRShareCredential {
    <#
    .SYNOPSIS
        Store credentials for a share

    .PARAMETER Name
        Share name

    .PARAMETER Credential
        PSCredential object to store
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [PSCredential]$Credential
    )

    Initialize-RSRShareModule

    $credFile = Join-Path $Script:CredentialsDir "$Name.xml"

    try {
        $Credential | Export-Clixml $credFile
        Write-RSRSuccess "Credentials stored for '$Name'"
    }
    catch {
        Write-RSRError "Failed to store credentials: $_"
        return $false
    }

    return $true
}

function Remove-RSRShareCredential {
    <#
    .SYNOPSIS
        Remove stored credentials for a share
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $credFile = Join-Path $Script:CredentialsDir "$Name.xml"

    if (Test-Path $credFile) {
        Remove-Item $credFile -Force
        Write-RSRSuccess "Credentials removed for '$Name'"
    }
    else {
        Write-RSRWarning "No credentials stored for '$Name'"
    }
}

function Get-RSRShareCredentialList {
    <#
    .SYNOPSIS
        List all stored credentials
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $Script:CredentialsDir)) {
        return @()
    }

    Get-ChildItem $Script:CredentialsDir -Filter '*.xml' | ForEach-Object {
        $name = $_.BaseName
        try {
            $cred = Import-Clixml $_.FullName
            [PSCustomObject]@{
                Name = $name
                Username = $cred.UserName
                Stored = $_.LastWriteTime
            }
        }
        catch {
            [PSCustomObject]@{
                Name = $name
                Username = '<error reading>'
                Stored = $_.LastWriteTime
            }
        }
    }
}

# =============================================================================
# Mount Operations
# =============================================================================

function Mount-RSRShare {
    <#
    .SYNOPSIS
        Mount a network share

    .DESCRIPTION
        Maps a network share to a drive letter or accessible path

    .PARAMETER Source
        Network share path (UNC, SMB URL, etc.)

    .PARAMETER DriveLetter
        Drive letter to map (e.g., 'Z')

    .PARAMETER Credential
        Credentials for authentication

    .PARAMETER Persistent
        Make the mapping persistent across reboots

    .PARAMETER Name
        Save configuration with this name

    .EXAMPLE
        Mount-RSRShare -Source "\\server\share" -DriveLetter Z

    .EXAMPLE
        Mount-RSRShare -Source "\\server\share" -DriveLetter Z -Credential (Get-Credential) -Persistent
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Source,

        [Parameter(Position = 1)]
        [ValidatePattern('^[A-Z]$')]
        [string]$DriveLetter,

        [PSCredential]$Credential,

        [switch]$Persistent,

        [string]$Name
    )

    # Convert to UNC path
    $uncPath = ConvertTo-RSRUNCPath -Path $Source

    # Validate path
    if (-not (Test-RSRSharePath -Path $uncPath -Type 'smb')) {
        Write-RSRError "Invalid share path: $Source"
        return $false
    }

    # Parse path for server info
    $parsed = Split-RSRSharePath -Path $uncPath
    if (-not $parsed) {
        Write-RSRError "Could not parse share path"
        return $false
    }

    # Auto-assign drive letter if not specified
    if (-not $DriveLetter) {
        $usedLetters = (Get-PSDrive -PSProvider FileSystem).Name
        $DriveLetter = ('Z','Y','X','W','V','U','T','S','R','Q','P','O','N','M','L','K','J','I','H','G','F','E','D' |
            Where-Object { $_ -notin $usedLetters } | Select-Object -First 1)

        if (-not $DriveLetter) {
            Write-RSRError "No available drive letters"
            return $false
        }

        Write-RSRInfo "Auto-assigned drive letter: $DriveLetter"
    }

    # Check if drive letter is in use
    if (Test-Path "${DriveLetter}:") {
        Write-RSRWarning "Drive $DriveLetter`: is already in use"
        $current = Get-PSDrive -Name $DriveLetter -ErrorAction SilentlyContinue
        if ($current.DisplayRoot -eq $uncPath) {
            Write-RSRInfo "Already mapped to the same share"
            return $true
        }
        return $false
    }

    # Try to get credentials from storage if name provided
    if ($Name -and -not $Credential) {
        $Credential = Get-RSRShareCredential -Name $Name
    }

    if ($PSCmdlet.ShouldProcess("$uncPath -> ${DriveLetter}:", "Mount network share")) {
        Write-RSRInfo "Mounting $uncPath to ${DriveLetter}:..."

        # Try New-PSDrive first, fall back to net use
        $mounted = $false

        # Method 1: New-PSDrive (preferred for PowerShell)
        try {
            $params = @{
                Name = $DriveLetter
                PSProvider = 'FileSystem'
                Root = $uncPath
                Persist = $Persistent
                Scope = 'Global'
            }

            if ($Credential) {
                $params['Credential'] = $Credential
            }

            New-PSDrive @params -ErrorAction Stop | Out-Null
            $mounted = $true
        }
        catch {
            Write-RSRWarning "PSDrive method failed, trying net use..."

            # Method 2: net use (fallback, better compatibility)
            try {
                $netUseArgs = @("${DriveLetter}:", $uncPath)

                if ($Credential) {
                    $netUseArgs += "/user:$($Credential.UserName)"
                    $netUseArgs += $Credential.GetNetworkCredential().Password
                }

                if ($Persistent) {
                    $netUseArgs += "/persistent:yes"
                } else {
                    $netUseArgs += "/persistent:no"
                }

                $result = & net use @netUseArgs 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $mounted = $true
                } else {
                    throw "net use failed: $result"
                }
            }
            catch {
                Write-RSRError "Failed to mount share: $_"
                return $false
            }
        }

        if ($mounted) {
            Write-RSRSuccess "Successfully mounted to ${DriveLetter}:"

            # Save configuration if name provided
            if ($Name) {
                Save-RSRShare -Name $Name -Source $uncPath -Target "${DriveLetter}:" -Automount $Persistent
            }

            return $true
        }
    }
}

function Dismount-RSRShare {
    <#
    .SYNOPSIS
        Unmount a network share

    .PARAMETER DriveLetter
        Drive letter to unmount

    .PARAMETER Path
        Mount path to unmount

    .PARAMETER Force
        Force unmount even if in use
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0)]
        [ValidatePattern('^[A-Z]:?$')]
        [string]$DriveLetter,

        [string]$Path,

        [switch]$Force
    )

    # Normalize drive letter
    if ($DriveLetter) {
        $DriveLetter = $DriveLetter.TrimEnd(':')
    }
    elseif ($Path) {
        # Try to find drive letter from path
        $drives = Get-RSRMountedShares
        $match = $drives | Where-Object { $_.LocalPath -eq $Path -or $_.RemotePath -eq $Path }
        if ($match) {
            $DriveLetter = $match.LocalPath.TrimEnd(':')
        }
    }

    if (-not $DriveLetter) {
        Write-RSRError "Drive letter or path required"
        return $false
    }

    if (-not (Test-Path "${DriveLetter}:")) {
        Write-RSRWarning "Drive ${DriveLetter}: is not mounted"
        return $true
    }

    if ($PSCmdlet.ShouldProcess("${DriveLetter}:", "Unmount network share")) {
        try {
            Remove-PSDrive -Name $DriveLetter -Force:$Force -ErrorAction Stop

            # Also remove from net use if persistent
            $null = net use "${DriveLetter}:" /delete /y 2>$null

            Write-RSRSuccess "Successfully unmounted ${DriveLetter}:"
            return $true
        }
        catch {
            Write-RSRError "Failed to unmount: $_"
            return $false
        }
    }
}

# =============================================================================
# Share Discovery
# =============================================================================

function Get-RSRMountedShares {
    <#
    .SYNOPSIS
        List currently mounted network shares
    #>
    [CmdletBinding()]
    param()

    # Get mapped drives
    Get-PSDrive -PSProvider FileSystem | Where-Object { $_.DisplayRoot -like '\\*' } | ForEach-Object {
        [PSCustomObject]@{
            LocalPath = "$($_.Name):"
            RemotePath = $_.DisplayRoot
            Used = $_.Used
            Free = $_.Free
            Persistent = $false  # Will be updated below
        }
    }

    # Check persistent mappings
    $netUse = net use 2>$null | Where-Object { $_ -match '^[A-Z]:' }
    # Note: Could parse net use output for more details
}

function Find-RSRNetworkShares {
    <#
    .SYNOPSIS
        Discover shares on a server

    .PARAMETER Server
        Server hostname or IP

    .PARAMETER Credential
        Credentials for authentication
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Server,

        [PSCredential]$Credential
    )

    Write-RSRInfo "Discovering shares on $Server..."

    try {
        $shares = if ($Credential) {
            # Use WMI with credentials
            Get-WmiObject -Class Win32_Share -ComputerName $Server -Credential $Credential -ErrorAction Stop
        }
        else {
            # Try anonymous/current user
            Get-WmiObject -Class Win32_Share -ComputerName $Server -ErrorAction Stop
        }

        $shares | Where-Object { $_.Type -eq 0 } | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Path = "\\$Server\$($_.Name)"
                Description = $_.Description
                Type = 'Disk'
            }
        }
    }
    catch {
        # Fallback to net view
        Write-RSRWarning "WMI failed, trying net view..."

        $netView = net view "\\$Server" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $netView | Where-Object { $_ -match '^\s*(\S+)\s+Disk' } | ForEach-Object {
                $shareName = $Matches[1]
                [PSCustomObject]@{
                    Name = $shareName
                    Path = "\\$Server\$shareName"
                    Description = ''
                    Type = 'Disk'
                }
            }
        }
        else {
            Write-RSRError "Failed to discover shares on $Server"
        }
    }
}

function Search-RSRNetworkServers {
    <#
    .SYNOPSIS
        Scan network for file servers

    .PARAMETER Subnet
        Subnet to scan (optional, auto-detects if not specified)
    #>
    [CmdletBinding()]
    param(
        [string]$Subnet
    )

    Write-RSRInfo "Scanning network for file servers..."

    # Get computers from network neighborhood
    try {
        $computers = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Name

        # Also try to get from network browser
        $network = New-Object -ComObject WScript.Network

        # Use net view to find servers
        $netView = net view 2>$null
        if ($netView) {
            $netView | Where-Object { $_ -match '^\\\\(\S+)' } | ForEach-Object {
                $Matches[1]
            }
        }
    }
    catch {
        Write-RSRWarning "Network discovery limited: $_"
    }
}

function Test-RSRShareConnectivity {
    <#
    .SYNOPSIS
        Test connectivity to a share

    .PARAMETER Source
        Share path to test
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source
    )

    $uncPath = ConvertTo-RSRUNCPath -Path $Source
    $parsed = Split-RSRSharePath -Path $uncPath

    if (-not $parsed) {
        Write-RSRError "Invalid share path"
        return $false
    }

    Write-RSRInfo "Testing connectivity to $($parsed.Server)..."

    # Test server connectivity
    $ping = Test-Connection -ComputerName $parsed.Server -Count 1 -Quiet
    if (-not $ping) {
        Write-RSRError "Server is not reachable"
        return $false
    }
    Write-RSRSuccess "Server is reachable"

    # Test SMB port
    $smb = Test-NetConnection -ComputerName $parsed.Server -Port 445 -WarningAction SilentlyContinue
    if (-not $smb.TcpTestSucceeded) {
        Write-RSRWarning "SMB port (445) is not accessible"
    }
    else {
        Write-RSRSuccess "SMB port is accessible"
    }

    # Test share accessibility
    Write-RSRInfo "Testing share access..."
    if (Test-Path $parsed.FullPath) {
        Write-RSRSuccess "Share is accessible"
        return $true
    }
    else {
        Write-RSRWarning "Share is not accessible (may require authentication)"
        return $false
    }
}

# =============================================================================
# Saved Share Management
# =============================================================================

function Get-RSRSavedShares {
    <#
    .SYNOPSIS
        Get list of saved share configurations
    #>
    [CmdletBinding()]
    param(
        [string]$Name
    )

    Initialize-RSRShareModule

    if (-not (Test-Path $Script:SavedSharesFile)) {
        return @()
    }

    $config = Get-Content $Script:SavedSharesFile -Raw | ConvertFrom-Json

    if ($Name) {
        return $config.shares | Where-Object { $_.name -eq $Name }
    }

    return $config.shares
}

function Save-RSRShare {
    <#
    .SYNOPSIS
        Save a share configuration
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Source,

        [string]$Target,

        [string]$Options,

        [bool]$Automount = $false
    )

    Initialize-RSRShareModule

    $config = Get-Content $Script:SavedSharesFile -Raw | ConvertFrom-Json

    # Remove existing entry with same name
    $config.shares = @($config.shares | Where-Object { $_.name -ne $Name })

    # Add new entry
    $entry = [PSCustomObject]@{
        name = $Name
        source = $Source
        target = $Target
        type = 'smb'
        options = $Options
        automount = $Automount
    }

    $config.shares += $entry

    $config | ConvertTo-Json -Depth 10 | Set-Content $Script:SavedSharesFile

    Write-RSRSuccess "Share '$Name' saved"
}

function Remove-RSRSavedShare {
    <#
    .SYNOPSIS
        Remove a saved share configuration
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $config = Get-Content $Script:SavedSharesFile -Raw | ConvertFrom-Json

    $existing = $config.shares | Where-Object { $_.name -eq $Name }
    if (-not $existing) {
        Write-RSRWarning "Share '$Name' not found"
        return
    }

    if ($PSCmdlet.ShouldProcess($Name, "Remove saved share")) {
        $config.shares = @($config.shares | Where-Object { $_.name -ne $Name })
        $config | ConvertTo-Json -Depth 10 | Set-Content $Script:SavedSharesFile

        # Also remove credentials
        Remove-RSRShareCredential -Name $Name

        Write-RSRSuccess "Share '$Name' removed"
    }
}

# =============================================================================
# Output Helpers
# =============================================================================

function Write-RSRInfo {
    param([string]$Message)
    Write-Host "▸ $Message" -ForegroundColor Blue
}

function Write-RSRSuccess {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-RSRWarning {
    param([string]$Message)
    Write-Warning $Message
}

function Write-RSRError {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    # Core operations
    'Mount-RSRShare'
    'Dismount-RSRShare'

    # Discovery
    'Get-RSRMountedShares'
    'Find-RSRNetworkShares'
    'Search-RSRNetworkServers'
    'Test-RSRShareConnectivity'

    # Configuration
    'Get-RSRSavedShares'
    'Save-RSRShare'
    'Remove-RSRSavedShare'

    # Credentials
    'Get-RSRShareCredential'
    'Set-RSRShareCredential'
    'Remove-RSRShareCredential'
    'Get-RSRShareCredentialList'

    # Utilities
    'Get-RSRShareType'
    'Test-RSRSharePath'
    'ConvertTo-RSRUNCPath'
    'Split-RSRSharePath'

    # Initialization
    'Initialize-RSRShareModule'
)

# Initialize on import
Initialize-RSRShareModule

