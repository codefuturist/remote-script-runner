# RSR.Validate.psm1 - RSR Validation PowerShell Module
# Provides: input validation functions
#
# Usage: Import-Module RSR (loads via manifest)

#Requires -Version 5.1

# =============================================================================
# Username Validation
# =============================================================================

function Test-RSRUsername {
    <#
    .SYNOPSIS
        Validate username format
    .PARAMETER Username
        The username to validate
    .PARAMETER Detailed
        Return detailed validation result instead of boolean
    .EXAMPLE
        if (Test-RSRUsername 'john_doe') { ... }
    .EXAMPLE
        $result = Test-RSRUsername 'john_doe' -Detailed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Username,

        [switch]$Detailed
    )

    $result = @{
        IsValid = $true
        Errors = @()
    }

    # Check empty
    if ([string]::IsNullOrWhiteSpace($Username)) {
        $result.IsValid = $false
        $result.Errors += 'Username cannot be empty'
    }

    # Check length
    if ($Username.Length -gt 32) {
        $result.IsValid = $false
        $result.Errors += 'Username must be 32 characters or less'
    }

    # Check format (starts with letter, alphanumeric + underscore + hyphen)
    if ($Username -notmatch '^[a-z][a-z0-9_-]*$') {
        $result.IsValid = $false
        if ($Username -notmatch '^[a-z]') {
            $result.Errors += 'Username must start with a lowercase letter'
        } else {
            $result.Errors += 'Username can only contain lowercase letters, numbers, underscore, and hyphen'
        }
    }

    if ($Detailed) {
        [PSCustomObject]$result
    } else {
        $result.IsValid
    }
}

# =============================================================================
# Password Validation
# =============================================================================

function Test-RSRPassword {
    <#
    .SYNOPSIS
        Validate password meets minimum requirements
    .PARAMETER Password
        The password to validate (as SecureString or plain string)
    .PARAMETER MinLength
        Minimum password length (default: 8)
    .EXAMPLE
        if (Test-RSRPassword $password) { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        $Password,

        [int]$MinLength = 8
    )

    # Convert SecureString to plain text for validation
    $plainPassword = if ($Password -is [System.Security.SecureString]) {
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        )
    } else {
        $Password
    }

    $plainPassword.Length -ge $MinLength
}

function Test-RSRPasswordComplex {
    <#
    .SYNOPSIS
        Validate password meets complexity requirements
    .DESCRIPTION
        Checks: 8+ chars, uppercase, lowercase, number, special character
    .PARAMETER Password
        The password to validate
    .PARAMETER Detailed
        Return detailed validation result
    .EXAMPLE
        if (Test-RSRPasswordComplex $password) { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        $Password,

        [switch]$Detailed
    )

    # Convert SecureString to plain text for validation
    $plainPassword = if ($Password -is [System.Security.SecureString]) {
        [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        )
    } else {
        $Password
    }

    $result = @{
        IsValid = $true
        Errors = @()
    }

    if ($plainPassword.Length -lt 8) {
        $result.IsValid = $false
        $result.Errors += 'Password must be at least 8 characters'
    }

    if ($plainPassword -cnotmatch '[A-Z]') {
        $result.IsValid = $false
        $result.Errors += 'Password must contain at least one uppercase letter'
    }

    if ($plainPassword -cnotmatch '[a-z]') {
        $result.IsValid = $false
        $result.Errors += 'Password must contain at least one lowercase letter'
    }

    if ($plainPassword -notmatch '[0-9]') {
        $result.IsValid = $false
        $result.Errors += 'Password must contain at least one number'
    }

    if ($plainPassword -notmatch '[!@#$%^&*()_+=\-\[\]{};:,.<>?/\\|`~]') {
        $result.IsValid = $false
        $result.Errors += 'Password must contain at least one special character'
    }

    if ($Detailed) {
        [PSCustomObject]$result
    } else {
        $result.IsValid
    }
}

# =============================================================================
# Network Validation
# =============================================================================

function Test-RSRIPv4 {
    <#
    .SYNOPSIS
        Validate IPv4 address format
    .PARAMETER IPAddress
        The IP address to validate
    .EXAMPLE
        if (Test-RSRIPv4 '192.168.1.1') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$IPAddress
    )

    try {
        $ip = [System.Net.IPAddress]::Parse($IPAddress)
        $ip.AddressFamily -eq 'InterNetwork'
    } catch {
        $false
    }
}

function Test-RSRIPv6 {
    <#
    .SYNOPSIS
        Validate IPv6 address format
    .PARAMETER IPAddress
        The IP address to validate
    .EXAMPLE
        if (Test-RSRIPv6 '2001:db8::1') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$IPAddress
    )

    try {
        $ip = [System.Net.IPAddress]::Parse($IPAddress)
        $ip.AddressFamily -eq 'InterNetworkV6'
    } catch {
        $false
    }
}

function Test-RSRHostname {
    <#
    .SYNOPSIS
        Validate hostname format
    .PARAMETER Hostname
        The hostname to validate
    .EXAMPLE
        if (Test-RSRHostname 'server.example.com') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Hostname
    )

    # RFC 1123 hostname validation
    if ($Hostname.Length -lt 1 -or $Hostname.Length -gt 253) {
        return $false
    }

    $Hostname -match '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*$'
}

function Test-RSRPort {
    <#
    .SYNOPSIS
        Validate port number
    .PARAMETER Port
        The port number to validate
    .EXAMPLE
        if (Test-RSRPort 8080) { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int]$Port
    )

    $Port -ge 1 -and $Port -le 65535
}

function Test-RSREmail {
    <#
    .SYNOPSIS
        Validate email address format
    .PARAMETER Email
        The email address to validate
    .EXAMPLE
        if (Test-RSREmail 'user@example.com') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Email
    )

    try {
        $addr = [System.Net.Mail.MailAddress]::new($Email)
        $addr.Address -eq $Email
    } catch {
        $false
    }
}

function Test-RSRUrl {
    <#
    .SYNOPSIS
        Validate URL format
    .PARAMETER Url
        The URL to validate
    .PARAMETER RequireHttps
        Require HTTPS scheme
    .EXAMPLE
        if (Test-RSRUrl 'https://example.com') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Url,

        [switch]$RequireHttps
    )

    try {
        $uri = [System.Uri]::new($Url)

        if ($RequireHttps) {
            return $uri.Scheme -eq 'https'
        }

        $uri.Scheme -in @('http', 'https')
    } catch {
        $false
    }
}

# =============================================================================
# Export
# =============================================================================

Export-ModuleMember -Function @(
    'Test-RSRUsername',
    'Test-RSRPassword',
    'Test-RSRPasswordComplex',
    'Test-RSRIPv4',
    'Test-RSRIPv6',
    'Test-RSRHostname',
    'Test-RSRPort',
    'Test-RSREmail',
    'Test-RSRUrl'
)

