#!/bin/bash

# Test script for SSH Configuration Manager remote execution
# This demonstrates how to use the script via HTTPS once published

echo "SSH Configuration Manager Remote Execution Test"
echo "=============================================="
echo

# Once the repository is published, you can use these commands:

echo "Example 1: Initialize SSH configuration"
echo "curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- init"
echo

echo "Example 2: Generate SSH key"
echo "curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- generate-key -t ed25519 -C 'user@example.com'"
echo

echo "Example 3: Add host configuration"
echo "curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- add-host myserver -H example.com -u myuser -p 22"
echo

echo "Example 4: List hosts with verbose output"
echo "curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- -v list-hosts"
echo

echo "Example 5: Apply security hardening"
echo "curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- harden"
echo

echo "Example 6: Check permissions"
echo "curl -fsSL https://raw.githubusercontent.com/codefuturist/remote-script-runner/main/ssh-config-manager.sh | bash -s -- check-permissions"
echo

echo "For local testing (before repository is published):"
echo "---------------------------------------------------"
echo

# Local test - this works now
SCRIPT_PATH="/Users/colin/Cloud/Nextcloud/Development/remote-script-runner/scripts/bash/ssh-config-manager.sh"

if [ -f "$SCRIPT_PATH" ]; then
    echo "Testing local execution..."
    echo "Running: $SCRIPT_PATH list-hosts"
    "$SCRIPT_PATH" list-hosts
else
    echo "Script not found at: $SCRIPT_PATH"
fi
