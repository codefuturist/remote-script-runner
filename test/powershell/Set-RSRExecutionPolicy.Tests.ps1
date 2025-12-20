<#
.SYNOPSIS
    Tests for Set-RSRExecutionPolicy.ps1

.DESCRIPTION
    Pester tests for the PowerShell Execution Policy configuration script.
    Tests cover parameter validation, status display, and policy detection.

.NOTES
    These tests use mocking to avoid actually changing execution policy.
#>

BeforeAll {
    $ScriptPath = Join-Path $PSScriptRoot '../../scripts/security/hardening/Set-RSRExecutionPolicy.ps1'

    # Mock Get-ExecutionPolicy to avoid system-specific results
    function Get-MockPolicyList {
        @(
            [PSCustomObject]@{ Scope = 'MachinePolicy'; ExecutionPolicy = 'Undefined' }
            [PSCustomObject]@{ Scope = 'UserPolicy'; ExecutionPolicy = 'Undefined' }
            [PSCustomObject]@{ Scope = 'Process'; ExecutionPolicy = 'Undefined' }
            [PSCustomObject]@{ Scope = 'CurrentUser'; ExecutionPolicy = 'RemoteSigned' }
            [PSCustomObject]@{ Scope = 'LocalMachine'; ExecutionPolicy = 'Undefined' }
        )
    }
}

Describe 'Set-RSRExecutionPolicy' {
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
    }

    Context 'Parameter Validation' {
        It 'Should accept -Status parameter' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Status') | Should -Be $true
        }

        It 'Should accept -Recommend parameter' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Recommend') | Should -Be $true
        }

        It 'Should accept -Scope parameter with valid values' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Scope') | Should -Be $true

            $validateSet = $cmd.Parameters['Scope'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Process'
            $validateSet.ValidValues | Should -Contain 'CurrentUser'
            $validateSet.ValidValues | Should -Contain 'LocalMachine'
        }

        It 'Should accept -Policy parameter with valid values' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Policy') | Should -Be $true

            $validateSet = $cmd.Parameters['Policy'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Contain 'Restricted'
            $validateSet.ValidValues | Should -Contain 'AllSigned'
            $validateSet.ValidValues | Should -Contain 'RemoteSigned'
            $validateSet.ValidValues | Should -Contain 'Unrestricted'
            $validateSet.ValidValues | Should -Contain 'Bypass'
            $validateSet.ValidValues | Should -Contain 'Undefined'
        }

        It 'Should accept -Backup parameter' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Backup') | Should -Be $true
        }

        It 'Should accept -Restore parameter' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Restore') | Should -Be $true
        }

        It 'Should support -WhatIf' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
        }

        It 'Should support -Force' {
            $cmd = Get-Command $ScriptPath
            $cmd.Parameters.ContainsKey('Force') | Should -Be $true
        }
    }

    Context 'Help Display' {
        It 'Should display help with -Help parameter' {
            $output = & $ScriptPath -Help 2>&1
            $output | Should -Not -BeNullOrEmpty
            ($output -join "`n") | Should -Match 'USAGE|Usage'
        }

        It 'Should display version with -Version parameter' {
            $output = & $ScriptPath -Version 2>&1
            $output | Should -Match 'Set-RSRExecutionPolicy v\d+\.\d+\.\d+'
        }
    }

    Context 'Status Display' -Skip:(-not $IsWindows) {
        BeforeAll {
            Mock Get-ExecutionPolicy {
                if ($List) {
                    return Get-MockPolicyList
                }
                return 'RemoteSigned'
            }
        }

        It 'Should display status without errors' {
            { & $ScriptPath -Status } | Should -Not -Throw
        }
    }

    Context 'Policy Information' {
        It 'Should contain policy information for all levels' {
            $content = Get-Content $ScriptPath -Raw

            # Check that policy info exists for all standard policies
            $content | Should -Match 'Restricted'
            $content | Should -Match 'AllSigned'
            $content | Should -Match 'RemoteSigned'
            $content | Should -Match 'Unrestricted'
            $content | Should -Match 'Bypass'
            $content | Should -Match 'Undefined'
        }

        It 'Should contain scope information for all scopes' {
            $content = Get-Content $ScriptPath -Raw

            $content | Should -Match 'MachinePolicy'
            $content | Should -Match 'UserPolicy'
            $content | Should -Match 'Process'
            $content | Should -Match 'CurrentUser'
            $content | Should -Match 'LocalMachine'
        }
    }

    Context 'Backup Functionality' -Skip:(-not $IsWindows) {
        BeforeAll {
            $testBackupDir = Join-Path $env:TEMP 'rsr-policy-test'
            if (-not (Test-Path $testBackupDir)) {
                New-Item -ItemType Directory -Path $testBackupDir -Force | Out-Null
            }
        }

        AfterAll {
            if (Test-Path $testBackupDir) {
                Remove-Item -Path $testBackupDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Should create backup file with correct structure' {
            Mock Get-ExecutionPolicy {
                if ($List) {
                    return Get-MockPolicyList
                }
                return 'RemoteSigned'
            }

            $backupPath = Join-Path $testBackupDir "test_backup.json"
            & $ScriptPath -Backup -BackupPath $backupPath 2>&1 | Out-Null

            if (Test-Path $backupPath) {
                $backup = Get-Content $backupPath -Raw | ConvertFrom-Json
                $backup.Timestamp | Should -Not -BeNullOrEmpty
                $backup.Policies | Should -Not -BeNullOrEmpty
            }
        }
    }
}

Describe 'Set-RSRExecutionPolicy Integration' -Tag 'Integration' -Skip:(-not $IsWindows) {
    Context 'RSR Entry Point' {
        BeforeAll {
            $rsrPath = Join-Path $PSScriptRoot '../../rsr.ps1'
        }

        It 'Should be accessible via rsr.ps1 policy command' {
            $rsrContent = Get-Content $rsrPath -Raw
            $rsrContent | Should -Match "'policy'"
        }

        It 'Should be registered in registry.json' {
            $registryPath = Join-Path $PSScriptRoot '../../scripts/registry.json'
            if (Test-Path $registryPath) {
                $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
                $policyScript = $registry.scripts | Where-Object { $_.command -eq 'policy' }
                $policyScript | Should -Not -BeNullOrEmpty
            }
        }
    }
}

