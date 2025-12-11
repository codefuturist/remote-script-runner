#!/bin/sh
# lib/config.sh - Central configuration for Remote Script Runner
# Source this file in scripts: . "${0%/*}/../lib/config.sh" or . ./lib/config.sh
#
# POSIX-compatible for maximum portability

# =============================================================================
# Version (Single Source of Truth)
# =============================================================================

# Read from VERSION file if available, otherwise use fallback
if [ -f "${RSR_ROOT:-}/VERSION" ]; then
    RSR_VERSION=$(cat "${RSR_ROOT}/VERSION" | tr -d '[:space:]')
elif [ -f "./VERSION" ]; then
    RSR_VERSION=$(cat "./VERSION" | tr -d '[:space:]')
else
    RSR_VERSION="1.0.0"
fi

# =============================================================================
# URLs (Single Source of Truth)
# =============================================================================

REPO_BASE_URL="https://scripts.pandia.io"
REPO_GITHUB_URL="https://github.com/codefuturist/remote-script-runner"

# =============================================================================
# Default Settings
# =============================================================================

RSR_DEFAULT_TIMEOUT="${RSR_TIMEOUT:-10}"
RSR_DEFAULT_SHELL="${RSR_SHELL:-}"

# Export for subshells
export RSR_VERSION
export REPO_BASE_URL
export REPO_GITHUB_URL
