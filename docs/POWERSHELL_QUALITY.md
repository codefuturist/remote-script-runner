# PowerShell Code Quality Guide

This document describes the PowerShell code quality standards and testing practices for the Remote Script Runner project.

## Overview

PowerShell scripts in this project follow the same rigorous quality standards as shell scripts, with dedicated linting, testing, and CI/CD integration.

## Tools

### PSScriptAnalyzer

**PSScriptAnalyzer** is the official PowerShell linter from Microsoft. It analyzes PowerShell code for best practices, potential bugs, and style violations.

- **Configuration**: `.psscriptanalyzer/PSScriptAnalyzerSettings.psd1`
- **Severity Levels**: Error, Warning, Information
- **Style Rules**: Enforces consistent formatting, naming conventions, and PowerShell best practices

### Pester

**Pester** is the official PowerShell testing framework. It provides BDD-style testing with rich assertion capabilities.

- **Test Location**: `test/powershell/`
- **Test Naming**: `*.Tests.ps1`
- **Style**: Describe/Context/It blocks (BDD)

## Requirements

### PowerShell Core

All scripts target **PowerShell Core (pwsh)** for cross-platform compatibility:

```bash
# macOS
brew install --cask powershell

# Ubuntu/Debian
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
sudo apt-get install -y powershell

# Windows
winget install Microsoft.PowerShell
```

### Modules

Required modules are auto-installed when running tools:

- **PSScriptAnalyzer**: Code linting
- **Pester**: Testing framework

## Local Development

### Running Lints

```bash
# Lint all PowerShell scripts
make lint-powershell

# Or run directly
./tools/lint-powershell.sh

# Auto-fix formatting issues
./tools/lint-powershell.sh --fix
```

### Running Tests

```bash
# Run PowerShell tests
make test-powershell

# Or run directly
./tools/test-powershell.sh

# Verbose output
make test-powershell-verbose
./tools/test-powershell.sh --verbose
```

### Run Everything

```bash
# Run all quality checks (includes PowerShell)
make all
```

## Code Style Guidelines

### 1. Script Structure

```powershell
<#
.SYNOPSIS
    Brief one-line description

.DESCRIPTION
    Detailed description of what the script does

.PARAMETER ParameterName
    Description of parameter

.EXAMPLE
    .\Script.ps1 -Parameter Value
    Description of what this example does

.NOTES
    Version:        1.0
    Author:         Your Name
    Purpose:        Production/Development/Testing
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RequiredParam,

    [Parameter(Mandatory=$false)]
    [switch]$OptionalSwitch
)

# Script implementation
```

### 2. Function Naming

Use **approved PowerShell verbs** and **PascalCase**:

```powershell
# ✅ Good
function Get-SystemInfo { }
function Test-Connection { }
function Set-Configuration { }

# ❌ Bad
function getSystemInfo { }
function CheckConnection { }
function configure { }
```

Get approved verbs: `Get-Verb`

### 3. Parameter Validation

Always validate parameters:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$ServerName,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Production', 'Staging', 'Development')]
    [string]$Environment = 'Development',

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65535)]
    [int]$Port = 22
)
```

### 4. Error Handling

Use try-catch blocks with informative messages:

```powershell
try {
    $result = Get-SomeData -Path $Path
    Write-Verbose "Successfully retrieved data"
} catch {
    Write-Error "Failed to retrieve data: $_"
    throw
}
```

### 5. Output and Logging

```powershell
# Use Write-* cmdlets appropriately
Write-Verbose "Detailed diagnostic information"  # -Verbose flag
Write-Debug "Debug information"                  # -Debug flag
Write-Information "Informational message"        # -InformationAction
Write-Warning "Warning message"                  # Always shown
Write-Error "Error message"                      # Always shown
Write-Host "UI output with color" -ForegroundColor Green  # Console only
```

### 6. Consistency

- **Indentation**: 4 spaces
- **Braces**: Opening brace on same line, closing brace on new line
- **Operators**: Space around operators (`$a = $b + $c`)
- **Pipelines**: One pipeline element per line for readability (when needed)

```powershell
# ✅ Good
Get-ChildItem -Path $Path |
    Where-Object { $_.Length -gt 1MB } |
    Sort-Object -Property LastWriteTime |
    Select-Object -First 10

