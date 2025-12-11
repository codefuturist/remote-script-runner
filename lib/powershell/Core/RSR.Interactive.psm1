# RSR.Interactive.psm1 - RSR Interactive PowerShell Module
# Provides: prompts, menus, progress indicators
#
# Usage: Import-Module RSR (loads via manifest)

#Requires -Version 5.1

# =============================================================================
# Yes/No Confirmation
# =============================================================================

function Read-RSRConfirm {
    <#
    .SYNOPSIS
        Prompt user for yes/no confirmation
    .PARAMETER Question
        The question to ask
    .PARAMETER Default
        Default answer: 'Yes', 'No', or $null for no default
    .EXAMPLE
        if (Read-RSRConfirm 'Continue?') { ... }
    .EXAMPLE
        if (Read-RSRConfirm 'Delete files?' -Default 'No') { ... }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Question,

        [ValidateSet('Yes', 'No', $null)]
        [string]$Default = $null
    )

    # Build hint
    $hint = switch ($Default) {
        'Yes' { '[Y/n]' }
        'No'  { '[y/N]' }
        default { '[y/n]' }
    }

    # Non-interactive: use default
    if (-not [Environment]::UserInteractive) {
        return $Default -eq 'Yes'
    }

    while ($true) {
        Write-Host "? " -ForegroundColor Cyan -NoNewline
        Write-Host "$Question $hint " -NoNewline
        $response = Read-Host

        # Empty response: use default
        if ([string]::IsNullOrWhiteSpace($response) -and $Default) {
            return $Default -eq 'Yes'
        }

        switch -Regex ($response) {
            '^(y|yes)$' { return $true }
            '^(n|no)$' { return $false }
            default { Write-Host "  Please answer yes or no" -ForegroundColor Yellow }
        }
    }
}

# =============================================================================
# Text Input
# =============================================================================

function Read-RSRInput {
    <#
    .SYNOPSIS
        Prompt user for text input
    .PARAMETER Prompt
        The prompt text
    .PARAMETER Default
        Default value if user enters nothing
    .PARAMETER Validator
        ScriptBlock to validate input (should return $true for valid)
    .EXAMPLE
        $name = Read-RSRInput 'Enter name'
    .EXAMPLE
        $port = Read-RSRInput 'Enter port' -Default '8080' -Validator { param($v) $v -match '^\d+$' }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Prompt,

        [string]$Default = '',

        [scriptblock]$Validator = $null
    )

    $hint = if ($Default) { " (default: $Default)" } else { '' }

    # Non-interactive: use default
    if (-not [Environment]::UserInteractive) {
        return $Default
    }

    while ($true) {
        Write-Host "? " -ForegroundColor Cyan -NoNewline
        Write-Host "$Prompt$hint`: " -NoNewline
        $response = Read-Host

        # Use default if empty
        if ([string]::IsNullOrWhiteSpace($response)) {
            $response = $Default
        }

        # Validate if validator provided
        if ($Validator) {
            if (& $Validator $response) {
                return $response
            } else {
                Write-Host "  Invalid input, please try again" -ForegroundColor Yellow
            }
        } else {
            return $response
        }
    }
}

function Read-RSRPassword {
    <#
    .SYNOPSIS
        Prompt user for password (hidden input)
    .PARAMETER Prompt
        The prompt text
    .PARAMETER Confirm
        Require password confirmation
    .PARAMETER AsSecureString
        Return as SecureString instead of plain text
    .EXAMPLE
        $password = Read-RSRPassword 'Enter password'
    .EXAMPLE
        $password = Read-RSRPassword 'Enter password' -Confirm -AsSecureString
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Prompt = 'Enter password',

        [switch]$Confirm,

        [switch]$AsSecureString
    )

    if (-not [Environment]::UserInteractive) {
        throw "Password input requires interactive mode"
    }

    while ($true) {
        Write-Host "? " -ForegroundColor Cyan -NoNewline
        Write-Host "$Prompt`: " -NoNewline
        $pass1 = Read-Host -AsSecureString

        if (-not $Confirm) {
            if ($AsSecureString) {
                return $pass1
            } else {
                return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1)
                )
            }
        }

        Write-Host "? " -ForegroundColor Cyan -NoNewline
        Write-Host "Confirm $Prompt`: " -NoNewline
        $pass2 = Read-Host -AsSecureString

        # Compare passwords
        $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1)
        )
        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2)
        )

        if ($plain1 -eq $plain2) {
            if ($AsSecureString) {
                return $pass1
            } else {
                return $plain1
            }
        } else {
            Write-Host "  Passwords do not match, please try again" -ForegroundColor Yellow
        }
    }
}

# =============================================================================
# Selection Menus
# =============================================================================

