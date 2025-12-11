# RSR.Users.psm1 - RSR User Management PowerShell Module
# Provides: user/group management for Windows (local users)
#
# Usage: Import-Module RSR (loads via manifest)

#Requires -Version 5.1

# =============================================================================
# User Existence & Info
# =============================================================================

function Test-RSRUserExists {
    <#
    .SYNOPSIS
        Check if a local user exists
    .PARAMETER Username
        The username to check
    .EXAMPLE
        if (Test-RSRUserExists 'john') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    $null -ne (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)
}

function Get-RSRUser {
    <#
    .SYNOPSIS
        Get a local user by name
    .PARAMETER Username
        The username to get
    .EXAMPLE
        $user = Get-RSRUser 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
}

function Get-RSRUserInfo {
    <#
    .SYNOPSIS
        Get detailed user information
    .PARAMETER Username
        The username to get info for
    .EXAMPLE
        $info = Get-RSRUserInfo 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    $user = Get-LocalUser -Name $Username -ErrorAction SilentlyContinue
    if (-not $user) {
        return $null
    }

    [PSCustomObject]@{
        Username = $user.Name
        SID = $user.SID.Value
        FullName = $user.FullName
        Description = $user.Description
        Enabled = $user.Enabled
        Home = "C:\Users\$($user.Name)"
        LastLogon = $user.LastLogon
        PasswordExpires = $user.PasswordExpires
        PasswordLastSet = $user.PasswordLastSet
        PasswordRequired = $user.PasswordRequired
        UserMayChangePassword = $user.UserMayChangePassword
    }
}

function Get-RSRUsers {
    <#
    .SYNOPSIS
        Get all local users
    .EXAMPLE
        $users = Get-RSRUsers
    #>
    [CmdletBinding()]
    param()

    Get-LocalUser | Select-Object Name, FullName, Enabled, SID, Description
}

function Get-RSRHumanUsers {
    <#
    .SYNOPSIS
        Get human (non-system) local users
    .EXAMPLE
        $users = Get-RSRHumanUsers
    #>
    [CmdletBinding()]
    param()

    Get-LocalUser | Where-Object {
        $_.Name -notmatch '^(Administrator|Guest|DefaultAccount|WDAGUtilityAccount)$' -and
        $_.Enabled
    } | Select-Object Name, FullName, Enabled, Description
}

# =============================================================================
# User Creation
# =============================================================================

function New-RSRUser {
    <#
    .SYNOPSIS
        Create a new local user
    .PARAMETER Username
        The username for the new user
    .PARAMETER FullName
        Full name of the user
    .PARAMETER Description
        User description
    .PARAMETER Password
        Password as SecureString
    .PARAMETER NoPassword
        Create user without password
    .PARAMETER PasswordNeverExpires
        Password never expires
    .PARAMETER UserCannotChangePassword
        User cannot change password
    .EXAMPLE
        New-RSRUser -Username 'john' -FullName 'John Doe' -Password $securePass
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [string]$FullName,

        [string]$Description,

        [SecureString]$Password,

        [switch]$NoPassword,

        [switch]$PasswordNeverExpires,

        [switch]$UserCannotChangePassword
    )

    if (Test-RSRUserExists $Username) {
        throw "User '$Username' already exists"
    }

    $params = @{
        Name = $Username
    }

    if ($FullName) { $params.FullName = $FullName }
    if ($Description) { $params.Description = $Description }

    if ($Password) {
        $params.Password = $Password
    } elseif ($NoPassword) {
        $params.NoPassword = $true
    } else {
        # Generate random password
        $randomPass = New-RSRRandomPassword
        $params.Password = ConvertTo-SecureString $randomPass -AsPlainText -Force
        Write-RSRInfo "Generated password: $randomPass"
    }

    if ($PasswordNeverExpires) { $params.PasswordNeverExpires = $true }
    if ($UserCannotChangePassword) { $params.UserMayNotChangePassword = $true }

    New-LocalUser @params
    Write-RSROk "User '$Username' created"
}

# =============================================================================
# User Deletion
# =============================================================================

