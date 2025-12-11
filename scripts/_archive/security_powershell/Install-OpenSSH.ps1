<#
.SYNOPSIS
    Automated OpenSSH Installation and Configuration Script for Windows

.DESCRIPTION
    This script provides a user-friendly, adaptive installation of OpenSSH Client and Server
    on Windows systems. It follows Microsoft's official documentation and industry best practices.

.NOTES
    Version:        2.0
    Author:         System Administrator
    Creation Date:  2025-12-09
    Purpose:        Production-ready OpenSSH deployment for Windows environments

.EXAMPLE
    .\Install-OpenSSH.ps1

.EXAMPLE
    .\Install-OpenSSH.ps1 -ClientOnly

.EXAMPLE
    .\Install-OpenSSH.ps1 -ServerOnly -AutoStart
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$ClientOnly,

    [Parameter(Mandatory=$false)]
    [switch]$ServerOnly,

    [Parameter(Mandatory=$false)]
    [switch]$AutoStart,

    [Parameter(Mandatory=$false)]
    [switch]$SkipFirewall,

    [Parameter(Mandatory=$false)]
    [string]$LogPath = "$env:TEMP\OpenSSH_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

#region Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes messages to both console and log file with timestamp
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Info','Warning','Error','Success')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Console output with colors
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Cyan }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }

    # File output
    try {
        Add-Content -Path $LogPath -Value $logMessage -ErrorAction Stop
    } catch {
        Write-Warning "Failed to write to log file: $_"
    }
}

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates system requirements for OpenSSH installation
    #>

    Write-Log "Checking system prerequisites..." -Level Info
    $prereqMet = $true

    # Check Administrator privileges
    Write-Log "Checking administrator privileges..."
    $isAdmin = (New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent())
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Log "Script must be run as Administrator!" -Level Error
        Write-Log "Please right-click PowerShell and select 'Run as Administrator'" -Level Warning
        return $false
    }
    Write-Log "Administrator privileges confirmed" -Level Success

    # Check PowerShell version (5.1 minimum)
    Write-Log "Checking PowerShell version..."
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -lt 5 -or ($psVersion.Major -eq 5 -and $psVersion.Minor -lt 1)) {
        Write-Log "PowerShell 5.1 or later is required. Current version: $($psVersion.ToString())" -Level Error
        Write-Log "Please update PowerShell from: https://aka.ms/powershell" -Level Info
        return $false
    }
    Write-Log "PowerShell version $($psVersion.ToString()) meets requirements" -Level Success

    # Check Windows version
    Write-Log "Checking Windows version..."
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $build = [int]$os.BuildNumber

        # Store OS info for later use
        $script:OSInfo = @{
            Version = $os.Version
            Build = $build
            Caption = $os.Caption
            IsServer = $os.Caption -like "*Server*"
            IsServer2025 = $os.Caption -like "*Server 2025*" -or $build -ge 26100
        }

        # Minimum: Windows 10 1809 (build 17763) or Server 2019
        $minBuild = 17763
        if ($build -lt $minBuild) {
            Write-Log "Windows 10 1809/Server 2019 or later required. Current build: $build" -Level Error
            return $false
        }

        Write-Log "Windows version: $($os.Caption) (Build $build)" -Level Success

        if ($script:OSInfo.IsServer2025) {
            Write-Log "Windows Server 2025 detected - OpenSSH is installed by default" -Level Info
        }

    } catch {
        Write-Log "Failed to determine Windows version: $_" -Level Error
        return $false
    }

    # Check network connectivity (optional, for downloading if needed)
    Write-Log "Checking network connectivity..."
    try {
        $testConnection = Test-NetConnection -ComputerName "www.microsoft.com" -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        if ($testConnection) {
            Write-Log "Network connectivity confirmed" -Level Success
        } else {
            Write-Log "Limited network connectivity detected - installation will proceed with local sources" -Level Warning
        }
    } catch {
        Write-Log "Could not verify network connectivity - proceeding anyway" -Level Warning
    }

    return $true
}