function Read-RSRSelect {
    <#
    .SYNOPSIS
        Display single-select menu
    .PARAMETER Title
        Menu title
    .PARAMETER Options
        Array of options to choose from
    .PARAMETER Default
        Default selection index (0-based)
    .EXAMPLE
        $choice = Read-RSRSelect 'Choose environment' @('Development', 'Staging', 'Production')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Title,

        [Parameter(Mandatory, Position = 1)]
        [string[]]$Options,

        [int]$Default = 0
    )

    if ($Options.Count -eq 0) {
        return $null
    }

    # Non-interactive: return default
    if (-not [Environment]::UserInteractive) {
        return $Options[$Default]
    }

    Write-Host "? " -ForegroundColor Cyan -NoNewline
    Write-Host "$Title"

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $prefix = if ($i -eq $Default) { '>' } else { ' ' }
        Write-Host "  $prefix [$($i + 1)] $($Options[$i])"
    }

    while ($true) {
        Write-Host "  Enter number (1-$($Options.Count)): " -NoNewline
        $response = Read-Host

        if ([string]::IsNullOrWhiteSpace($response)) {
            return $Options[$Default]
        }

        if ($response -match '^\d+$') {
            $index = [int]$response - 1
            if ($index -ge 0 -and $index -lt $Options.Count) {
                return $Options[$index]
            }
        }

        Write-Host "  Invalid selection" -ForegroundColor Yellow
    }
}

function Read-RSRMultiSelect {
    <#
    .SYNOPSIS
        Display multi-select menu
    .PARAMETER Title
        Menu title
    .PARAMETER Options
        Array of options to choose from
    .EXAMPLE
        $choices = Read-RSRMultiSelect 'Select features' @('Logging', 'Monitoring', 'Alerts')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Title,

        [Parameter(Mandatory, Position = 1)]
        [string[]]$Options
    )

    if ($Options.Count -eq 0) {
        return @()
    }

    # Non-interactive: return empty
    if (-not [Environment]::UserInteractive) {
        return @()
    }

    Write-Host "? " -ForegroundColor Cyan -NoNewline
    Write-Host "$Title (enter numbers separated by comma)"

    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "    [$($i + 1)] $($Options[$i])"
    }

    Write-Host "  Enter numbers (e.g., 1,3,4): " -NoNewline
    $response = Read-Host

    if ([string]::IsNullOrWhiteSpace($response)) {
        return @()
    }

    $selected = @()
    $response.Split(',') | ForEach-Object {
        $num = $_.Trim()
        if ($num -match '^\d+$') {
            $index = [int]$num - 1
            if ($index -ge 0 -and $index -lt $Options.Count) {
                $selected += $Options[$index]
            }
        }
    }

    return $selected
}

# =============================================================================
# Progress Indicators
# =============================================================================

function Show-RSRProgress {
    <#
    .SYNOPSIS
        Show progress bar
    .PARAMETER Activity
        The activity description
    .PARAMETER Status
        Current status message
    .PARAMETER PercentComplete
        Completion percentage (0-100)
    .PARAMETER Complete
        Mark as complete and clear progress
    .EXAMPLE
        Show-RSRProgress 'Downloading' 'file.zip' 50
    .EXAMPLE
        Show-RSRProgress -Complete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Activity = 'Processing',

        [Parameter(Position = 1)]
        [string]$Status = '',

        [Parameter(Position = 2)]
        [int]$PercentComplete = 0,

        [switch]$Complete
    )

    if ($Complete) {
        Write-Progress -Activity $Activity -Completed
        return
    }

    Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
}

function Show-RSRSpinner {
    <#
    .SYNOPSIS
        Show spinner while running a script block
    .PARAMETER Message
        Message to display
    .PARAMETER ScriptBlock
        The code to execute
    .EXAMPLE
        Show-RSRSpinner 'Loading...' { Start-Sleep 3 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock]$ScriptBlock
    )

    $spinChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $job = Start-Job -ScriptBlock $ScriptBlock
    $i = 0

    try {
        while ($job.State -eq 'Running') {
            Write-Host "`r$($spinChars[$i % $spinChars.Count]) $Message" -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 100
            $i++
        }

        # Get job result
        $result = Receive-Job -Job $job -Wait

        # Clear spinner and show result
        Write-Host "`r" -NoNewline
        if ($job.State -eq 'Completed') {
            Write-Host "✓ $Message" -ForegroundColor Green
        } else {
            Write-Host "✗ $Message" -ForegroundColor Red
        }

        return $result
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# Export
# =============================================================================

Export-ModuleMember -Function @(
    'Read-RSRConfirm',
    'Read-RSRInput',
    'Read-RSRPassword',
    'Read-RSRSelect',
    'Read-RSRMultiSelect',
    'Show-RSRProgress',
    'Show-RSRSpinner'
)

