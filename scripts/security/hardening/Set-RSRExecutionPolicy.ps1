<#
.SYNOPSIS
    Set-RSRExecutionPolicy - Configure PowerShell Execution Policy interactively or via CLI

.DESCRIPTION
    A user-friendly automation tool to configure PowerShell execution policies on Windows.
    Provides an interactive wizard with educational guidance, security recommendations,
    and support for all policy scopes. Follows Microsoft best practices and industry standards.

    Features:
    - Interactive wizard with step-by-step guidance
    - CLI mode for automation and scripting
    - Security assessment and recommendations
    - Group Policy detection and warnings
    - Backup and rollback support
    - Dry-run mode for testing

.PARAMETER Interactive
    Launch the interactive configuration wizard (default if no parameters)

.PARAMETER Status
    Display current execution policy status across all scopes

.PARAMETER Recommend
    Show security recommendations based on current configuration

.PARAMETER Scope
    Target scope for policy change: Process, CurrentUser, LocalMachine

.PARAMETER Policy
    Execution policy to set: Restricted, AllSigned, RemoteSigned, Unrestricted, Bypass

.PARAMETER Backup
    Save current policy state before making changes

.PARAMETER Restore
    Restore policy from a previous backup file

.PARAMETER BackupPath
    Path to backup file (for -Backup or -Restore)

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER Help
    Show detailed help information

.EXAMPLE
    .\Set-RSRExecutionPolicy.ps1
    Launch interactive wizard

.EXAMPLE
    .\Set-RSRExecutionPolicy.ps1 -Status
    Show current execution policy status

.EXAMPLE
    .\Set-RSRExecutionPolicy.ps1 -Scope CurrentUser -Policy RemoteSigned
    Set RemoteSigned policy for current user

.EXAMPLE
    .\Set-RSRExecutionPolicy.ps1 -Recommend
    Show security recommendations

.EXAMPLE
    .\Set-RSRExecutionPolicy.ps1 -Backup -BackupPath "C:\backup\policy.json"
    Backup current policies to file

.NOTES
    Version:  1.0.0
    Author:   RSR Team
    Platform: Windows (PowerShell 5.1+)
    License:  MIT
#>

#Requires -Version 5.1

# Suppress PSReviewUnusedParameter - parameters are used via $PSCmdlet.ParameterSetName
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Parameters used via ParameterSetName')]
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,

    [Parameter(ParameterSetName = 'Recommend')]
    [switch]$Recommend,

    [Parameter(ParameterSetName = 'Set', Mandatory)]
    [ValidateSet('Process', 'CurrentUser', 'LocalMachine')]
    [string]$Scope,

    [Parameter(ParameterSetName = 'Set', Mandatory)]
    [ValidateSet('Restricted', 'AllSigned', 'RemoteSigned', 'Unrestricted', 'Bypass', 'Undefined')]
    [string]$Policy,

    [Parameter(ParameterSetName = 'Backup')]
    [switch]$Backup,

    [Parameter(ParameterSetName = 'Restore')]
    [switch]$Restore,

    [Parameter(ParameterSetName = 'Backup')]
    [Parameter(ParameterSetName = 'Restore')]
    [string]$BackupPath,

    [switch]$Force,

    [switch]$Help,

    [switch]$Version
)

# =============================================================================
# Configuration
# =============================================================================

$ErrorActionPreference = 'Stop'
$Script:Name = 'Set-RSRExecutionPolicy'
$Script:Version = '1.0.0'
$Script:DefaultBackupDir = Join-Path $env:USERPROFILE '.rsr\policy-backups'

# =============================================================================
# RSR Library Loading
# =============================================================================

$RSRModulePath = Join-Path $PSScriptRoot '../../../lib/powershell/RSR.psd1'
$Script:UseRSRLib = $false

if (Test-Path $RSRModulePath) {
    try {
        Import-Module $RSRModulePath -Force -ErrorAction Stop
        $Script:UseRSRLib = $true
    } catch {
        Write-Warning "RSR library not available, using built-in functions"
    }
}

# =============================================================================
# Fallback UI Functions (when RSR lib not available)
# =============================================================================

