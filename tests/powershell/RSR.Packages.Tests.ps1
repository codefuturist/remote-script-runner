#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for RSR.Packages module
.DESCRIPTION
    Tests package manager detection, installation functions, and profile management
#>

BeforeAll {
    # Import RSR module
    $ModulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "lib\powershell"
    Import-Module (Join-Path $ModulePath "RSR.psd1") -Force
}

Describe 'RSR.Packages Module' {
    
    Context 'Package Manager Detection' {
        
        It 'Get-RSRPackageManager should return a package manager' {
            $mgr = Get-RSRPackageManager
            $mgr | Should -Not -BeNullOrEmpty
        }
        
        It 'Get-RSRPackageManager should return valid manager name' {
            $mgr = Get-RSRPackageManager
            $validManagers = @('winget', 'choco', 'scoop', 'brew', 'apt', 'dnf', 'pacman', 'zypper', 'unknown')
            $mgr | Should -BeIn $validManagers
        }
        
        It 'Get-RSRAvailableMethods should return array' {
            $methods = Get-RSRAvailableMethods
            $methods | Should -BeOfType [System.Array]
        }
    }
    
    Context 'Profile Management' {
        
        It 'Get-RSRPackageProfiles should return profiles' {
            $profiles = Get-RSRPackageProfiles
            $profiles | Should -Not -BeNullOrEmpty
        }
        
        It 'Get-RSRPackageProfiles should return objects with required properties' {
            $profiles = Get-RSRPackageProfiles
            $profiles[0] | Should -HaveProperty 'Name'
            $profiles[0] | Should -HaveProperty 'Description'
            $profiles[0] | Should -HaveProperty 'Path'
        }
        
        It 'Get-RSRPackageProfileInfo should return profile info for core' {
            $info = Get-RSRPackageProfileInfo -Profile 'core'
            $info | Should -Not -BeNullOrEmpty
            $info.Name | Should -Be 'core'
        }
        
        It 'Get-RSRPackageProfileInfo should throw for non-existent profile' {
            { Get-RSRPackageProfileInfo -Profile 'nonexistent' } | Should -Throw
        }
        
        It 'Get-RSRPackageGroups should return groups for development profile' {
            $groups = Get-RSRPackageGroups -Profile 'development-v2'
            $groups | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'YAML Parsing' {
        
        It 'ConvertFrom-RSRYaml should parse core.yaml' {
            $profilePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "config\packages\core.yaml"
            $yaml = ConvertFrom-RSRYaml -Path $profilePath
            $yaml | Should -Not -BeNullOrEmpty
            $yaml['name'] | Should -Be 'core'
        }
        
        It 'Get-RSRYamlSection should extract packages section' {
            $profilePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "config\packages\core.yaml"
            $packages = Get-RSRYamlSection -Path $profilePath -Section 'packages'
            $packages | Should -BeOfType [System.Array]
        }
        
        It 'Get-RSRYamlGroups should return groups from development-v2.yaml' {
            $profilePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "config\packages\development-v2.yaml"
            $groups = Get-RSRYamlGroups -Path $profilePath
            $groups | Should -Not -BeNullOrEmpty
        }
        
        It 'Get-RSRYamlGroupPackages should extract packages from group path' {
            $profilePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "config\packages\development-v2.yaml"
            $packages = Get-RSRYamlGroupPackages -Path $profilePath -GroupPath 'essentials'
            $packages | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Package Status Functions' {
        
        It 'Test-RSRPackageInstalled should check for git' {
            # Test should work regardless of whether git is installed
            { Test-RSRPackageInstalled -Name 'git' } | Should -Not -Throw
        }
        
        It 'Test-RSRPackageInstalled should return boolean' {
            $result = Test-RSRPackageInstalled -Name 'git'
            $result | Should -BeOfType [System.Boolean]
        }
    }
    
    Context 'Cache Management' {
        
        It 'Update-RSRPackageCache should not throw' {
            { Update-RSRPackageCache } | Should -Not -Throw
        }
        
        It 'Clear-RSRPackageCache should not throw' {
            { Clear-RSRPackageCache } | Should -Not -Throw
        }
    }
}

Describe 'Install-PackageProfile.ps1 Script' {
    
    BeforeAll {
        $ScriptPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "scripts\packages\Install-PackageProfile.ps1"
    }
    
    Context 'Script Execution' {
        
        It 'Script file should exist' {
            Test-Path $ScriptPath | Should -Be $true
        }
        
        It 'Should list profiles without error' {
            { & $ScriptPath -List } | Should -Not -Throw
        }
        
        It 'Should show groups for development profile' {
            { & $ScriptPath -Groups 'development-v2' } | Should -Not -Throw
        }
        
        It 'Should show info for core profile' {
            { & $ScriptPath -Info 'core' } | Should -Not -Throw
        }
    }
}