# ✅ Also good for simple cases
Get-ChildItem -Path $Path | Select-Object -First 10
```

## Testing Best Practices

### Test Structure

```powershell
# Install-OpenSSH.Tests.ps1

BeforeAll {
    # Setup code that runs once before all tests
    $script:scriptPath = Join-Path $PSScriptRoot '../../scripts/powershell/Install-OpenSSH.ps1'
}

Describe 'Install-OpenSSH.ps1' {
    Context 'Parameter Validation' {
        It 'Should accept ClientOnly parameter' {
            { & $script:scriptPath -ClientOnly -WhatIf } | Should -Not -Throw
        }

        It 'Should require administrator privileges' {
            # Test implementation
        }
    }

    Context 'Function Behavior' {
        BeforeEach {
            # Setup before each test
        }

        It 'Should log messages correctly' {
            # Test implementation
        }

        AfterEach {
            # Cleanup after each test
        }
    }
}

AfterAll {
    # Cleanup code that runs once after all tests
}
```

### Mocking

Use `Mock` to avoid side effects:

```powershell
BeforeAll {
    Mock -CommandName Set-Service -MockWith {}
    Mock -CommandName Start-Service -MockWith {}
    Mock -CommandName Get-Service -MockWith {
        return [PSCustomObject]@{
            Name = 'sshd'
            Status = 'Running'
        }
    }
}

It 'Should start the service' {
    Start-MyService -Name 'sshd'
    Should -Invoke Start-Service -Times 1 -Exactly
}
```

### Assertions

```powershell
# Value assertions
$result | Should -Be 'expected'
$result | Should -Not -Be 'unexpected'
$result | Should -BeNullOrEmpty
$result | Should -Not -BeNullOrEmpty

# Type assertions
$result | Should -BeOfType [string]

# Collection assertions
$array | Should -Contain 'item'
$array | Should -HaveCount 5

# Exception assertions
{ Do-Something } | Should -Throw
{ Do-Something } | Should -Not -Throw

# Pattern matching
$result | Should -Match 'pattern'
$result | Should -MatchExactly 'CaseSensitivePattern'
```

## CI/CD Integration

### GitHub Actions

PowerShell quality checks run automatically on:

- **Lint Workflow** (`.github/workflows/lint.yml`):
  - PSScriptAnalyzer on every push/PR
  - Runs on Ubuntu with PowerShell Core
  - Fails on errors, warns on issues

- **Test Workflow** (`.github/workflows/test.yml`):
  - Pester tests on Ubuntu, macOS, and Windows
  - Cross-platform validation
  - Test results uploaded as artifacts

### Local Pre-commit

Before committing, run:

```bash
# Check everything
make all

# Or just PowerShell
make lint-powershell test-powershell
```

## Common Issues and Solutions

### Issue: PSScriptAnalyzer not installed

```bash
# Solution: Auto-installed on first run, or install manually
pwsh -Command "Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser"
```

### Issue: Pester not installed

```bash
# Solution: Auto-installed on first run, or install manually
pwsh -Command "Install-Module -Name Pester -Force -Scope CurrentUser -SkipPublisherCheck"
```

### Issue: Tests fail with WhatIf errors

Some cmdlets don't support `-WhatIf`. Use mocking:

```powershell
BeforeAll {
    Mock -CommandName Set-Service -MockWith {}
}
```

### Issue: Cross-platform path separators

Use `Join-Path` instead of hardcoding `\` or `/`:

```powershell
# ✅ Good
$path = Join-Path $PSScriptRoot 'subfolder' 'file.txt'

# ❌ Bad
$path = "$PSScriptRoot\subfolder\file.txt"
```

## References

- [PSScriptAnalyzer Rules](https://github.com/PowerShell/PSScriptAnalyzer/blob/master/RuleDocumentation/README.md)
- [Pester Documentation](https://pester.dev/docs/quick-start)
- [PowerShell Best Practices](https://docs.microsoft.com/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations)
- [Approved PowerShell Verbs](https://docs.microsoft.com/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands)

## Continuous Improvement

As the project grows:

1. **Add more tests** for edge cases and error conditions
2. **Increase code coverage** target to 80%+
3. **Document complex functions** with comprehensive examples
4. **Review and update** PSScriptAnalyzer rules quarterly
5. **Share knowledge** through team reviews and pair programming
