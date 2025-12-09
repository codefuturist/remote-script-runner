# PowerShell Quality Tools - Quick Reference

## 🚀 Quick Start

```bash
# Lint PowerShell scripts
make lint-powershell

# Run PowerShell tests
make test-powershell

# Run everything
make all
```

## 📋 Commands

### Linting

```bash
# Basic lint
./tools/lint-powershell.sh

# Auto-fix formatting issues
./tools/lint-powershell.sh --fix
```

### Testing

```bash
# Run tests
./tools/test-powershell.sh

# Verbose output
./tools/test-powershell.sh --verbose
make test-powershell-verbose
```

### Via Makefile

```bash
make lint-powershell          # Lint PowerShell scripts
make test-powershell          # Run Pester tests
make test-powershell-verbose  # Run tests with detail
make lint                     # Lint everything (includes PowerShell)
make all                      # All quality checks
```

## 📁 Files

```
.psscriptanalyzer/
└── PSScriptAnalyzerSettings.psd1   # Lint configuration

test/powershell/
├── Install-OpenSSH.Tests.ps1       # Tests for Install-OpenSSH.ps1
└── Invoke-RemoteScript.Tests.ps1   # Tests for Invoke-RemoteScript.ps1

tools/
├── lint-powershell.sh              # Linting wrapper
└── test-powershell.sh              # Testing wrapper

docs/
├── POWERSHELL_QUALITY.md           # Full guide (380+ lines)
└── POWERSHELL_IMPLEMENTATION_SUMMARY.md  # Implementation details
```

## 🔧 Installation

PowerShell Core is required:

```bash
# macOS
brew install --cask powershell

# Ubuntu/Debian
wget -q https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update && sudo apt-get install -y powershell

# Windows
winget install Microsoft.PowerShell
```

Modules auto-install on first run:
- PSScriptAnalyzer
- Pester

## ✅ What Gets Checked

### Linting (PSScriptAnalyzer)
- ✅ Code style (indentation, braces, casing)
- ✅ Best practices (error handling, parameter validation)
- ✅ Security issues (hardcoded values, credentials)
- ✅ Documentation (comment-based help)
- ✅ Naming conventions (approved verbs, PascalCase)

### Testing (Pester)
- ✅ Script structure and existence
- ✅ Parameter types and validation
- ✅ Function presence and naming
- ✅ Documentation completeness
- ✅ Code quality standards

## 🎯 CI/CD

### Workflows

**`.github/workflows/lint.yml`**
- Job: `psscriptanalyzer`
- Platform: Ubuntu
- Runs on: Push to main/develop, PRs

**`.github/workflows/test.yml`**
- Job: `test-powershell`
- Platforms: Ubuntu, macOS, Windows
- Runs on: Push to main/develop, PRs

### Results

Tests and lint results upload as artifacts automatically.

## 📊 Current Status

- **Scripts**: 2 PowerShell files
- **Tests**: 36 tests (35 passing, 97.2%)
- **Linting**: Active (52 warnings in Install-OpenSSH.ps1)
- **CI/CD**: ✅ Integrated

## 🐛 Common Issues

### PowerShell not found
```bash
# Check installation
command -v pwsh

# Install if missing (see Installation above)
```

### Module not found
Modules auto-install. If issues occur:
```bash
pwsh -Command "Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser"
pwsh -Command "Install-Module -Name Pester -Force -Scope CurrentUser -SkipPublisherCheck"
```

### Tests fail with WhatIf errors
Scripts may not support `-WhatIf`. Tests validate structure, not execution.

## 📚 Documentation

- **Full Guide**: [`docs/POWERSHELL_QUALITY.md`](POWERSHELL_QUALITY.md)
- **Implementation**: [`docs/POWERSHELL_IMPLEMENTATION_SUMMARY.md`](POWERSHELL_IMPLEMENTATION_SUMMARY.md)
- **Test Guide**: [`test/README.md`](../test/README.md)

## 💡 Tips

1. **Fix formatting automatically**: `./tools/lint-powershell.sh --fix`
2. **Run before commit**: `make all`
3. **Verbose test output**: `./tools/test-powershell.sh --verbose`
4. **Check a specific file**: `pwsh -Command "Invoke-ScriptAnalyzer -Path scripts/powershell/Install-OpenSSH.ps1"`

## 🔗 Resources

- [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
- [Pester Documentation](https://pester.dev)
- [PowerShell Best Practices](https://docs.microsoft.com/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations)

---

**Quick Check**: `make lint-powershell test-powershell` ✨

