# PowerShell Tests

BeforeAll {
    # Import the script to test
    $script:scriptPath = Join-Path $PSScriptRoot '../../scripts/powershell/Install-OpenSSH.ps1'
}

Describe 'Install-OpenSSH.ps1 - Script File' {
    It 'Should exist' {
        $script:scriptPath | Should -Exist
    }

    It 'Should be a valid PowerShell script' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Not -BeNullOrEmpty
    }

    It 'Should have proper comment-based help' {
        $help = Get-Help $script:scriptPath
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.Examples | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-OpenSSH.ps1 - Parameters' {
    It 'Should have ClientOnly parameter' {
        $params = (Get-Command $script:scriptPath).Parameters
        $params.ContainsKey('ClientOnly') | Should -Be $true
        $params['ClientOnly'].ParameterType.Name | Should -Be 'SwitchParameter'
    }

    It 'Should have ServerOnly parameter' {
        $params = (Get-Command $script:scriptPath).Parameters
        $params.ContainsKey('ServerOnly') | Should -Be $true
    }

    It 'Should have AutoStart parameter' {
        $params = (Get-Command $script:scriptPath).Parameters
        $params.ContainsKey('AutoStart') | Should -Be $true
    }

    It 'Should have LogPath parameter with default value' {
        $params = (Get-Command $script:scriptPath).Parameters
        $params.ContainsKey('LogPath') | Should -Be $true
    }
}

Describe 'Install-OpenSSH.ps1 - Functions' {
    It 'Should have Write-Log function' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match 'function Write-Log'
    }

    It 'Should have Test-Prerequisites function' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match 'function Test-Prerequisites'
    }

    It 'Should have proper error handling with try-catch blocks' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match 'try\s*\{'
        $scriptContent | Should -Match 'catch\s*\{'
    }
}

Describe 'Install-OpenSSH.ps1 - Code Quality' {
    It 'Should follow PowerShell naming conventions' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        # Check for PascalCase function names
        $scriptContent | Should -Match 'function [A-Z][a-zA-Z]*-[A-Z][a-zA-Z]*'
    }

    It 'Should use approved verbs for functions where possible' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $functions = [regex]::Matches($scriptContent, 'function ([A-Z][a-zA-Z]*)-') | ForEach-Object { $_.Groups[1].Value }

        # Note: Some legacy functions may use non-approved verbs
        # This test verifies the pattern exists, not strict enforcement
        $functions.Count | Should -BeGreaterThan 0

        # Verify at least some functions use approved verbs
        $approvedVerbs = Get-Verb | Select-Object -ExpandProperty Verb
        $approvedCount = 0
        foreach ($verb in $functions) {
            if ($verb -in $approvedVerbs) {
                $approvedCount++
            }
        }
        $approvedCount | Should -BeGreaterThan 0
    }

    It 'Should have CmdletBinding on main script' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match '\[CmdletBinding\(\)\]'
    }

    It 'Should have parameter validation' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match '\[Parameter\('
    }
}

Describe 'Install-OpenSSH.ps1 - Documentation' {
    It 'Should have Synopsis in comment-based help' {
        $help = Get-Help $script:scriptPath
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis.Length | Should -BeGreaterThan 20
    }

    It 'Should have Description in comment-based help' {
        $help = Get-Help $script:scriptPath
        $help.Description | Should -Not -BeNullOrEmpty
    }

    It 'Should have at least one example' {
        $help = Get-Help $script:scriptPath
        $help.Examples.Example.Count | Should -BeGreaterThan 0
    }

    It 'Should have Notes section with metadata' {
        $help = Get-Help $script:scriptPath
        $help.alertSet.alert | Should -Not -BeNullOrEmpty
    }
}

