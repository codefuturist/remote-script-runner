---
author: robinharwood
description: Learn how to install and connect to remote machines using the OpenSSH Client and Server for Windows.
source: https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11
---
# Get started with OpenSSH Server for Windows

![](open-graph-image.png)
Learn how to install and connect to remote machines using the OpenSSH Client and Server for Windows.

OpenSSH is a connectivity tool for remote sign-in that uses the SSH protocol. It encrypts all traffic between client and server to eliminate eavesdropping, connection hijacking, and other attacks.

An OpenSSH-compatible client can be used to connect to Windows Server and Windows client devices.

Important

If you downloaded the OpenSSH beta from the GitHub repo at [PowerShell/openssh-portal](https://github.com/PowerShell/openssh-portable), follow the instructions listed there, not the ones in this article. Some information in the Win32-OpenSSH repository relates to prerelease product that might be substantially modified before it's released. Microsoft makes no warranties, express or implied, with respect to the information provided there.

Before you start, your computer must meet the following requirements:

* A device running at least Windows Server 2019 or Windows 10 (build 1809).

* PowerShell 5.1 or later.

* An account that is a member of the built-in Administrators group.

To validate your environment, open an elevated PowerShell session and do the following:

* Enter *winver.exe* and press enter to see the version details for your Windows device.

* Run `$PSVersionTable.PSVersion`. Verify your major version is at least 5, and your minor version at least 1. Learn more about [installing PowerShell on Windows](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows).

* To check when you're an administrator, run the following command. The output shows `True` when you're a member of the built-in Administrators group.

```
(New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

Beginning with Windows Server 2025, OpenSSH is now installed by default. You can also enable or disable the `sshd` service in Server Manager.

* [GUI](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_1_gui)
* [PowerShell](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_1_powershell)
To enable SSHD using PowerShell:

1. Open PowerShell as an administrator and run the following cmdlet to start the SSHD service:

```
# Start the sshd service
Start-Service sshd
```

1. You can also run the following optional but recommended cmdlet to automatically start SSHD to make sure it stays enabled:

```
Set-Service -Name sshd -StartupType 'Automatic'
```

1. Finally, run the following command to verify that the SSHD setup process automatically configured the firewall rule:

```
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}
```

⠀

* [GUI](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_2_gui)
* [PowerShell](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_2_powershell)
To install OpenSSH using PowerShell:

1. Run PowerShell as an Administrator.

2. Run the following cmdlet to make sure that OpenSSH is available:

```
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'
```

1. The command should return the following output if neither are already installed:

```
Name  : OpenSSH.Client~~~~0.0.1.0
State : NotPresent

Name  : OpenSSH.Server~~~~0.0.1.0
State : NotPresent
```

1. After that, run the following cmdlets to install the server or client components as needed:

```
# Install the OpenSSH Client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Install the OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

1. Both commands should return the following output:

```
Path          :
Online        : True
RestartNeeded : False
```

1. To start and configure OpenSSH Server for initial use, open an elevated PowerShell prompt (right-click, then select **Run as an administrator**), then run the following commands to start the `sshd service`:

```
# Start the sshd service
Start-Service sshd

# OPTIONAL but recommended:
Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}
```

⠀

* [GUI](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_3_gui)
* [PowerShell](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_3_powershell)
To install OpenSSH using PowerShell:

1. Run PowerShell as an Administrator.

2. Run the following cmdlet to make sure that OpenSSH is available:

```
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'
```

1. The command should return the following output if neither are already installed:

```
Name  : OpenSSH.Client~~~~0.0.1.0
State : NotPresent

Name  : OpenSSH.Server~~~~0.0.1.0
State : NotPresent
```

1. After that, run the following cmdlets to install the server or client components as needed:

```
# Install the OpenSSH Client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Install the OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

1. Both commands should return the following output:

```
Path          :
Online        : True
RestartNeeded : False
```

1. To start and configure OpenSSH Server for initial use, open an elevated PowerShell prompt (right-click, then select **Run as an administrator**), then run the following commands to start the `sshd service`:

```
# Start the sshd service
Start-Service sshd