function Get-OpenSSHStatus {
    <#
    .SYNOPSIS
        Checks current OpenSSH installation status
    #>

    Write-Log "Checking current OpenSSH installation status..." -Level Info

    $status = @{
        ClientInstalled = $false
        ServerInstalled = $false
        ClientVersion = $null
        ServerVersion = $null
        SshdRunning = $false
        SshdStartType = $null
    }

    try {
        # Check Windows Capabilities
        $capabilities = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $Name -like 'OpenSSH*' }

        foreach ($cap in $capabilities) {
            if ($cap.Name -like '*Client*') {
                $status.ClientInstalled = ($cap.State -eq 'Installed')
                if ($status.ClientInstalled) {
                    Write-Log "OpenSSH Client is already installed" -Level Info
                    # Try to get version
                    try {
                        $sshPath = "$env:SystemRoot\System32\OpenSSH\ssh.exe"
                        if (Test-Path $sshPath) {
                            $versionInfo = & $sshPath -V 2>&1
                            $status.ClientVersion = $versionInfo
                        }
                    } catch {}
                }
            }
            elseif ($cap.Name -like '*Server*') {
                $status.ServerInstalled = ($cap.State -eq 'Installed')
                if ($status.ServerInstalled) {
                    Write-Log "OpenSSH Server is already installed" -Level Info
                    # Check service status
                    try {
                        $service = Get-Service -Name sshd -ErrorAction Stop
                        $status.SshdRunning = ($service.Status -eq 'Running')
                        $status.SshdStartType = $service.StartType

                        if ($status.SshdRunning) {
                            Write-Log "SSH Server service (sshd) is running" -Level Info
                        } else {
                            Write-Log "SSH Server service (sshd) is installed but not running" -Level Warning
                        }
                    } catch {
                        Write-Log "SSH Server service (sshd) is not configured" -Level Warning
                    }
                }
            }
        }
    } catch {
        Write-Log "Error checking OpenSSH status: $_" -Level Warning
        # Fallback to checking services directly
        try {
            if (Get-Service -Name ssh-agent -ErrorAction SilentlyContinue) {
                $status.ClientInstalled = $true
            }
            if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
                $status.ServerInstalled = $true
            }
        } catch {}
    }

    return $status
}

function Install-OpenSSHClient {
    <#
    .SYNOPSIS
        Installs OpenSSH Client component
    #>

    Write-Log "Installing OpenSSH Client..." -Level Info

    try {
        # Progress indicator
        Write-Progress -Activity "Installing OpenSSH Client" -Status "Please wait..." -PercentComplete 50

        $result = Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 -ErrorAction Stop

        Write-Progress -Activity "Installing OpenSSH Client" -Completed

        if ($result.RestartNeeded) {
            Write-Log "OpenSSH Client installed successfully - Restart may be required" -Level Warning
            $script:RestartRequired = $true
        } else {
            Write-Log "OpenSSH Client installed successfully" -Level Success
        }

        # Verify installation
        Start-Sleep -Seconds 2
        $sshPath = "$env:SystemRoot\System32\OpenSSH\ssh.exe"
        if (Test-Path $sshPath) {
            Write-Log "SSH client executable verified at: $sshPath" -Level Success
        }

        return $true
    } catch {
        Write-Log "Failed to install OpenSSH Client: $_" -Level Error

        # Provide troubleshooting tips
        Write-Log "Troubleshooting tips:" -Level Info
        Write-Log "  1. Ensure Windows Update service is running" -Level Info
        Write-Log "  2. Check if your organization blocks Windows Features" -Level Info
        Write-Log "  3. Try running: DISM /Online /Add-Capability /CapabilityName:OpenSSH.Client~~~~0.0.1.0" -Level Info

        return $false
    }
}

