# PowerShell Tests

BeforeAll {
    # Import the script to test
    $script:scriptPath = Join-Path $PSScriptRoot '../../scripts/powershell/Invoke-RemoteScript.ps1'
}

Describe 'Invoke-RemoteScript.ps1 - Script File' {
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

Describe 'Invoke-RemoteScript.ps1 - Parameters' {
    It 'Should have ScriptName parameter' {
        $params = (Get-Command $script:scriptPath).Parameters
        $params.ContainsKey('ScriptName') | Should -Be $true
    }

    It 'Should have ValidateSet on ScriptName parameter' {
        $params = (Get-Command $script:scriptPath).Parameters
        $validateSet = $params['ScriptName'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet | Should -Not -BeNullOrEmpty
        $validateSet.ValidValues | Should -Contain 'health-check'
        $validateSet.ValidValues | Should -Contain 'server-setup'
    }

    It 'Should have CustomUri parameter' {
        $params = (Get-Command $script:scriptPath).Parameters
        $params.ContainsKey('CustomUri') | Should -Be $true
    }

    It 'Should have Arguments parameter as string array' {
        $params = (Get-Command $script:scriptPath).Parameters
        $params.ContainsKey('Arguments') | Should -Be $true
        $params['Arguments'].ParameterType.Name | Should -Match 'String\[\]'
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

    It 'Should have logic to handle ScriptName' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match 'ScriptName'
    }

    It 'Should have logic to handle CustomUri' {
        $scriptContent = Get-Content $script:scriptPath -Raw
        $scriptContent | Should -Match 'CustomUri'
    }
}