# OPTIONAL but recommended:
Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}
```

⠀

* [GUI](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_4_gui)
* [PowerShell](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_4_powershell)
To install OpenSSH using PowerShell:

1. Run PowerShell as an Administrator.

2. Run the following cmdlet to make sure that OpenSSH is available:

```
Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH*'
```

1. The command should return the following output if neither are already installed:

```
Name  : OpenSSH.Client~~~~0.0.1.0
State : NotPresent

Name  : OpenSSH.Server~~~~0.0.1.0
State : NotPresent
```

1. After that, run the following cmdlets to install the server or client components as needed:

```
# Install the OpenSSH Client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Install the OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

1. Both commands should return the following output:

```
Path          :
Online        : True
RestartNeeded : False
```

1. To start and configure OpenSSH Server for initial use, open an elevated PowerShell prompt (right-click, then select **Run as an administrator**), then run the following commands to start the `sshd service`:

```
# Start the sshd service
Start-Service sshd

# OPTIONAL but recommended:
Set-Service -Name sshd -StartupType 'Automatic'

# Confirm the Firewall rule is configured. It should be created automatically by setup. Run the following to verify
if (!(Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, creating it..."
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
} else {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' has been created and exists."
}
```

⠀
Once installed, you can connect to OpenSSH Server from a Windows or Windows Server device with the OpenSSH client installed. From a PowerShell prompt, run the following command.

```
ssh domain\username@servername
```

Once connected, you get a message similar to the following output.

```
The authenticity of host 'servername (10.00.00.001)' can't be established.
ECDSA key fingerprint is SHA256:(<a large string>).
Are you sure you want to continue connecting (yes/no)?
```

Entering *yes* adds that server to the list of known SSH hosts on your Windows client.

At this point, the service prompts you for your password. As a security precaution, the characters of your password aren't displayed as you enter them.

Once connected, you should see the following Windows command shell prompt:

```
domain\username@SERVERNAME C:\Users\username>
```

You can disable the `sshd` service in Server Manager.

* [GUI](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_5_gui)
* [PowerShell](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_5_powershell)
To disable SSHD using PowerShell:

1. Open PowerShell as an administrator and run the following cmdlet to start the SSHD service:

```
# Stop the sshd service
Stop-Service sshd
```

1. You can also run the following optional but recommended cmdlet to automatically start SSHD to make sure it stays enabled:

```
Set-Service -Name sshd -StartupType 'Disabled'
```

1. Finally, run the following command to disable the default SSHD firewall rule:

```
if ((Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' is being disabled."
    Disable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
} else {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, disable failed..."
}
```

⠀

* [GUI](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_6_gui)
* [PowerShell](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_6_powershell)
To uninstall the OpenSSH components using PowerShell, follow these steps.

1. Open PowerShell as an administrator.

2. To remove OpenSSH, use the following commands:

```
# Uninstall the OpenSSH Client
Remove-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Uninstall the OpenSSH Server
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

1. Finally, run the following command to remove the firewall rule:

```
if ((Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' is being removed."
    Remove-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
} else {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, removal failed..."
}
```

⠀

* [GUI](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_7_gui)
* [PowerShell](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11#tabpanel_7_powershell)
To uninstall the OpenSSH components using PowerShell, follow these steps.

1. Open PowerShell as an administrator.

2. To remove OpenSSH, use the following commands:

```
# Uninstall the OpenSSH Client
Remove-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Uninstall the OpenSSH Server
Remove-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

1. Finally, run the following command to remove the firewall rule:

```
if ((Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
    Write-Output "Firewall rule 'OpenSSH-Server-In-TCP' is being removed."
    Remove-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
} else {
    Write-Output "Firewall Rule 'OpenSSH-Server-In-TCP' does not exist, removal failed..."
}
```

⠀
If the service was in use when you uninstalled it, you should restart Windows.

Now that you're done installing OpenSSH Server for Windows, here are some articles that can help you learn how to use it:

* Learn more about using key pairs for authentication in [OpenSSH key management](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)

* Learn more about the [OpenSSH Server configuration for Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_server_configuration)

[Get started with OpenSSH Server for Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?tabs=powershell&pivots=windows-11)

# web
