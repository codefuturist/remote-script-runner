#!/bin/bash

# Symlink Replacement Template
# This template creates scripts that work like symlinks for remote execution
# Copy this file and modify the TARGET variable

# TARGET: Set this to the path of the script you want to link to
TARGET="scripts/bash/ssh-config-manager.sh"

# Auto-detect execution context and run appropriately
if [ -f "$TARGET" ]; then
    # Local execution - run the target directly
    exec "$TARGET" "$@"
else
    # Remote execution - fetch from GitHub
    # Try to detect the repository URL from git remote if available
    if command -v git >/dev/null 2>&1 && git remote get-url origin >/dev/null 2>&1; then
        REPO_URL=$(git remote get-url origin | sed 's/\.git$//' | sed 's/github.com:/github.com\//')
        REPO_BASE_URL="https://raw.githubusercontent.com/${REPO_URL#*github.com/}/main"
    else
        # Fallback to hardcoded URL
        REPO_BASE_URL="https://raw.githubusercontent.com/codefuturist/remote-script-runner/main"
    fi
    
    # Download and execute
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_BASE_URL/$TARGET" | bash -s -- "$@"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$REPO_BASE_URL/$TARGET" | bash -s -- "$@"
    else
        echo "Error: Neither curl nor wget is available"
        exit 1
    fi
fi