function Write-StatusMessage {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Debug')]
        [string]$Level = 'Info'
    )

    if ($Script:UseRSRLib) {
        Write-RSRLog $Message -Level $Level
    } else {
        $colors = @{
            'Info' = 'Cyan'
            'Success' = 'Green'
            'Warning' = 'Yellow'
            'Error' = 'Red'
            'Debug' = 'DarkGray'
        }
        $symbols = @{
            'Info' = '▸'
            'Success' = '✓'
            'Warning' = '⚠'
            'Error' = '✗'
            'Debug' = '○'
        }
        Write-Host "$($symbols[$Level]) " -ForegroundColor $colors[$Level] -NoNewline
        Write-Host $Message
    }
}

function Read-Confirmation {
    param(
        [string]$Question,
        [string]$Default = 'No'
    )

    if ($Script:UseRSRLib) {
        return Read-RSRConfirm -Question $Question -Default $Default
    }

    $hint = if ($Default -eq 'Yes') { '[Y/n]' } else { '[y/N]' }
    Write-Host "? " -ForegroundColor Cyan -NoNewline
    Write-Host "$Question $hint " -NoNewline
    $response = Read-Host

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $Default -eq 'Yes'
    }
    return $response -match '^(y|yes)$'
}

function Read-Selection {
    param(
        [string]$Title,
        [string[]]$Options,
        [int]$Default = 0
    )

    if ($Script:UseRSRLib) {
        return Read-RSRSelect -Title $Title -Options $Options -Default $Default
    }

    Write-Host ""
    Write-Host "? " -ForegroundColor Cyan -NoNewline
    Write-Host $Title
    Write-Host ""

    for ($i = 0; $i -lt $Options.Count; $i++) {
        $prefix = if ($i -eq $Default) { '›' } else { ' ' }
        $color = if ($i -eq $Default) { 'White' } else { 'Gray' }
        Write-Host "  $prefix " -NoNewline -ForegroundColor Cyan
        Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor DarkGray
        Write-Host $Options[$i] -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  Enter number (1-$($Options.Count)) or press Enter for default: " -NoNewline
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

    Write-Host "  Invalid selection, using default" -ForegroundColor Yellow
    return $Options[$Default]
}

# =============================================================================
# Policy Information Database
# =============================================================================

$Script:PolicyInfo = @{
    'Restricted' = @{
        Level = 'High Security'
        Color = 'Green'
        Risk = 1
        Description = 'No scripts can run. PowerShell can only be used interactively.'
        UseCase = 'Maximum security environments, locked-down workstations'
        Drawback = 'Cannot run any PowerShell scripts, including useful automation'
    }
    'AllSigned' = @{
        Level = 'High Security'
        Color = 'Green'
        Risk = 2
        Description = 'Only scripts signed by a trusted publisher can run.'
        UseCase = 'Enterprise environments with code signing infrastructure'
        Drawback = 'Requires certificate infrastructure, all scripts must be signed'
    }
    'RemoteSigned' = @{
        Level = 'Balanced'
        Color = 'Yellow'
        Risk = 3
        Description = 'Local scripts run freely. Downloaded scripts must be signed.'
        UseCase = 'Recommended for most users and developers'
        Drawback = 'Downloaded scripts need signing or unblocking'
    }
    'Unrestricted' = @{
        Level = 'Low Security'
        Color = 'Red'
        Risk = 4
        Description = 'All scripts run. Warns before running downloaded scripts.'
        UseCase = 'Development/testing environments only'
        Drawback = 'Reduced protection against malicious scripts'
    }
    'Bypass' = @{
        Level = 'No Security'
        Color = 'Red'
        Risk = 5
        Description = 'Nothing is blocked, no warnings or prompts.'
        UseCase = 'Automated pipelines, CI/CD systems (Process scope only)'
        Drawback = 'No protection at all - use with extreme caution'
    }
    'Undefined' = @{
        Level = 'Inherited'
        Color = 'Gray'
        Risk = 0
        Description = 'No policy set at this scope. Inherits from broader scope.'
        UseCase = 'Let higher-priority scopes control the policy'
        Drawback = 'Behavior depends on other scope settings'
    }
}

$Script:ScopeInfo = @{
    'MachinePolicy' = @{
        Priority = 1
        Editable = $false
        Description = 'Set by Group Policy for all users on this computer'
        Admin = $true
    }
    'UserPolicy' = @{
        Priority = 2
        Editable = $false
        Description = 'Set by Group Policy for current user'
        Admin = $true
    }
    'Process' = @{
        Priority = 3
        Editable = $true
        Description = 'Affects only the current PowerShell session'
        Admin = $false
    }
    'CurrentUser' = @{
        Priority = 4
        Editable = $true
        Description = 'Affects all sessions for the current user'
        Admin = $false
    }
    'LocalMachine' = @{
        Priority = 5
        Editable = $true
        Description = 'Default for all users on this computer'
        Admin = $true
    }
}

# =============================================================================
# Core Functions
# =============================================================================

function Get-PolicyStatus {
    <#
    .SYNOPSIS
        Get current execution policy across all scopes
    #>
    [CmdletBinding()]
    param()

    $policies = Get-ExecutionPolicy -List

    $result = @()
    foreach ($p in $policies) {
        $scopeName = $p.Scope.ToString()
        $policyName = $p.ExecutionPolicy.ToString()
        $scopeDetails = $Script:ScopeInfo[$scopeName]
        $policyDetails = $Script:PolicyInfo[$policyName]

        $result += [PSCustomObject]@{
            Scope = $scopeName
            Policy = $policyName
            Priority = $scopeDetails.Priority
            Editable = $scopeDetails.Editable
            RequiresAdmin = $scopeDetails.Admin
            Description = $scopeDetails.Description
            SecurityLevel = $policyDetails.Level
            RiskScore = $policyDetails.Risk
            Color = $policyDetails.Color
        }
    }

    # Add effective policy
    $effective = Get-ExecutionPolicy
    $effectiveDetails = $Script:PolicyInfo[$effective.ToString()]

    $result += [PSCustomObject]@{
        Scope = 'Effective'
        Policy = $effective.ToString()
        Priority = 0
        Editable = $false
        RequiresAdmin = $false
        Description = 'The policy that actually applies to this session'
        SecurityLevel = $effectiveDetails.Level
        RiskScore = $effectiveDetails.Risk
        Color = 'Cyan'
    }

    return $result
}

function Show-PolicyStatus {
    <#
    .SYNOPSIS
        Display formatted policy status
    #>
    [CmdletBinding()]
    param()

    $policies = Get-PolicyStatus

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          PowerShell Execution Policy Status                      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Check for GPO control
    $gpoControlled = $false
    foreach ($p in $policies) {
        if ($p.Scope -in 'MachinePolicy', 'UserPolicy' -and $p.Policy -ne 'Undefined') {
            $gpoControlled = $true
            break
        }
    }

    if ($gpoControlled) {
        Write-Host "  ⚠ " -ForegroundColor Yellow -NoNewline
        Write-Host "Group Policy is controlling execution policy on this system" -ForegroundColor Yellow
        Write-Host "    Contact your IT administrator to modify GPO-controlled settings" -ForegroundColor DarkGray
        Write-Host ""
    }

    # Display table header
    Write-Host "  ┌────────────────┬─────────────────┬────────────────┬───────────┐" -ForegroundColor DarkGray
    Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Scope          " -ForegroundColor White -NoNewline
    Write-Host "│ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Policy          " -ForegroundColor White -NoNewline
    Write-Host "│ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Security       " -ForegroundColor White -NoNewline
    Write-Host "│ " -ForegroundColor DarkGray -NoNewline
    Write-Host "Editable  " -ForegroundColor White -NoNewline
    Write-Host "│" -ForegroundColor DarkGray
    Write-Host "  ├────────────────┼─────────────────┼────────────────┼───────────┤" -ForegroundColor DarkGray

    foreach ($p in $policies | Sort-Object Priority) {
        $scopeStr = $p.Scope.PadRight(14)
        $policyStr = $p.Policy.PadRight(15)
        $secStr = $p.SecurityLevel.PadRight(14)
        $editStr = if ($p.Scope -eq 'Effective') { 'N/A' } elseif ($p.Editable) { 'Yes' } else { 'GPO' }
        $editStr = $editStr.PadRight(9)

        $policyColor = switch ($p.Color) {
            'Green' { 'Green' }
            'Yellow' { 'Yellow' }
            'Red' { 'Red' }
            'Cyan' { 'Cyan' }
            default { 'Gray' }
        }

        $editColor = if ($p.Editable) { 'Green' } elseif ($p.Scope -eq 'Effective') { 'DarkGray' } else { 'Yellow' }

        Write-Host "  │ " -ForegroundColor DarkGray -NoNewline
        if ($p.Scope -eq 'Effective') {
            Write-Host $scopeStr -ForegroundColor Cyan -NoNewline
        } else {
            Write-Host $scopeStr -ForegroundColor White -NoNewline
        }
        Write-Host "│ " -ForegroundColor DarkGray -NoNewline
        Write-Host $policyStr -ForegroundColor $policyColor -NoNewline
        Write-Host "│ " -ForegroundColor DarkGray -NoNewline
        Write-Host $secStr -ForegroundColor $policyColor -NoNewline
        Write-Host "│ " -ForegroundColor DarkGray -NoNewline
        Write-Host $editStr -ForegroundColor $editColor -NoNewline
        Write-Host "│" -ForegroundColor DarkGray
    }

    Write-Host "  └────────────────┴─────────────────┴────────────────┴───────────┘" -ForegroundColor DarkGray
    Write-Host ""

    # Show legend
    Write-Host "  Legend: " -ForegroundColor DarkGray -NoNewline
    Write-Host "●" -ForegroundColor Green -NoNewline
    Write-Host " Secure  " -ForegroundColor DarkGray -NoNewline
    Write-Host "●" -ForegroundColor Yellow -NoNewline
    Write-Host " Balanced  " -ForegroundColor DarkGray -NoNewline
    Write-Host "●" -ForegroundColor Red -NoNewline
    Write-Host " Risky  " -ForegroundColor DarkGray -NoNewline
    Write-Host "GPO" -ForegroundColor Yellow -NoNewline
    Write-Host " = Group Policy controlled" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-Recommendation {
    <#
    .SYNOPSIS
        Display security recommendations based on current state
    #>
    [CmdletBinding()]
    param()

    $policies = Get-PolicyStatus
    $effective = ($policies | Where-Object { $_.Scope -eq 'Effective' }).Policy
    $currentUser = ($policies | Where-Object { $_.Scope -eq 'CurrentUser' }).Policy
    $localMachine = ($policies | Where-Object { $_.Scope -eq 'LocalMachine' }).Policy

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║          Security Recommendations                                ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    $recommendations = @()

    # Check effective policy
    switch ($effective) {
        'Bypass' {
            $recommendations += @{
                Level = 'Critical'
                Title = 'Bypass policy detected'
                Detail = 'Your system has no script execution restrictions. This is a security risk.'
                Action = 'Set CurrentUser scope to RemoteSigned for balanced security.'
            }
        }
        'Unrestricted' {
            $recommendations += @{
                Level = 'Warning'
                Title = 'Unrestricted policy detected'
                Detail = 'Scripts run with minimal restrictions. Consider tightening security.'
                Action = 'Use RemoteSigned for better protection while maintaining functionality.'
            }
        }
        'Restricted' {
            $recommendations += @{
                Level = 'Info'
                Title = 'Highly restrictive policy'
                Detail = 'No scripts can run. This may prevent useful automation.'
                Action = 'Consider RemoteSigned if you need to run PowerShell scripts.'
            }
        }
        'RemoteSigned' {
            $recommendations += @{
                Level = 'Success'
                Title = 'Good security balance'
                Detail = 'RemoteSigned provides good protection while allowing local scripts.'
                Action = 'No changes recommended for most users.'
            }
        }
        'AllSigned' {
            $recommendations += @{
                Level = 'Success'
                Title = 'High security configuration'
                Detail = 'Only signed scripts can run. Excellent for enterprise environments.'
                Action = 'Ensure you have code signing infrastructure in place.'
            }
        }
    }

    # Check for undefined policies
    if ($currentUser -eq 'Undefined' -and $localMachine -eq 'Undefined') {
        $recommendations += @{
            Level = 'Info'
            Title = 'No explicit policy set'
            Detail = 'Relying on system defaults. Consider setting an explicit policy.'
            Action = 'Set CurrentUser to RemoteSigned for predictable behavior.'
        }
    }

    # Display recommendations
    foreach ($rec in $recommendations) {
        $icon = switch ($rec.Level) {
            'Critical' { '🔴' }
            'Warning' { '🟡' }
            'Info' { '🔵' }
            'Success' { '🟢' }
        }
        $color = switch ($rec.Level) {
            'Critical' { 'Red' }
            'Warning' { 'Yellow' }
            'Info' { 'Cyan' }
            'Success' { 'Green' }
        }

        Write-Host "  $icon " -NoNewline
        Write-Host $rec.Title -ForegroundColor $color
        Write-Host "     $($rec.Detail)" -ForegroundColor Gray
        Write-Host "     → " -ForegroundColor DarkGray -NoNewline
        Write-Host $rec.Action -ForegroundColor White
        Write-Host ""
    }

    # General best practices
    Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  📋 Best Practices:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "     • " -ForegroundColor DarkGray -NoNewline
    Write-Host "Use " -NoNewline
    Write-Host "RemoteSigned" -ForegroundColor Yellow -NoNewline
    Write-Host " for personal computers and development"
    Write-Host "     • " -ForegroundColor DarkGray -NoNewline
    Write-Host "Use " -NoNewline
    Write-Host "AllSigned" -ForegroundColor Green -NoNewline
    Write-Host " in enterprise environments with code signing"
    Write-Host "     • " -ForegroundColor DarkGray -NoNewline
    Write-Host "Avoid " -NoNewline
    Write-Host "Bypass" -ForegroundColor Red -NoNewline
    Write-Host " and " -NoNewline
    Write-Host "Unrestricted" -ForegroundColor Red -NoNewline
    Write-Host " for persistent scopes"
    Write-Host "     • " -ForegroundColor DarkGray -NoNewline
    Write-Host "Use " -NoNewline
    Write-Host "Process" -ForegroundColor Cyan -NoNewline
    Write-Host " scope for temporary changes in automation"
    Write-Host ""
}

function Test-AdminElevation {
    <#
    .SYNOPSIS
        Check if running with administrator privileges
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-PolicyBackup {
    <#
    .SYNOPSIS
        Backup current policy configuration to file
    #>
    [CmdletBinding()]
    param(
        [string]$Path
    )

    if (-not $Path) {
        if (-not (Test-Path $Script:DefaultBackupDir)) {
            New-Item -ItemType Directory -Path $Script:DefaultBackupDir -Force | Out-Null
        }
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $Path = Join-Path $Script:DefaultBackupDir "policy_backup_$timestamp.json"
    }

    $policies = Get-ExecutionPolicy -List | ForEach-Object {
        @{
            Scope = $_.Scope.ToString()
            Policy = $_.ExecutionPolicy.ToString()
        }
    }

    $backup = @{
        Timestamp = (Get-Date).ToString('o')
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Policies = $policies
    }

    $backup | ConvertTo-Json -Depth 3 | Set-Content -Path $Path -Encoding UTF8

    Write-StatusMessage "Policy backup saved to: $Path" -Level Success
    return $Path
}

function Invoke-PolicyRestore {
    <#
    .SYNOPSIS
        Restore policy configuration from backup file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-StatusMessage "Backup file not found: $Path" -Level Error
        return $false
    }

    $backup = Get-Content -Path $Path -Raw | ConvertFrom-Json

    Write-Host ""
    Write-Host "  Backup Information:" -ForegroundColor Cyan
    Write-Host "    Created: $($backup.Timestamp)" -ForegroundColor Gray
    Write-Host "    Computer: $($backup.ComputerName)" -ForegroundColor Gray
    Write-Host "    User: $($backup.UserName)" -ForegroundColor Gray
    Write-Host ""

    $editableScopes = @('Process', 'CurrentUser', 'LocalMachine')

    foreach ($p in $backup.Policies) {
        if ($p.Scope -in $editableScopes -and $p.Policy -ne 'Undefined') {
            $needsAdmin = $p.Scope -eq 'LocalMachine'

            if ($needsAdmin -and -not (Test-AdminElevation)) {
                Write-StatusMessage "Skipping $($p.Scope) - requires administrator privileges" -Level Warning
                continue
            }

            if ($Force -or (Read-Confirmation "Restore $($p.Scope) to $($p.Policy)?")) {
                try {
                    Set-ExecutionPolicy -ExecutionPolicy $p.Policy -Scope $p.Scope -Force
                    Write-StatusMessage "Restored $($p.Scope) to $($p.Policy)" -Level Success
                } catch {
                    Write-StatusMessage "Failed to restore $($p.Scope): $_" -Level Error
                }
            }
        }
    }

    return $true
}

function Set-PolicyWithValidation {
    <#
    .SYNOPSIS
        Set execution policy with validation and safety checks
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$TargetScope,

        [Parameter(Mandatory)]
        [string]$TargetPolicy,

        [switch]$SkipConfirmation
    )

    # Check for admin requirements
    if ($TargetScope -eq 'LocalMachine' -and -not (Test-AdminElevation)) {
        Write-StatusMessage "LocalMachine scope requires administrator privileges" -Level Error
        Write-Host ""
        Write-Host "  To elevate, run:" -ForegroundColor Gray
        Write-Host "    Start-Process pwsh -Verb RunAs -ArgumentList '-File', '$($MyInvocation.ScriptName)'" -ForegroundColor Yellow
        Write-Host ""
        return $false
    }

    # Get current policy for this scope
    $current = (Get-ExecutionPolicy -Scope $TargetScope).ToString()

    if ($current -eq $TargetPolicy) {
        Write-StatusMessage "$TargetScope is already set to $TargetPolicy" -Level Info
        return $true
    }

    # Show policy change details
    $policyInfo = $Script:PolicyInfo[$TargetPolicy]

    Write-Host ""
    Write-Host "  Policy Change Summary:" -ForegroundColor Cyan
    Write-Host "  ───────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host "    Scope:        $TargetScope" -ForegroundColor White
    Write-Host "    Current:      $current" -ForegroundColor Yellow
    Write-Host "    New:          $TargetPolicy" -ForegroundColor Green
    Write-Host "    Security:     $($policyInfo.Level)" -ForegroundColor $policyInfo.Color
    Write-Host ""
    Write-Host "    $($policyInfo.Description)" -ForegroundColor Gray
    Write-Host ""

    # Warn about risky policies
    if ($policyInfo.Risk -ge 4) {
        Write-Host "  ⚠ " -ForegroundColor Yellow -NoNewline
        Write-Host "Warning: " -ForegroundColor Yellow -NoNewline
        Write-Host $policyInfo.Drawback -ForegroundColor Yellow
        Write-Host ""
    }

    # Confirm unless skipped
    if (-not $SkipConfirmation -and -not $Force) {
        if (-not (Read-Confirmation "Apply this change?" -Default 'No')) {
            Write-StatusMessage "Operation cancelled" -Level Info
            return $false
        }
    }

    # Apply the change
    if ($PSCmdlet.ShouldProcess("$TargetScope execution policy", "Set to $TargetPolicy")) {
        try {
            Set-ExecutionPolicy -ExecutionPolicy $TargetPolicy -Scope $TargetScope -Force
            Write-StatusMessage "Successfully set $TargetScope to $TargetPolicy" -Level Success
            return $true
        } catch {
            Write-StatusMessage "Failed to set policy: $_" -Level Error
            return $false
        }
    }

    return $true
}

# =============================================================================
# Interactive Wizard
# =============================================================================

function Start-InteractiveWizard {
    <#
    .SYNOPSIS
        Launch the interactive policy configuration wizard
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Wrapper function that delegates state changes to Set-PolicyWithValidation which supports ShouldProcess')]
    [CmdletBinding()]
    param()

    Clear-Host

    # Header
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                                  ║" -ForegroundColor Cyan
    Write-Host "  ║   " -ForegroundColor Cyan -NoNewline
    Write-Host "⚡ PowerShell Execution Policy Configuration Wizard" -ForegroundColor White -NoNewline
    Write-Host "         ║" -ForegroundColor Cyan
    Write-Host "  ║                                                                  ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  This wizard helps you configure PowerShell's execution policy" -ForegroundColor Gray
    Write-Host "  to balance security and functionality for your needs." -ForegroundColor Gray
    Write-Host ""

    # Show current status
    Show-PolicyStatus

    # Main menu
    $menuOptions = @(
        'View detailed recommendations',
        'Configure CurrentUser policy (recommended)',
        'Configure LocalMachine policy (requires admin)',
        'Configure Process policy (temporary)',
        'Backup current configuration',
        'Restore from backup',
        'Exit'
    )

    while ($true) {
        $choice = Read-Selection -Title "What would you like to do?" -Options $menuOptions -Default 1

        switch ($choice) {
            'View detailed recommendations' {
                Show-Recommendation
                Write-Host "  Press Enter to continue..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            'Configure CurrentUser policy (recommended)' {
                Invoke-ScopeConfiguration -TargetScope 'CurrentUser'
            }
            'Configure LocalMachine policy (requires admin)' {
                if (-not (Test-AdminElevation)) {
                    Write-Host ""
                    Write-StatusMessage "This option requires administrator privileges" -Level Warning
                    Write-Host ""
                    Write-Host "  Options:" -ForegroundColor Gray
                    Write-Host "    1. Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor White
                    Write-Host "    2. Run: " -ForegroundColor Gray -NoNewline
                    Write-Host "Start-Process pwsh -Verb RunAs" -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "  Press Enter to continue..." -ForegroundColor DarkGray
                    Read-Host | Out-Null
                } else {
                    Invoke-ScopeConfiguration -TargetScope 'LocalMachine'
                }
            }
            'Configure Process policy (temporary)' {
                Invoke-ScopeConfiguration -TargetScope 'Process'
            }
            'Backup current configuration' {
                Write-Host ""
                Invoke-PolicyBackup
                Write-Host ""
                Write-Host "  Press Enter to continue..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            'Restore from backup' {
                $backupDir = $Script:DefaultBackupDir
                if (Test-Path $backupDir) {
                    $backups = Get-ChildItem -Path $backupDir -Filter '*.json' | Sort-Object LastWriteTime -Descending
                    if ($backups.Count -gt 0) {
                        $backupNames = $backups | ForEach-Object { "$($_.BaseName) ($($_.LastWriteTime.ToString('g')))" }
                        $selected = Read-Selection -Title "Select backup to restore:" -Options $backupNames
                        $index = [Array]::IndexOf($backupNames, $selected)
                        if ($index -ge 0) {
                            Invoke-PolicyRestore -Path $backups[$index].FullName
                        }
                    } else {
                        Write-StatusMessage "No backups found in $backupDir" -Level Warning
                    }
                } else {
                    Write-StatusMessage "No backup directory found. Create a backup first." -Level Warning
                }
                Write-Host ""
                Write-Host "  Press Enter to continue..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            'Exit' {
                Write-Host ""
                Write-StatusMessage "Goodbye!" -Level Info
                return
            }
        }

        # Refresh status display
        Clear-Host
        Write-Host ""
        Show-PolicyStatus
    }
}

function Invoke-ScopeConfiguration {
    <#
    .SYNOPSIS
        Configure policy for a specific scope with educational guidance
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TargetScope
    )

    $scopeInfo = $Script:ScopeInfo[$TargetScope]

    Write-Host ""
    Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  Configuring: $TargetScope" -ForegroundColor Cyan
    Write-Host "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  $($scopeInfo.Description)" -ForegroundColor Gray
    Write-Host ""

    # Policy options with descriptions
    $policyOptions = @(
        "RemoteSigned  - Local scripts run, downloaded must be signed (RECOMMENDED)",
        "AllSigned     - All scripts must be signed by trusted publisher",
        "Restricted    - No scripts can run (maximum security)",
        "Unrestricted  - All scripts run with warnings",
        "Bypass        - No restrictions (use with caution)",
        "Undefined     - Remove policy for this scope (inherit from other scopes)",
        "Cancel        - Return to main menu"
    )

    # Find recommended default based on scope
    $defaultIndex = 0  # RemoteSigned

    $selected = Read-Selection -Title "Select execution policy:" -Options $policyOptions -Default $defaultIndex

    if ($selected -match '^Cancel') {
        return
    }

    # Extract policy name from selection
    $selectedPolicy = ($selected -split '\s+-')[0].Trim()

    # Offer backup before change
    if (Read-Confirmation "Create backup before applying change?" -Default 'Yes') {
        Invoke-PolicyBackup | Out-Null
    }

    # Apply the change
    Set-PolicyWithValidation -TargetScope $TargetScope -TargetPolicy $selectedPolicy

    Write-Host ""
    Write-Host "  Press Enter to continue..." -ForegroundColor DarkGray
    Read-Host | Out-Null
}

