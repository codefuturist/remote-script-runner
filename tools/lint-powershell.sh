#!/bin/bash
# =============================================================================
# PowerShell Linting Script - Cross-platform PSScriptAnalyzer runner
# =============================================================================
#
# This script runs PSScriptAnalyzer on PowerShell files to ensure code quality.
# Works on macOS, Linux, and Windows (with PowerShell Core installed).
#
# Usage: ./tools/lint-powershell.sh [--fix]
#
# Options:
#   --fix    Auto-fix formatting issues where possible
#
# Requirements:
#   - PowerShell Core (pwsh) installed
#   - PSScriptAnalyzer module (auto-installed if missing)
#
# Exit codes:
#   0 - All checks passed
#   1 - Linting errors found
#   2 - PowerShell not available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PS_SCRIPTS_DIR="$ROOT_DIR/scripts/powershell"
SETTINGS_FILE="$ROOT_DIR/.psscriptanalyzer/PSScriptAnalyzerSettings.psd1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FIX_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)
            FIX_MODE=true
            shift
            ;;
        -h | --help)
            echo "Usage: $0 [--fix]"
            echo ""
            echo "Options:"
            echo "  --fix    Auto-fix formatting issues where possible"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}" >&2
            exit 1
            ;;
    esac
done

log_info() { printf "${BLUE}▸${NC} %s\n" "$1"; }
log_ok() { printf "${GREEN}✓${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}⚠${NC} %s\n" "$1"; }
log_error() { printf "${RED}✗${NC} %s\n" "$1"; }

# Check if PowerShell Core is installed
check_pwsh() {
    if ! command -v pwsh >/dev/null 2>&1; then
        log_error "PowerShell Core (pwsh) is not installed"
        echo ""
        echo "Install PowerShell Core:"
        echo "  macOS:   brew install --cask powershell"
        echo "  Linux:   See https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux"
        echo "  Windows: winget install Microsoft.PowerShell"
        echo ""
        return 1
    fi
    return 0
}

# Main script
main() {
    log_info "Checking PowerShell environment..."

    if ! check_pwsh; then
        exit 2
    fi

    log_ok "PowerShell Core is available"

    # Check if PSScriptAnalyzer is installed, install if needed
    log_info "Checking PSScriptAnalyzer module..."

    pwsh -NoProfile -Command "
        if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
            Write-Host '${YELLOW}▸${NC} Installing PSScriptAnalyzer module...' -NoNewline
            Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -Repository PSGallery
            Write-Host ' ${GREEN}Done${NC}'
        }
    " || {
        log_error "Failed to install PSScriptAnalyzer"
        exit 1
    }

    log_ok "PSScriptAnalyzer module is ready"

    # Run PSScriptAnalyzer
    log_info "Running PSScriptAnalyzer on PowerShell scripts..."
    echo ""

    FIX_FLAG=""
    if [ "$FIX_MODE" = true ]; then
        FIX_FLAG="-Fix"
        log_info "Auto-fix mode enabled"
    fi

    # Run the analyzer using a PowerShell script
    pwsh -NoProfile -Command "
        \$ErrorActionPreference = 'Continue'

        # Import module
        Import-Module PSScriptAnalyzer -ErrorAction Stop

        # Get all PowerShell files
        \$scriptsPath = '$PS_SCRIPTS_DIR'
        \$settingsPath = '$SETTINGS_FILE'
        \$fixMode = '$FIX_MODE'

        \$scripts = Get-ChildItem -Path \$scriptsPath -Filter '*.ps1' -File

        \$totalIssues = 0
        \$hasErrors = \$false

        foreach (\$script in \$scripts) {
            Write-Host ''
            Write-Host 'Analyzing: ' -NoNewline
            Write-Host \$script.Name -ForegroundColor Cyan
            Write-Host ('─' * 80)

            # Build parameters
            \$params = @{
                Path = \$script.FullName
                Settings = \$settingsPath
                Severity = @('Error', 'Warning', 'Information')
            }

            if (\$fixMode -eq 'true') {
                \$params['Fix'] = \$true
            }

            # Run analyzer
            try {
                \$results = Invoke-ScriptAnalyzer @params
            } catch {
                Write-Host \"  Error analyzing file: \$_\" -ForegroundColor Red
                \$hasErrors = \$true
                continue
            }

            if (\$results) {
                \$totalIssues += \$results.Count

                foreach (\$result in \$results) {
                    # Color by severity
                    \$color = switch (\$result.Severity) {
                        'Error'       { 'Red' }
                        'Warning'     { 'Yellow' }
                        'Information' { 'Cyan' }
                        default       { 'White' }
                    }

                    \$icon = switch (\$result.Severity) {
                        'Error'       { '✗' }
                        'Warning'     { '⚠' }
                        'Information' { 'ℹ' }
                        default       { '•' }
                    }

                    Write-Host \"  \$icon \" -ForegroundColor \$color -NoNewline
                    Write-Host \"[\$(\$result.Severity)] \" -ForegroundColor \$color -NoNewline
                    Write-Host \"Line \$(\$result.Line): \" -NoNewline
                    Write-Host \$result.RuleName -ForegroundColor White
                    Write-Host \"    \$(\$result.Message)\" -ForegroundColor Gray

                    if (\$result.Severity -eq 'Error') {
                        \$hasErrors = \$true
                    }
                }
            } else {
                Write-Host '  ✓ No issues found' -ForegroundColor Green
            }
        }

        Write-Host ''
        Write-Host ('═' * 80)

        if (\$totalIssues -eq 0) {
            Write-Host '✓ All PowerShell scripts passed linting' -ForegroundColor Green
            exit 0
        } else {
            Write-Host \"Found \$totalIssues issue(s) in PowerShell scripts\" -ForegroundColor Yellow

            if (\$hasErrors) {
                Write-Host '✗ Linting failed with errors' -ForegroundColor Red
                exit 1
            } else {
                Write-Host '✓ No errors found (warnings/info only)' -ForegroundColor Green
                exit 0
            }
        }
    "

    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo ""
        log_ok "PowerShell linting completed successfully"
    else
        echo ""
        log_error "PowerShell linting found issues"
    fi

    exit $exit_code
}

main