function Install-OpenSSHServer {
    <#
    .SYNOPSIS
        Installs and configures OpenSSH Server component
    #>

    Write-Log "Installing OpenSSH Server..." -Level Info

    try {
        # For Windows Server 2025, just need to start the service
        if ($script:OSInfo.IsServer2025) {
            Write-Log "Windows Server 2025 detected - OpenSSH Server is pre-installed" -Level Info
            return Configure-SSHDService
        }

        # Progress indicator
        Write-Progress -Activity "Installing OpenSSH Server" -Status "Please wait..." -PercentComplete 50

        $result = Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop

        Write-Progress -Activity "Installing OpenSSH Server" -Completed

        if ($result.RestartNeeded) {
            Write-Log "OpenSSH Server installed successfully - Restart may be required" -Level Warning
            $script:RestartRequired = $true
        } else {
            Write-Log "OpenSSH Server installed successfully" -Level Success
        }

        # Configure the service
        return Configure-SSHDService

    } catch {
        Write-Log "Failed to install OpenSSH Server: $_" -Level Error

        Write-Log "Troubleshooting tips:" -Level Info
        Write-Log "  1. Ensure Windows Update service is running" -Level Info
        Write-Log "  2. Check if port 22 is not already in use: netstat -an | findstr :22" -Level Info
        Write-Log "  3. Try running: DISM /Online /Add-Capability /CapabilityName:OpenSSH.Server~~~~0.0.1.0" -Level Info

        return $false
    }
}

function Configure-SSHDService {
    <#
    .SYNOPSIS
        Configures SSH Server service and firewall rules
    #>

    Write-Log "Configuring SSH Server service..." -Level Info

    $configSuccess = $true

    # Wait for service to be available
    $retries = 10
    $serviceFound = $false

    while ($retries -gt 0 -and -not $serviceFound) {
        try {
            $service = Get-Service -Name sshd -ErrorAction Stop
            $serviceFound = $true
        } catch {
            Write-Log "Waiting for sshd service to be available... ($retries retries left)" -Level Info
            Start-Sleep -Seconds 2
            $retries--
        }
    }

    if (-not $serviceFound) {
        Write-Log "SSH Server service (sshd) not found after installation!" -Level Error
        return $false
    }

    # Start the service
    try {
        Write-Log "Starting SSH Server service..."
        Start-Service sshd -ErrorAction Stop
        Write-Log "SSH Server service started successfully" -Level Success
    } catch {
        Write-Log "Failed to start SSH Server service: $_" -Level Error
        $configSuccess = $false
    }

    # Set automatic startup if requested
    if ($AutoStart -or $script:OSInfo.IsServer) {
        try {
            Write-Log "Setting SSH Server service to start automatically..."
            Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
            Write-Log "SSH Server service set to automatic startup" -Level Success

            # Also set ssh-agent to automatic for key management
            try {
                Set-Service -Name ssh-agent -StartupType Automatic -ErrorAction Stop
                Start-Service ssh-agent -ErrorAction Stop
                Write-Log "SSH Agent service configured for automatic startup" -Level Success
            } catch {
                Write-Log "Could not configure SSH Agent service: $_" -Level Warning
            }
        } catch {
            Write-Log "Failed to set automatic startup: $_" -Level Warning
        }
    }

    # Configure firewall
    if (-not $SkipFirewall) {
        Configure-Firewall
    }

    # Create default configuration if it doesn't exist
    Configure-SSHDDefaults

    return $configSuccess
}

function Configure-Firewall {
    <#
    .SYNOPSIS
        Configures Windows Firewall for SSH access
    #>

    Write-Log "Configuring Windows Firewall for SSH..." -Level Info

    try {
        # Check if rule exists
        $existingRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

        if ($existingRule) {
            Write-Log "Firewall rule 'OpenSSH-Server-In-TCP' already exists" -Level Info

            # Ensure it's enabled
            if ($existingRule.Enabled -eq $false) {
                Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction Stop
                Write-Log "Firewall rule 'OpenSSH-Server-In-TCP' has been enabled" -Level Success
            }
        } else {
            Write-Log "Creating firewall rule for OpenSSH Server..."

            New-NetFirewallRule `
                -Name 'OpenSSH-Server-In-TCP' `
                -DisplayName 'OpenSSH Server (sshd)' `
                -Description 'Inbound rule for OpenSSH Server (TCP Port 22)' `
                -Enabled True `
                -Direction Inbound `
                -Protocol TCP `
                -Action Allow `
                -LocalPort 22 `
                -Profile Any `
                -ErrorAction Stop

            Write-Log "Firewall rule 'OpenSSH-Server-In-TCP' created successfully" -Level Success
        }

        # Additional security: Log connection attempts (optional)
        try {
            Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -LogAllowed True -ErrorAction SilentlyContinue
        } catch {}

    } catch {
        Write-Log "Failed to configure firewall: $_" -Level Error
        Write-Log "You may need to manually create a firewall rule for TCP port 22" -Level Warning

        # Provide manual command
        Write-Log "Manual command: New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22" -Level Info
    }
}

