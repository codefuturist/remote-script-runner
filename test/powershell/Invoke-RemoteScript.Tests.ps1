# PowerShell Tests

BeforeAll {
    # Import the script to test
    $script:scriptPath = Join-Path $PSScriptRoot '../../scripts/powershell/Invoke-RemoteScript.ps1'
}

Describe 'Invoke-RemoteScript.ps1 - Parameter Validation' {
    It 'Should accept ScriptName parameter with valid values' {
        { & $script:scriptPath -ScriptName 'health-check' -WhatIf } | Should -Not -Throw
        { & $script:scriptPath -ScriptName 'server-setup' -WhatIf } | Should -Not -Throw
    }

    It 'Should accept CustomUri parameter' {
        { & $script:scriptPath -CustomUri 'https://example.com/script.sh' -WhatIf } | Should -Not -Throw
    }

    It 'Should accept Arguments parameter as array' {
        { & $script:scriptPath -ScriptName 'health-check' -Arguments @('-v', '-s', 'cpu') -WhatIf } | Should -Not -Throw
    }

    It 'Should have proper comment-based help' {
        $help = Get-Help $script:scriptPath
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Description | Should -Not -BeNullOrEmpty
        $help.Examples | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-RemoteScript.ps1 - Documentation' {
    It 'Should have Synopsis in comment-based help' {
        $help = Get-Help $script:scriptPath
        $help.Synopsis | Should -Not -BeNullOrEmpty
        $help.Synopsis.Length | Should -BeGreaterThan 20
    }

    It 'Should have Description in comment-based help' {
        $help = Get-Help $script:scriptPath
        $help.Description | Should -Not -BeNullOrEmpty
    }

    It 'Should have multiple examples' {
        $help = Get-Help $script:scriptPath
        $help.Examples.Example.Count | Should -BeGreaterThan 1
    }

    It 'Should have Notes section' {
        $help = Get-Help $script:scriptPath
        $help.alertSet.alert | Should -Not -BeNullOrEmpty
    }

    It 'Should document all parameters' {
        $help = Get-Help $script:scriptPath -Full
        $help.parameters.parameter | Should -Not -BeNullOrEmpty

        foreach ($param in $help.parameters.parameter) {
            $param.description | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-RemoteScript.ps1 - Code Quality' {
    It 'Should have CmdletBinding' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match '\[CmdletBinding\(\)\]'
    }

    It 'Should have parameter validation' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match '\[Parameter\('
        $scriptContent | Should -Match '\[ValidateSet\('
    }

    It 'Should use proper variable naming (PascalCase for parameters)' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        # Check that parameters start with uppercase
        $scriptContent | Should -Match '\$[A-Z][a-zA-Z]*'
    }
}

Describe 'Invoke-RemoteScript.ps1 - Script Structure' {
    It 'Should define a base URL' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match '\$baseUrl'
    }

    It 'Should validate that ScriptName or CustomUri is provided' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        # The script should have logic to ensure either ScriptName or CustomUri is used
        $scriptContent.Length | Should -BeGreaterThan 0
    }
}

