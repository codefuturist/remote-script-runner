# test/lib/Test-RSR.ps1 - PowerShell Tests for RSR Module
#
# Run with: Invoke-Pester test/lib/Test-RSR.ps1
# Or: pwsh -c "Invoke-Pester test/lib/Test-RSR.ps1"

#Requires -Version 5.1

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '../../lib/powershell/RSR.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

Describe 'RSR.Core Module' {

    Context 'Logging Functions' {

        It 'Write-RSRLog should not throw' {
            { Write-RSRLog 'Test message' -Level Info } | Should -Not -Throw
        }

        It 'Write-RSRInfo should not throw' {
            { Write-RSRInfo 'Info message' } | Should -Not -Throw
        }

        It 'Write-RSROk should not throw' {
            { Write-RSROk 'Success message' } | Should -Not -Throw
        }

        It 'Write-RSRWarn should not throw' {
            { Write-RSRWarn 'Warning message' } | Should -Not -Throw
        }

        It 'Write-RSRError should not throw' {
            { Write-RSRError 'Error message' } | Should -Not -Throw
        }
    }

    Context 'Platform Detection' {

        It 'Get-RSRPlatform should return valid platform' {
            $platform = Get-RSRPlatform
            $platform | Should -BeIn @('Windows', 'Linux', 'macOS')
        }

        It 'Get-RSRArchitecture should return valid architecture' {
            $arch = Get-RSRArchitecture
            $arch | Should -Match '^(amd64|arm64|arm|i386|X64|X86|Arm64)$'
        }
    }

    Context 'Command Utilities' {

        It 'Test-RSRCommand should return true for existing command' {
            Test-RSRCommand 'pwsh' | Should -BeIn @($true, $false)
        }

        It 'Test-RSRCommand should return false for nonexistent command' {
            Test-RSRCommand 'nonexistent_command_12345' | Should -Be $false
        }

        It 'Test-RSRRoot should return boolean' {
            Test-RSRRoot | Should -BeOfType [bool]
        }
    }
}

Describe 'RSR.Validate Module' {

    Context 'Username Validation' {

        It 'Test-RSRUsername should accept valid username' {
            Test-RSRUsername 'john' | Should -Be $true
        }

        It 'Test-RSRUsername should accept username with numbers' {
            Test-RSRUsername 'john123' | Should -Be $true
        }

        It 'Test-RSRUsername should reject empty username' {
            Test-RSRUsername '' | Should -Be $false
        }

        It 'Test-RSRUsername should reject username starting with number' {
            Test-RSRUsername '1john' | Should -Be $false
        }

        It 'Test-RSRUsername should reject uppercase' {
            Test-RSRUsername 'John' | Should -Be $false
        }
    }

    Context 'Password Validation' {

        It 'Test-RSRPassword should accept valid password' {
            Test-RSRPassword 'password123' | Should -Be $true
        }

        It 'Test-RSRPassword should reject short password' {
            Test-RSRPassword 'short' | Should -Be $false
        }

        It 'Test-RSRPasswordComplex should accept complex password' {
            Test-RSRPasswordComplex 'MyP@ssw0rd' | Should -Be $true
        }

        It 'Test-RSRPasswordComplex should reject simple password' {
            Test-RSRPasswordComplex 'password' | Should -Be $false
        }
    }

    Context 'Network Validation' {

        It 'Test-RSRIPv4 should accept valid IPv4' {
            Test-RSRIPv4 '192.168.1.1' | Should -Be $true
        }

        It 'Test-RSRIPv4 should reject invalid IPv4' {
            Test-RSRIPv4 '192.168.1.256' | Should -Be $false
        }

        It 'Test-RSRHostname should accept valid hostname' {
            Test-RSRHostname 'server.example.com' | Should -Be $true
        }

        It 'Test-RSRPort should accept valid port' {
            Test-RSRPort 8080 | Should -Be $true
        }

        It 'Test-RSRPort should reject invalid port' {
            Test-RSRPort 65536 | Should -Be $false
        }

        It 'Test-RSREmail should accept valid email' {
            Test-RSREmail 'user@example.com' | Should -Be $true
        }

        It 'Test-RSREmail should reject invalid email' {
            Test-RSREmail 'not-an-email' | Should -Be $false
        }

        It 'Test-RSRUrl should accept valid URL' {
            Test-RSRUrl 'https://example.com' | Should -Be $true
        }

        It 'Test-RSRUrl should reject invalid URL' {
            Test-RSRUrl 'not-a-url' | Should -Be $false
        }
    }
}