function Remove-RSRUser {
    <#
    .SYNOPSIS
        Remove a local user
    .PARAMETER Username
        The username to remove
    .PARAMETER RemoveHome
        Also remove user's home directory
    .PARAMETER Force
        Don't prompt for confirmation
    .EXAMPLE
        Remove-RSRUser 'john' -RemoveHome
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username,

        [switch]$RemoveHome,

        [switch]$Force
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    # Safety check
    if ($Username -eq 'Administrator') {
        throw "Cannot delete Administrator account"
    }

    $homeDir = "C:\Users\$Username"

    if ($Force -or $PSCmdlet.ShouldProcess($Username, 'Remove user')) {
        Remove-LocalUser -Name $Username
        Write-RSROk "User '$Username' removed"

        if ($RemoveHome -and (Test-Path $homeDir)) {
            Remove-Item -Path $homeDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-RSROk "Home directory removed: $homeDir"
        }
    }
}

# =============================================================================
# User Enable/Disable
# =============================================================================

function Enable-RSRUser {
    <#
    .SYNOPSIS
        Enable (unlock) a local user account
    .PARAMETER Username
        The username to enable
    .EXAMPLE
        Enable-RSRUser 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Enable-LocalUser -Name $Username
    Write-RSROk "User '$Username' enabled"
}

function Disable-RSRUser {
    <#
    .SYNOPSIS
        Disable (lock) a local user account
    .PARAMETER Username
        The username to disable
    .EXAMPLE
        Disable-RSRUser 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Disable-LocalUser -Name $Username
    Write-RSROk "User '$Username' disabled"
}

# =============================================================================
# Password Management
# =============================================================================

function Set-RSRUserPassword {
    <#
    .SYNOPSIS
        Set password for a local user
    .PARAMETER Username
        The username
    .PARAMETER Password
        The new password as SecureString
    .EXAMPLE
        Set-RSRUserPassword 'john' -Password $securePass
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username,

        [Parameter(Mandatory)]
        [SecureString]$Password
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Set-LocalUser -Name $Username -Password $Password
    Write-RSROk "Password set for user '$Username'"
}

function New-RSRRandomPassword {
    <#
    .SYNOPSIS
        Generate a random password
    .PARAMETER Length
        Password length (default: 16)
    .PARAMETER AsSecureString
        Return as SecureString
    .EXAMPLE
        $pass = New-RSRRandomPassword -Length 20
    #>
    [CmdletBinding()]
    param(
        [int]$Length = 16,

        [switch]$AsSecureString
    )

    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
    $password = -join ((1..$Length) | ForEach-Object {
        $chars[(Get-Random -Maximum $chars.Length)]
    })

    if ($AsSecureString) {
        ConvertTo-SecureString $password -AsPlainText -Force
    } else {
        $password
    }
}

# =============================================================================
# Group Management
# =============================================================================

function Test-RSRGroupExists {
    <#
    .SYNOPSIS
        Check if a local group exists
    .PARAMETER GroupName
        The group name to check
    .EXAMPLE
        if (Test-RSRGroupExists 'Developers') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$GroupName
    )

    $null -ne (Get-LocalGroup -Name $GroupName -ErrorAction SilentlyContinue)
}

function Get-RSRGroups {
    <#
    .SYNOPSIS
        Get all local groups
    .EXAMPLE
        $groups = Get-RSRGroups
    #>
    [CmdletBinding()]
    param()

    Get-LocalGroup | Select-Object Name, Description, SID
}

function New-RSRGroup {
    <#
    .SYNOPSIS
        Create a new local group
    .PARAMETER GroupName
        The group name
    .PARAMETER Description
        Group description
    .EXAMPLE
        New-RSRGroup 'Developers' -Description 'Development team'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$GroupName,

        [string]$Description
    )

    if (Test-RSRGroupExists $GroupName) {
        throw "Group '$GroupName' already exists"
    }

    $params = @{ Name = $GroupName }
    if ($Description) { $params.Description = $Description }

    New-LocalGroup @params
    Write-RSROk "Group '$GroupName' created"
}

