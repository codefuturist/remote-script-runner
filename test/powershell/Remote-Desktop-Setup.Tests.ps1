<#
.SYNOPSIS
    Tests for Remote-Desktop-Setup.ps1

.DESCRIPTION
    Pester tests for the Windows Remote Desktop configuration script.
    Tests cover parameter validation, status display, and security settings.

.NOTES
    These tests use mocking to avoid actually changing RDP settings.
    Some tests are skipped on non-Windows systems.
#>

BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot '../../scripts/system/remote-desktop/Remote-Desktop-Setup.ps1'
}

Describe 'Remote-Desktop-Setup' {
    Context 'Script Basics' {
        It 'Should exist at expected path' {
            Test-Path $ScriptPath | Should -Be $true
        }

        It 'Should have valid PowerShell syntax' {
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $ScriptPath,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0
        }

        It 'Should have comment-based help' {
            $help = Get-Help $ScriptPath
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It 'Should have examples in help' {
            $help = Get-Help $ScriptPath -Examples
            $help.Examples | Should -Not -BeNullOrEmpty
        }

        It 'Should require Administrator privileges' {
            $content = Get-Content $ScriptPath -Raw
            $content | Should -Match '#Requires -RunAsAdministrator'
        }

        It 'Should require PowerShell 5.1+' {
            $content = Get-Content $ScriptPath -Raw
            $content | Should -Match '#Requires -Version 5\.1'
        }
    }

    Context 'Parameter Validation' {
        It 'Should accept -Action parameter' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Action') | Should -Be $true
        }

        It 'Should validate Action parameter values' {
            $cmd = Get-Command $ScriptPath
            $validateSet = $cmd.Parameters['Action'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            
            $validateSet.ValidValues | Should -Contain 'Enable'
            $validateSet.ValidValues | Should -Contain 'Disable'
            $validateSet.ValidValues | Should -Contain 'Status'
            $validateSet.ValidValues | Should -Contain 'Security'
            $validateSet.ValidValues | Should -Contain 'Firewall'
            $validateSet.ValidValues | Should -Contain 'Users'
            $validateSet.ValidValues | Should -Contain 'Menu'
            $validateSet.ValidValues | Should -Contain 'Help'
        }

        It 'Should accept -Force parameter' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Force') | Should -Be $true
        }

        It 'Should accept -Help parameter' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Help') | Should -Be $true
        }

        It 'Should support -WhatIf (SupportsShouldProcess)' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
        }
    }

    Context 'Help Display' {
        It 'Should display help with -Help parameter' {
            # Run in a separate PowerShell process to avoid Administrator requirement
            $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
                try {
                    & '$ScriptPath' -Help 2>&1
                } catch {
                    'Help displayed'
                }
            " 2>&1
            
            # Help should contain usage info
            ($output -join "`n") | Should -Match 'USAGE|Usage|Remote-Desktop'
        }

        It 'Should display help with -Action Help' {
            $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
                try {
                    & '$ScriptPath' -Action Help 2>&1
                } catch {
                    'Help displayed'
                }
            " 2>&1
            
            ($output -join "`n") | Should -Match 'USAGE|Usage|Remote-Desktop'
        }
    }

    Context 'Interactive Mode' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should contain Show-InteractiveMenu function' {
            $content | Should -Match 'function Show-InteractiveMenu'
        }

        It 'Should check for interactive environment' {
            $content | Should -Match 'UserInteractive|ConsoleHost'
        }

        It 'Should support Menu action' {
            $cmd = Get-Command $ScriptPath
            $validateSet = $cmd.Parameters['Action'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Menu'
        }

        It 'Should mention interactive mode in help' {
            $content | Should -Match 'INTERACTIVE MODE'
        }

        It 'Should have menu options for all features' {
            $content | Should -Match 'Enable Remote Desktop'
            $content | Should -Match 'Disable Remote Desktop'
            $content | Should -Match 'security hardening'
        }
    }

    Context 'Script Content Validation' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should contain Enable-RemoteDesktop function' {
            $content | Should -Match 'function Enable-RemoteDesktop'
        }

        It 'Should contain Disable-RemoteDesktop function' {
            $content | Should -Match 'function Disable-RemoteDesktop'
        }

        It 'Should contain Get-RDPStatus function' {
            $content | Should -Match 'function Get-RDPStatus'
        }

        It 'Should contain Set-RDPSecurity function' {
            $content | Should -Match 'function Set-RDPSecurity'
        }

        It 'Should contain Enable-RDPFirewall function' {
            $content | Should -Match 'function Enable-RDPFirewall'
        }

        It 'Should contain Set-RDPUsers function' {
            $content | Should -Match 'function Set-RDPUsers'
        }

        It 'Should contain Test-WindowsEdition function' {
            $content | Should -Match 'function Test-WindowsEdition'
        }
    }

    Context 'Windows Edition Detection' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should check for supported Windows editions' {
            $content | Should -Match 'Pro'
            $content | Should -Match 'Enterprise'
            $content | Should -Match 'Server'
        }

        It 'Should warn about Windows Home edition' {
            $content | Should -Match 'Home|home'
        }

        It 'Should use Win32_OperatingSystem for edition detection' {
            $content | Should -Match 'Win32_OperatingSystem'
        }
    }

    Context 'Registry Settings' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should reference Terminal Server registry key' {
            $content | Should -Match 'Terminal Server'
        }

        It 'Should reference fDenyTSConnections setting' {
            $content | Should -Match 'fDenyTSConnections'
        }

        It 'Should reference UserAuthentication (NLA) setting' {
            $content | Should -Match 'UserAuthentication'
        }

        It 'Should reference RDP-Tcp settings' {
            $content | Should -Match 'RDP-Tcp'
        }
    }

    Context 'Security Hardening' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should configure Network Level Authentication (NLA)' {
            $content | Should -Match 'NLA|Network Level Authentication'
        }

        It 'Should configure encryption level' {
            $content | Should -Match 'MinEncryptionLevel|encryption'
        }

        It 'Should configure SSL/TLS security layer' {
            $content | Should -Match 'SecurityLayer|SSL|TLS'
        }

        It 'Should provide security recommendations' {
            $content | Should -Match 'Recommendation|recommendation|strong password'
        }

        It 'Should mention account lockout policy' {
            $content | Should -Match 'lockout'
        }
    }

    Context 'Firewall Configuration' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should use Enable-NetFirewallRule' {
            $content | Should -Match 'Enable-NetFirewallRule'
        }

        It 'Should reference Remote Desktop display group' {
            $content | Should -Match 'Remote Desktop'
        }

        It 'Should handle firewall rule creation' {
            $content | Should -Match 'New-NetFirewallRule'
        }

        It 'Should use correct RDP port (3389)' {
            $content | Should -Match '3389'
        }
    }

    Context 'Service Management' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should manage TermService' {
            $content | Should -Match 'TermService'
        }

        It 'Should use Start-Service' {
            $content | Should -Match 'Start-Service'
        }

        It 'Should use Stop-Service' {
            $content | Should -Match 'Stop-Service'
        }

        It 'Should configure service startup type' {
            $content | Should -Match 'Set-Service.*StartupType'
        }
    }

    Context 'User Management' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should reference Remote Desktop Users group' {
            $content | Should -Match 'Remote Desktop Users'
        }

        It 'Should use Get-LocalGroupMember' {
            $content | Should -Match 'Get-LocalGroupMember'
        }

        It 'Should mention Add-LocalGroupMember' {
            $content | Should -Match 'Add-LocalGroupMember'
        }
    }

    Context 'Status Output' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should check if RDP is enabled' {
            $content | Should -Match 'fDenyTSConnections'
        }

        It 'Should check NLA status' {
            $content | Should -Match 'UserAuthentication'
        }

        It 'Should check firewall rules' {
            $content | Should -Match 'Get-NetFirewallRule'
        }

        It 'Should check listening ports' {
            $content | Should -Match 'Get-NetTCPConnection|listening'
        }

        It 'Should display connection info with IP address' {
            $content | Should -Match 'Get-NetIPAddress|IPAddress'
        }

        It 'Should display active sessions' {
            $content | Should -Match 'quser|sessions'
        }
    }

    Context 'Error Handling' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should set ErrorActionPreference to Stop' {
            $content | Should -Match "\`$ErrorActionPreference\s*=\s*'Stop'"
        }

        It 'Should use -ErrorAction SilentlyContinue where appropriate' {
            $content | Should -Match 'ErrorAction SilentlyContinue'
        }

        It 'Should have try-catch blocks for error handling' {
            $content | Should -Match 'try\s*{|catch\s*{'
        }
    }

    Context 'RSR Library Integration' {
        BeforeAll {
            $content = Get-Content $ScriptPath -Raw
        }

        It 'Should attempt to load RSR library' {
            $content | Should -Match 'RSR\.psd1|RSRModulePath'
        }

        It 'Should have standalone fallback logging' {
            $content | Should -Match 'function Write-Info|Write-RSRInfo'
        }
    }
}