function Configure-SSHDDefaults {
    <#
    .SYNOPSIS
        Sets up secure default configuration for SSH Server
    #>

    $sshdConfigPath = "$env:ProgramData\ssh\sshd_config"

    if (-not (Test-Path $sshdConfigPath)) {
        Write-Log "SSH configuration file not found at $sshdConfigPath" -Level Warning
        return
    }

    Write-Log "Reviewing SSH Server configuration..." -Level Info

    try {
        # Backup original configuration
        $backupPath = "$sshdConfigPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -Path $sshdConfigPath -Destination $backupPath -Force
        Write-Log "Configuration backup created: $backupPath" -Level Info

        # Read current configuration
        $config = Get-Content $sshdConfigPath -Raw

        # Security recommendations (commented out by default - admin can enable as needed)
        $securityNote = @"

# Security Hardening Recommendations (uncomment to enable):
# PermitRootLogin no
# PasswordAuthentication yes
# PubkeyAuthentication yes
# PermitEmptyPasswords no
# MaxAuthTries 3
# ClientAliveInterval 300
# ClientAliveCountMax 2
# MaxSessions 10
# AllowGroups ssh-users
"@

        # Add security notes if not already present
        if ($config -notmatch "Security Hardening Recommendations") {
            Add-Content -Path $sshdConfigPath -Value $securityNote
            Write-Log "Added security hardening recommendations to configuration (commented)" -Level Info
        }

    } catch {
        Write-Log "Could not update SSH configuration: $_" -Level Warning
    }
}

