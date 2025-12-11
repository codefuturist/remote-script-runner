<#
.SYNOPSIS
    PowerShell wrapper for executing remote bash scripts with arguments
    
.DESCRIPTION
    This script provides a PowerShell-friendly interface for running remote bash scripts
    from the remote-script-runner repository. It supports both system health checks
    and server setup operations.
    
.PARAMETER ScriptName
    The name of the script to run: 'health-check' or 'server-setup'
    
.PARAMETER Arguments
    Arguments to pass to the remote script
    
.PARAMETER CustomUri
    Optional custom URI to a script (overrides ScriptName)
    
.EXAMPLE
    # Run health check for CPU and memory
    .\Invoke-RemoteScript.ps1 -ScriptName health-check -Arguments '-v', '-s', 'cpu', 'memory'
    
.EXAMPLE
    # Run server setup in dry-run mode
    .\Invoke-RemoteScript.ps1 -ScriptName server-setup -Arguments '-d', '-u', 'admin', '-p', 'production', 'nginx', 'docker'
    
.EXAMPLE
    # Use custom script URI
    .\Invoke-RemoteScript.ps1 -CustomUri 'https://example.com/my-script.sh' -Arguments '-a'
    
.NOTES
    Requires: bash (native on macOS/Linux, WSL/Git Bash on Windows)
    Author: Remote Script Runner
    Version: 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('health-check', 'server-setup')]
    [string]$ScriptName,
    
    [Parameter(Mandatory=$false)]
    [string[]]$Arguments = @(),
    
    [Parameter(Mandatory=$false)]
    [string]$CustomUri
)

# Base repository URL
$baseUrl = "https://codefuturist.github.io/remote-script-runner"

# Script mappings
$scriptMap = @{
    'health-check' = "$baseUrl/system-health-check.sh"
    'server-setup' = "$baseUrl/server-setup.sh"
}

# Determine script URI
if ($CustomUri) {
    $scriptUri = $CustomUri
    Write-Host "Using custom script: $scriptUri" -ForegroundColor Cyan
} elseif ($ScriptName) {
    $scriptUri = $scriptMap[$ScriptName]
    Write-Host "Running $ScriptName script..." -ForegroundColor Cyan
} else {
    Write-Error "Either -ScriptName or -CustomUri must be specified"
    exit 1
}

# Check for bash availability
function Test-BashAvailable {
    $bashCommands = @('bash', 'wsl bash', 'C:\Program Files\Git\bin\bash.exe')
    
    foreach ($bash in $bashCommands) {
        try {
            $null = & ([scriptblock]::Create("$bash --version")) 2>$null
            return $bash
        } catch {
            continue
        }
    }
    
    return $null
}

$bashCommand = Test-BashAvailable

if (-not $bashCommand) {
    Write-Error @"
Bash is not available on this system.

For Windows users:
- Install WSL (Windows Subsystem for Linux): https://docs.microsoft.com/en-us/windows/wsl/install
- Or install Git for Windows: https://git-scm.com/download/win

For macOS/Linux users:
- Bash should be available by default
"@
    exit 1
}

Write-Host "Using bash: $bashCommand" -ForegroundColor Green

# Download and execute script
try {
    Write-Host "Downloading script from: $scriptUri" -ForegroundColor Yellow
    
    $scriptContent = Invoke-RestMethod -Uri $scriptUri -ErrorAction Stop
    
    # Build argument string
    $argString = if ($Arguments.Count -gt 0) {
        " -- " + ($Arguments -join ' ')
    } else {
        ""
    }
    
    Write-Host "Executing with arguments: $argString" -ForegroundColor Yellow
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    
    # Execute the script
    if ($Arguments.Count -gt 0) {
        $scriptContent | & $bashCommand -s -- @Arguments
    } else {
        $scriptContent | & $bashCommand -s
    }
    
    $exitCode = $LASTEXITCODE
    
    Write-Host ("-" * 60) -ForegroundColor DarkGray
    
    if ($exitCode -eq 0) {
        Write-Host "Script completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Script failed with exit code: $exitCode" -ForegroundColor Red
    }
    
    exit $exitCode
    
} catch {
    Write-Error "Failed to download or execute script: $_"
    exit 1
}

<#
.ADDITIONAL EXAMPLES

# Health Check Examples
# --------------------

# Run all health checks
.\Invoke-RemoteScript.ps1 -ScriptName health-check -Arguments '-a'

# Verbose CPU and memory check
.\Invoke-RemoteScript.ps1 -ScriptName health-check -Arguments '-v', '-s', 'cpu', '-s', 'memory'

# Check with timeout and logging
.\Invoke-RemoteScript.ps1 -ScriptName health-check -Arguments '-a', '-t', '30', '-l', '/tmp/health.log'

# JSON format output
.\Invoke-RemoteScript.ps1 -ScriptName health-check -Arguments '-f', 'json', '-s', 'uptime'


# Server Setup Examples
# --------------------

# Dry run for production setup
.\Invoke-RemoteScript.ps1 -ScriptName server-setup -Arguments '-d', '-u', 'admin', '-p', 'production', '-i', 'nginx', '-i', 'docker'

# Development setup with verbose output
.\Invoke-RemoteScript.ps1 -ScriptName server-setup -Arguments '-v', '-u', 'developer', '-p', 'development', 'nodejs', 'python3', 'git'

# Install specific packages
.\Invoke-RemoteScript.ps1 -ScriptName server-setup -Arguments '-u', 'sysadmin', '-i', 'nginx', '-i', 'fail2ban', '-i', 'htop'


# Advanced Usage
# -------------

# Use with pipeline
'health-check' | ForEach-Object { .\Invoke-RemoteScript.ps1 -ScriptName $_ -Arguments '-s', 'cpu' }

# Store results
$result = .\Invoke-RemoteScript.ps1 -ScriptName health-check -Arguments '-f', 'json', '-s', 'uptime' | ConvertFrom-Json

# Schedule with Task Scheduler (Windows)
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-File "C:\Scripts\Invoke-RemoteScript.ps1" -ScriptName health-check -Arguments "-a"'
$trigger = New-ScheduledTaskTrigger -Daily -At 9am
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "DailyHealthCheck"
#>