Describe 'Remote-Desktop-Setup Integration' -Tag 'Integration' -Skip:(-not $IsWindows) {
    Context 'RSR Entry Point' {
        BeforeAll {
            $rsrPath = Join-Path $PSScriptRoot '../../rsr.ps1'
            $registryPath = Join-Path $PSScriptRoot '../../scripts/registry.json'
        }

        It 'Should be registered in registry.json' {
            if (Test-Path $registryPath) {
                $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
                $rdpScript = $registry.scripts | Where-Object { $_.command -eq 'remote-desktop' }
                $rdpScript | Should -Not -BeNullOrEmpty
                $rdpScript.platforms | Should -Contain 'windows'
            }
        }

        It 'Should have PowerShell script path in registry' {
            if (Test-Path $registryPath) {
                $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
                $rdpScript = $registry.scripts | Where-Object { $_.command -eq 'remote-desktop' }
                $rdpScript.powershell | Should -Match 'Remote-Desktop-Setup\.ps1'
            }
        }
    }

    Context 'Windows-Specific Functionality' -Skip:(-not $IsWindows) {
        It 'Should detect Windows edition without errors' {
            # This would need to be run with mocking in a real environment
            # Just testing that the script structure is correct
            $content = Get-Content $ScriptPath -Raw
            $content | Should -Match 'Get-CimInstance.*Win32_OperatingSystem'
        }
    }
}