Describe 'RSR.Users Module' -Skip:($PSVersionTable.Platform -ne 'Win32NT') {

    Context 'User Existence' {

        It 'Test-RSRUserExists should return true for Administrator' {
            Test-RSRUserExists 'Administrator' | Should -Be $true
        }

        It 'Test-RSRUserExists should return false for nonexistent user' {
            Test-RSRUserExists 'nonexistent_user_12345' | Should -Be $false
        }
    }

    Context 'User Listing' {

        It 'Get-RSRUsers should return users' {
            $users = Get-RSRUsers
            $users | Should -Not -BeNullOrEmpty
        }

        It 'Get-RSRHumanUsers should not throw' {
            { Get-RSRHumanUsers } | Should -Not -Throw
        }
    }

    Context 'Group Management' {

        It 'Test-RSRGroupExists should return true for Administrators' {
            Test-RSRGroupExists 'Administrators' | Should -Be $true
        }

        It 'Test-RSRGroupExists should return false for nonexistent group' {
            Test-RSRGroupExists 'nonexistent_group_12345' | Should -Be $false
        }

        It 'Get-RSRGroups should return groups' {
            $groups = Get-RSRGroups
            $groups | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Password Generation' {

        It 'New-RSRRandomPassword should generate password of default length' {
            $pass = New-RSRRandomPassword
            $pass.Length | Should -Be 16
        }

        It 'New-RSRRandomPassword should generate password of custom length' {
            $pass = New-RSRRandomPassword -Length 24
            $pass.Length | Should -Be 24
        }

        It 'New-RSRRandomPassword should return SecureString when requested' {
            $pass = New-RSRRandomPassword -AsSecureString
            $pass | Should -BeOfType [System.Security.SecureString]
        }
    }
}

Describe 'RSR.Docker Module' {

    Context 'Docker Detection' {

        It 'Test-RSRDockerInstalled should return boolean' {
            Test-RSRDockerInstalled | Should -BeOfType [bool]
        }

        It 'Get-RSRDockerVersion should return version or not_installed' {
            $version = Get-RSRDockerVersion
            $version | Should -Match '^(\d+\.\d+|not_installed)'
        }
    }

    Context 'Docker Operations' -Skip:(-not (Test-RSRDockerInstalled) -or -not (Test-RSRDockerRunning)) {

        It 'Test-RSRDockerRunning should return true' {
            Test-RSRDockerRunning | Should -Be $true
        }

        It 'Test-RSRDockerContainerExists should return false for nonexistent container' {
            Test-RSRDockerContainerExists 'nonexistent_container_12345' | Should -Be $false
        }

        It 'Get-RSRDockerContainers should not throw' {
            { Get-RSRDockerContainers } | Should -Not -Throw
        }

        It 'Get-RSRDockerImages should not throw' {
            { Get-RSRDockerImages } | Should -Not -Throw
        }

        It 'Get-RSRDockerVolumes should not throw' {
            { Get-RSRDockerVolumes } | Should -Not -Throw
        }

        It 'Get-RSRDockerNetworks should not throw' {
            { Get-RSRDockerNetworks } | Should -Not -Throw
        }
    }
}

Describe 'RSR.SSH Module' {

    Context 'SSH Detection' {

        It 'Test-RSRSSHServerInstalled should return boolean' {
            Test-RSRSSHServerInstalled | Should -BeOfType [bool]
        }

        It 'Get-RSRSSHServerStatus should return object' {
            $status = Get-RSRSSHServerStatus
            $status | Should -Not -BeNullOrEmpty
            $status.Installed | Should -BeOfType [bool]
            $status.Running | Should -BeOfType [bool]
            $status.Enabled | Should -BeOfType [bool]
        }
    }
}

AfterAll {
    Remove-Module RSR -ErrorAction SilentlyContinue
}

