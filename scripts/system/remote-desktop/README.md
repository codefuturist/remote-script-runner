# Remote Desktop Setup

Cross-platform remote desktop server setup for Linux and Windows.

## Overview

This module provides user-friendly scripts to set up remote desktop access on:

- **Linux**: xRDP (RDP protocol - compatible with Windows Remote Desktop Client)
- **Windows**: Native Remote Desktop Services (RDP)

## Quick Start

### Interactive Mode (Recommended)

Simply run the script without arguments to launch the interactive menu:

```bash
# Linux - launches interactive menu
sudo ./remote-desktop-setup.sh

# Windows (PowerShell as Administrator)
.\Remote-Desktop-Setup.ps1
```

The interactive menu provides a user-friendly interface to:
- Install/uninstall remote desktop
- Start/stop/restart services
- Configure firewall and security
- View detailed status

### Linux (Command Line)

```bash
# Install and enable remote desktop
sudo ./remote-desktop-setup.sh install

# Check status
./remote-desktop-setup.sh status

# Apply security hardening
sudo ./remote-desktop-setup.sh security
```

### Windows (PowerShell as Administrator)

```powershell
# Enable Remote Desktop
.\Remote-Desktop-Setup.ps1 -Action Enable

# Check status
.\Remote-Desktop-Setup.ps1 -Action Status

# Apply security hardening
.\Remote-Desktop-Setup.ps1 -Action Security
```

### Remote Execution (Linux)

```bash
# One-liner installation
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/system/remote-desktop/remote-desktop-setup.sh | sudo bash -s -- install

# Check status
curl -fsSL https://codefuturist.github.io/remote-script-runner/scripts/system/remote-desktop/remote-desktop-setup.sh | bash -s -- status
```

## Features

### Linux (xRDP)

| Feature | Description |
|---------|-------------|
| **Interactive menu** | User-friendly menu when run without arguments |
| Multi-distro support | Ubuntu, Debian, Fedora, Rocky, AlmaLinux, openSUSE |
| Desktop detection | Auto-detects GNOME, KDE, XFCE, MATE, Cinnamon |
| Security hardening | TLS encryption, fail2ban integration |
| Firewall configuration | UFW, firewalld, iptables support |
| Service management | Start, stop, enable, disable |

### Windows (RDP)

| Feature | Description |
|---------|-------------|
| **Interactive menu** | User-friendly menu when run without arguments |
| Edition check | Validates Windows Pro/Enterprise requirement |
| NLA enforcement | Network Level Authentication for security |
| Firewall config | Automatic Windows Firewall rules |
| User management | Remote Desktop Users group management |
| Security hardening | SSL/TLS, encryption settings |

## Subcommands

### Linux

| Command | Description |
|---------|-------------|
| *(no args)* | Launch interactive menu |
| `install` | Install xRDP and configure desktop session |
| `status` | Show service status and connection info |
| `start/stop/restart` | Control xRDP service |
| `enable/disable` | Configure boot-time startup |
| `menu` | Launch interactive menu |
| `firewall` | Configure firewall rules for RDP |
| `security` | Apply security hardening |
| `uninstall` | Remove xRDP |

### Windows

| Action | Description |
|--------|-------------|
| *(no args)* | Launch interactive menu |
| `Enable` | Enable RDP and configure firewall |
| `Disable` | Disable RDP |
| `Status` | Show configuration and sessions |
| `Security` | Apply security hardening |
| `Firewall` | Configure firewall only |
| `Users` | Manage allowed users |
| `Menu` | Launch interactive menu |

## Connection

After setup, connect using any RDP client:

### From Windows
1. Press `Win + R`
2. Type `mstsc`
3. Enter the server IP address

### From macOS
1. Install "Microsoft Remote Desktop" from App Store
2. Add a new PC with the server IP

### From Linux
```bash
# Using Remmina (GUI)
remmina

# Using xfreerdp (CLI)
xfreerdp /v:192.168.1.100 /u:username

# Using rdesktop
rdesktop 192.168.1.100
```

## Security Best Practices

### Recommended Settings

1. **Enable NLA** (Network Level Authentication)
   - Requires authentication before session starts
   - Prevents anonymous resource consumption

2. **Use TLS/SSL**
   - Encrypts all RDP traffic
   - Protects credentials in transit

3. **Strong Passwords**
   - Enforce complex password policy
   - Consider account lockout policy

4. **Limit Users**
   - Only add necessary users to RDP access
   - Use `Remote Desktop Users` group

5. **Firewall Rules**
   - Restrict access to trusted IPs when possible
   - Consider VPN for remote access

6. **Keep Updated**
   - Regular security patches
   - Monitor for RDP vulnerabilities

### Port Security

The default RDP port is 3389. For additional security:

```bash
# Linux: Change port in /etc/xrdp/xrdp.ini
port=3390

# Windows: Change via registry
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'PortNumber' -Value 3390
```

Remember to update firewall rules when changing ports.

## Supported Systems

### Linux Distributions

| Distribution | Versions | Desktop Environments |
|--------------|----------|---------------------|
| Ubuntu | 20.04, 22.04, 24.04 | GNOME, XFCE, KDE |
| Debian | 11, 12 | GNOME, XFCE, KDE |
| Linux Mint | 20, 21 | Cinnamon, MATE, XFCE |
| Fedora | 38, 39, 40 | GNOME, KDE |
| Rocky Linux | 8, 9 | GNOME |
| AlmaLinux | 8, 9 | GNOME |
| openSUSE | Leap 15.x | KDE, GNOME |

### Windows Editions

| Edition | RDP Server Support |
|---------|-------------------|
| Windows 10/11 Home | ❌ No (client only) |
| Windows 10/11 Pro | ✅ Yes |
| Windows 10/11 Enterprise | ✅ Yes |
| Windows 10/11 Education | ✅ Yes |
| Windows Server | ✅ Yes |

## Troubleshooting

### Linux

**Black screen after login:**
```bash
# Check session configuration
cat /etc/xrdp/startwm.sh

# For GNOME, try:
echo "gnome-session" > ~/.xsession
```

**Authentication issues:**
```bash
# Check xrdp-sesman logs
sudo journalctl -u xrdp-sesman -f

# Ensure dbus is available
sudo apt install dbus-x11
```

**Slow performance:**
- Use XFCE instead of GNOME/KDE
- Reduce color depth in RDP client settings
- Disable visual effects

### Windows

**Cannot enable RDP:**
- Verify Windows edition (Pro/Enterprise required)
- Run PowerShell as Administrator
- Check TermService status

**Connection refused:**
```powershell
# Check firewall
Get-NetFirewallRule -DisplayGroup "Remote Desktop"

# Check if service is running
Get-Service TermService
```

## Files

```
scripts/system/remote-desktop/
├── README.md                    # This file
├── remote-desktop-setup.sh      # Linux setup script
└── Remote-Desktop-Setup.ps1     # Windows setup script
```

## See Also

- [SSH Server Management](../../../docs/SSH_SERVER_MANAGEMENT.md)
- [User Management](../../../docs/USER_MANAGEMENT.md)
- [Security Hardening](../../security/hardening/)
