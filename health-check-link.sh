#!/bin/bash
# Redirect script - acts like a symlink for remote execution
# Fetches and executes the actual script from the repository

# Configuration
REPO_BASE_URL="https://raw.githubusercontent.com/codefuturist/remote-script-runner/main"
TARGET_SCRIPT="scripts/bash/system-health-check.sh"

# Fetch and execute the target script with all arguments
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_BASE_URL/$TARGET_SCRIPT" | bash -s -- "$@"
elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$REPO_BASE_URL/$TARGET_SCRIPT" | bash -s -- "$@"
else
    echo "Error: Neither curl nor wget is available"
    exit 1
fi