# =============================================================================
# Help Display
# =============================================================================

function Show-DetailedHelp {
    Write-Host @"

  PowerShell Execution Policy Configuration Tool
  ═══════════════════════════════════════════════

  USAGE:
    .\Set-RSRExecutionPolicy.ps1 [OPTIONS]

  MODES:
    -Interactive     Launch interactive wizard (default)
    -Status          Show current policy status
    -Recommend       Display security recommendations

  CONFIGURATION:
    -Scope <scope>   Target: Process, CurrentUser, LocalMachine
    -Policy <policy> Policy: Restricted, AllSigned, RemoteSigned,
                            Unrestricted, Bypass, Undefined

  BACKUP/RESTORE:
    -Backup          Save current configuration
    -Restore         Restore from backup file
    -BackupPath      Custom backup file path

  OPTIONS:
    -Force           Skip confirmation prompts
    -WhatIf          Preview changes without applying
    -Help            Show this help message
    -Version         Show version information

  EXAMPLES:
    # Interactive wizard
    .\Set-RSRExecutionPolicy.ps1

    # Check current status
    .\Set-RSRExecutionPolicy.ps1 -Status

    # Set policy for current user
    .\Set-RSRExecutionPolicy.ps1 -Scope CurrentUser -Policy RemoteSigned

    # Backup and set policy
    .\Set-RSRExecutionPolicy.ps1 -Backup
    .\Set-RSRExecutionPolicy.ps1 -Scope CurrentUser -Policy AllSigned

  POLICY LEVELS (least to most permissive):
    Restricted    → No scripts run
    AllSigned     → Only signed scripts run
    RemoteSigned  → Local scripts + signed remote scripts (RECOMMENDED)
    Unrestricted  → All scripts with warnings
    Bypass        → All scripts without restrictions

  SCOPES (highest to lowest priority):
    MachinePolicy → Group Policy (computer) - not editable
    UserPolicy    → Group Policy (user) - not editable
    Process       → Current session only
    CurrentUser   → All sessions for this user
    LocalMachine  → Default for all users (requires admin)

"@
}

