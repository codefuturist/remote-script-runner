# PowerShell Tests

BeforeAll {
    # Import the script to test
    $script:scriptPath = Join-Path $PSScriptRoot '../../scripts/powershell/Install-OpenSSH.ps1'

    # Mock functions and commands to avoid actual system changes during tests
    Mock -CommandName Set-Service -MockWith {}
    Mock -CommandName Start-Service -MockWith {}
    Mock -CommandName Restart-Service -MockWith {}
    Mock -CommandName New-NetFirewallRule -MockWith {}
    Mock -CommandName Add-Content -MockWith {}
}

Describe 'Install-OpenSSH.ps1 - Parameter Validation' {
    It 'Should accept ClientOnly parameter' {
        { & $script:scriptPath -ClientOnly -WhatIf } | Should -Not -Throw
    }

    It 'Should accept ServerOnly parameter' {
        { & $script:scriptPath -ServerOnly -WhatIf } | Should -Not -Throw
    }

    It 'Should have proper comment-based help' {
        $help = Get-Help $script:scriptPath
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.Examples | Should -Not -BeNullOrEmpty
    }
}

Describe 'Install-OpenSSH.ps1 - Functions' {
    BeforeAll {
        # Dot-source the script to load its functions without executing the main script
        # Note: This requires the script to be structured to support dot-sourcing
        # For now, we'll test the script as a whole
    }

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

    It 'Should use approved verbs for functions' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $functions = [regex]::Matches($scriptContent, 'function ([A-Z][a-zA-Z]*)-') | ForEach-Object { $_.Groups[1].Value }

        foreach ($verb in $functions) {
            $approvedVerbs = Get-Verb | Select-Object -ExpandProperty Verb
            $verb | Should -BeIn $approvedVerbs
        }
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