function Test-SSHConnection {
    <#
    .SYNOPSIS
        Tests SSH connectivity to localhost
    #>

    Write-Log "Testing SSH connection to localhost..." -Level Info

    try {
        # Get current user info
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

        Write-Log "Current user: $currentUser" -Level Info
        Write-Log "To test SSH connection, run: ssh $currentUser@localhost" -Level Info

        # Check if service is responding on port 22
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $connect = $tcpClient.BeginConnect("127.0.0.1", 22, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne(3000, $false)

        if ($wait -and -not $tcpClient.Connected) {
            Write-Log "SSH Server is not responding on port 22" -Level Warning
        } else {
            Write-Log "SSH Server is responding on port 22" -Level Success

            # Get host key fingerprint for reference
            $hostKeyPath = "$env:ProgramData\ssh\ssh_host_ecdsa_key.pub"
            if (Test-Path $hostKeyPath) {
                Write-Log "Host key location: $hostKeyPath" -Level Info
            }
        }

        $tcpClient.Close()

    } catch {
        Write-Log "Could not test SSH connection: $_" -Level Warning
    }
}

function Show-Summary {
    <#
    .SYNOPSIS
        Displays installation summary and next steps
    #>

    Write-Host "`n" -NoNewline
    Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                  OpenSSH Installation Summary                 ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    $status = Get-OpenSSHStatus

    Write-Host "`nComponent Status:" -ForegroundColor Yellow
    Write-Host "  • OpenSSH Client: " -NoNewline
    if ($status.ClientInstalled) {
        Write-Host "Installed ✓" -ForegroundColor Green
    } else {
        Write-Host "Not Installed" -ForegroundColor Gray
    }

    Write-Host "  • OpenSSH Server: " -NoNewline
    if ($status.ServerInstalled) {
        Write-Host "Installed ✓" -ForegroundColor Green
        Write-Host "  • Service Status: " -NoNewline
        if ($status.SshdRunning) {
            Write-Host "Running ✓" -ForegroundColor Green
        } else {
            Write-Host "Stopped" -ForegroundColor Yellow
        }
        Write-Host "  • Startup Type:   $($status.SshdStartType)" -ForegroundColor Gray
    } else {
        Write-Host "Not Installed" -ForegroundColor Gray
    }

    if ($status.ServerInstalled -and $status.SshdRunning) {
        Write-Host "`nConnection Information:" -ForegroundColor Yellow
        Write-Host "  • Port:     22 (default)" -ForegroundColor Gray
        Write-Host "  • Config:   $env:ProgramData\ssh\sshd_config" -ForegroundColor Gray
        Write-Host "  • Logs:     $env:ProgramData\ssh\logs\" -ForegroundColor Gray

        # Get computer name and IP
        $computerName = $env:COMPUTERNAME
        $ipAddresses = Get-NetIPAddress -AddressFamily IPv4 |
                      Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
                      Select-Object -ExpandProperty IPAddress

        Write-Host "`nTo connect to this server:" -ForegroundColor Yellow
        Write-Host "  From Windows:  ssh username@$computerName" -ForegroundColor Gray
        if ($ipAddresses) {
            Write-Host "  From network:  ssh username@$($ipAddresses[0])" -ForegroundColor Gray
        }
    }

    if ($script:RestartRequired) {
        Write-Host "`n⚠ RESTART REQUIRED" -ForegroundColor Yellow
        Write-Host "  A system restart is required to complete the installation." -ForegroundColor Yellow
        Write-Host "  Run 'Restart-Computer' when ready." -ForegroundColor Gray
    }

    Write-Host "`nNext Steps:" -ForegroundColor Yellow
    Write-Host "  1. Configure SSH keys for passwordless authentication" -ForegroundColor Gray
    Write-Host "  2. Review and harden $env:ProgramData\ssh\sshd_config" -ForegroundColor Gray
    Write-Host "  3. Add users to appropriate groups for SSH access" -ForegroundColor Gray
    Write-Host "  4. Test connectivity from a remote machine" -ForegroundColor Gray

    Write-Host "`nLog file saved to: $LogPath" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

#endregion Functions

#region Main Execution

# Initialize
Clear-Host
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         OpenSSH Automated Installation Script v2.0            ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$script:RestartRequired = $false
$script:OSInfo = @{}

# Start logging
Write-Log "OpenSSH installation script started" -Level Info
Write-Log "Script parameters: ClientOnly=$ClientOnly, ServerOnly=$ServerOnly, AutoStart=$AutoStart, SkipFirewall=$SkipFirewall" -Level Info

# Check prerequisites
if (-not (Test-Prerequisites)) {
    Write-Log "Prerequisites check failed. Exiting..." -Level Error
    exit 1
}

# Get current status
$currentStatus = Get-OpenSSHStatus

# Determine what to install
$installClient = $false
$installServer = $false

if ($ClientOnly) {
    $installClient = -not $currentStatus.ClientInstalled
    $installServer = $false
} elseif ($ServerOnly) {
    $installClient = $false
    $installServer = -not $currentStatus.ServerInstalled
} else {
    # Interactive mode
    if (-not $currentStatus.ClientInstalled) {
        $response = Read-Host "Install OpenSSH Client? (Y/N) [Y]"
        $installClient = ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y')
    }

    if (-not $currentStatus.ServerInstalled) {
        $response = Read-Host "Install OpenSSH Server? (Y/N) [Y]"
        $installServer = ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y')
    } elseif ($currentStatus.ServerInstalled -and -not $currentStatus.SshdRunning) {
        $response = Read-Host "OpenSSH Server is installed but not running. Start it now? (Y/N) [Y]"
        if ($response -eq '' -or $response -eq 'Y' -or $response -eq 'y') {
            Configure-SSHDService
        }
    }
}

# Perform installations
$installationSuccess = $true

if ($installClient) {
    if (-not (Install-OpenSSHClient)) {
        $installationSuccess = $false
    }
}

if ($installServer) {
    if (-not (Install-OpenSSHServer)) {
        $installationSuccess = $false
    }
}

# Test if requested
if ($installServer -or ($currentStatus.ServerInstalled -and $currentStatus.SshdRunning)) {
    Test-SSHConnection
}

# Show summary
Show-Summary

# Exit code
if ($installationSuccess) {
    Write-Log "OpenSSH installation completed successfully" -Level Success
    exit 0
} else {
    Write-Log "OpenSSH installation completed with errors" -Level Warning
    exit 1
}

#endregion Main Execution