# =============================================================================
# Main Entry Point
# =============================================================================

function Main {
    # Handle help and version
    if ($Help) {
        Show-DetailedHelp
        return
    }

    if ($Version) {
        Write-Output "$($Script:Name) v$($Script:Version)"
        return
    }

    # Route to appropriate mode
    switch ($PSCmdlet.ParameterSetName) {
        'Status' {
            Show-PolicyStatus
        }
        'Recommend' {
            Show-PolicyStatus
            Show-Recommendation
        }
        'Set' {
            Set-PolicyWithValidation -TargetScope $Scope -TargetPolicy $Policy
        }
        'Backup' {
            Invoke-PolicyBackup -Path $BackupPath
        }
        'Restore' {
            if (-not $BackupPath) {
                # List available backups
                $backupDir = $Script:DefaultBackupDir
                if (Test-Path $backupDir) {
                    $backups = Get-ChildItem -Path $backupDir -Filter '*.json' | Sort-Object LastWriteTime -Descending
                    if ($backups.Count -gt 0) {
                        Write-Host ""
                        Write-Host "Available backups:" -ForegroundColor Cyan
                        foreach ($b in $backups) {
                            Write-Host "  - $($b.FullName)" -ForegroundColor Gray
                        }
                        Write-Host ""
                        Write-StatusMessage "Use -BackupPath to specify which backup to restore" -Level Info
                    } else {
                        Write-StatusMessage "No backups found" -Level Warning
                    }
                } else {
                    Write-StatusMessage "No backup directory found" -Level Warning
                }
            } else {
                Invoke-PolicyRestore -Path $BackupPath
            }
        }
        default {
            # Interactive mode (default)
            Start-InteractiveWizard
        }
    }
}

# Run
Main

