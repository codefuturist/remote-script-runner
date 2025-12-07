#!/bin/bash
# Universal Symlink Handler for Remote Execution
# This script enables symlinks to work when executed remotely via curl
#
# Usage: 
# 1. Replace your symlinks with copies of this script
# 2. Set the TARGET variable to point to the actual script
# 3. The script will work both locally (as a regular script) and remotely (via curl)

# CONFIGURATION - Set this to your target script path
TARGET="scripts/bash/system-health-check.sh"

# Auto-detect if we're running locally or remotely
if [ -f "$TARGET" ]; then
    # Local execution - just run the target script directly
    exec "$TARGET" "$@"
else
    # Remote execution - fetch and run from GitHub Pages
    REPO_BASE_URL="https://codefuturist.github.io/remote-script-runner"
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_BASE_URL/$TARGET" | bash -s -- "$@"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$REPO_BASE_URL/$TARGET" | bash -s -- "$@"
    else
        echo "Error: Neither curl nor wget is available"
        exit 1
    fi
fi