function Remove-RSRGroup {
    <#
    .SYNOPSIS
        Remove a local group
    .PARAMETER GroupName
        The group name to remove
    .EXAMPLE
        Remove-RSRGroup 'Developers'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$GroupName
    )

    if (-not (Test-RSRGroupExists $GroupName)) {
        throw "Group '$GroupName' does not exist"
    }

    if ($PSCmdlet.ShouldProcess($GroupName, 'Remove group')) {
        Remove-LocalGroup -Name $GroupName
        Write-RSROk "Group '$GroupName' removed"
    }
}

function Add-RSRGroupMember {
    <#
    .SYNOPSIS
        Add a user to a group
    .PARAMETER GroupName
        The group name
    .PARAMETER Username
        The username to add
    .EXAMPLE
        Add-RSRGroupMember 'Administrators' 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$GroupName,

        [Parameter(Mandatory, Position = 1)]
        [string]$Username
    )

    if (-not (Test-RSRGroupExists $GroupName)) {
        throw "Group '$GroupName' does not exist"
    }

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Add-LocalGroupMember -Group $GroupName -Member $Username
    Write-RSROk "Added '$Username' to group '$GroupName'"
}

function Remove-RSRGroupMember {
    <#
    .SYNOPSIS
        Remove a user from a group
    .PARAMETER GroupName
        The group name
    .PARAMETER Username
        The username to remove
    .EXAMPLE
        Remove-RSRGroupMember 'Administrators' 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$GroupName,

        [Parameter(Mandatory, Position = 1)]
        [string]$Username
    )

    if (-not (Test-RSRGroupExists $GroupName)) {
        throw "Group '$GroupName' does not exist"
    }

    Remove-LocalGroupMember -Group $GroupName -Member $Username -ErrorAction SilentlyContinue
    Write-RSROk "Removed '$Username' from group '$GroupName'"
}

function Get-RSRUserGroups {
    <#
    .SYNOPSIS
        Get groups a user belongs to
    .PARAMETER Username
        The username
    .EXAMPLE
        $groups = Get-RSRUserGroups 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Get-LocalGroup | Where-Object {
        (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -match "\\$Username$"
    } | Select-Object Name, Description
}

# =============================================================================
# Sudo/Admin Operations
# =============================================================================

function Test-RSRUserHasSudo {
    <#
    .SYNOPSIS
        Check if user has administrator privileges
    .PARAMETER Username
        The username to check
    .EXAMPLE
        if (Test-RSRUserHasSudo 'john') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        return $false
    }

    $adminGroup = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue
    $adminGroup.Name -match "\\$Username$"
}

function Grant-RSRUserSudo {
    <#
    .SYNOPSIS
        Grant administrator privileges to a user
    .PARAMETER Username
        The username
    .EXAMPLE
        Grant-RSRUserSudo 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Add-LocalGroupMember -Group 'Administrators' -Member $Username -ErrorAction SilentlyContinue
    Write-RSROk "Granted administrator privileges to '$Username'"
}

function Revoke-RSRUserSudo {
    <#
    .SYNOPSIS
        Revoke administrator privileges from a user
    .PARAMETER Username
        The username
    .EXAMPLE
        Revoke-RSRUserSudo 'john'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username
    )

    if (-not (Test-RSRUserExists $Username)) {
        throw "User '$Username' does not exist"
    }

    Remove-LocalGroupMember -Group 'Administrators' -Member $Username -ErrorAction SilentlyContinue
    Write-RSROk "Revoked administrator privileges from '$Username'"
}

# =============================================================================
# Export
# =============================================================================

Export-ModuleMember -Function @(
    'Test-RSRUserExists',
    'Get-RSRUser',
    'Get-RSRUserInfo',
    'Get-RSRUsers',
    'Get-RSRHumanUsers',
    'New-RSRUser',
    'Remove-RSRUser',
    'Enable-RSRUser',
    'Disable-RSRUser',
    'Set-RSRUserPassword',
    'New-RSRRandomPassword',
    'Test-RSRGroupExists',
    'Get-RSRGroups',
    'New-RSRGroup',
    'Remove-RSRGroup',
    'Add-RSRGroupMember',
    'Remove-RSRGroupMember',
    'Get-RSRUserGroups',
    'Test-RSRUserHasSudo',
    'Grant-RSRUserSudo',
    'Revoke-RSRUserSudo'
)

