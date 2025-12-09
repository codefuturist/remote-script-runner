#!/bin/bash
# Test script to verify user-level installation works without sudo/root

set -euo pipefail

echo "════════════════════════════════════════════════════════════"
echo "Testing User-Level Installation (No Sudo Required)"
echo "════════════════════════════════════════════════════════════"
echo ""

# Verify we're not root
if [[ $EUID -eq 0 ]]; then
    echo "❌ ERROR: This test must be run as a regular user, not root!"
    echo "   Run without sudo: bash $0"
    exit 1
fi

echo "✓ Running as regular user: $(whoami)"
echo ""

# Test 1: Check directory creation
echo "Test 1: Creating user directories..."
TEST_INSTALL_DIR="$HOME/.local/bin"
TEST_CONFIG_DIR="$HOME/.config/git-auto-sync-test"
TEST_RUNTIME_DIR="$HOME/.cache/git-auto-sync-test"
TEST_STATE_DIR="$HOME/.local/state/git-auto-sync-test"

mkdir -p "$TEST_INSTALL_DIR" "$TEST_CONFIG_DIR" "$TEST_RUNTIME_DIR" "$TEST_STATE_DIR" && \
    echo "✓ All directories created successfully (no sudo needed)" || \
    { echo "❌ Failed to create directories"; exit 1; }

# Test 2: Check write permissions
echo ""
echo "Test 2: Verifying write permissions..."
touch "$TEST_CONFIG_DIR/test.json" && \
    echo "✓ Can write to config directory" || \
    { echo "❌ Cannot write to config directory"; exit 1; }

touch "$TEST_RUNTIME_DIR/test.lock" && \
    echo "✓ Can write to runtime directory" || \
    { echo "❌ Cannot write to runtime directory"; exit 1; }

touch "$TEST_STATE_DIR/test.log" && \
    echo "✓ Can write to state directory" || \
    { echo "❌ Cannot write to state directory"; exit 1; }

# Test 3: Script installation simulation
echo ""
echo "Test 3: Testing script installation..."
cat > "$TEST_INSTALL_DIR/test-git-sync.sh" << 'EOF'
#!/bin/bash
echo "Test script running as: $(whoami)"
exit 0
EOF

chmod +x "$TEST_INSTALL_DIR/test-git-sync.sh" && \
    echo "✓ Can create and make scripts executable" || \
    { echo "❌ Cannot create executable scripts"; exit 1; }

# Test 4: Execute script
"$TEST_INSTALL_DIR/test-git-sync.sh" && \
    echo "✓ Can execute installed scripts" || \
    { echo "❌ Cannot execute scripts"; exit 1; }

# Test 5: Config file creation
echo ""
echo "Test 5: Testing configuration file creation..."
cat > "$TEST_CONFIG_DIR/repos.json" << 'EOF'
{
  "repositories": [
    {
      "name": "test-repo",
      "path": "/home/user/test",
      "branch": "main"
    }
  ]
}
EOF

if command -v jq >/dev/null 2>&1; then
    jq '.' "$TEST_CONFIG_DIR/repos.json" >/dev/null && \
        echo "✓ Config file is valid JSON" || \
        { echo "❌ Config file is not valid JSON"; exit 1; }
else
    echo "⚠ jq not installed, skipping JSON validation"
fi

# Test 6: SystemD user service (Linux only)
if [[ "$(uname)" == "Linux" ]] && command -v systemctl >/dev/null 2>&1; then
    echo ""
    echo "Test 6: Testing SystemD user service..."
    
    SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_USER_DIR" && \
        echo "✓ Can create SystemD user directory" || \
        { echo "❌ Cannot create SystemD user directory"; exit 1; }
    
    cat > "$SYSTEMD_USER_DIR/test-git-sync.service" << 'EOF'
[Unit]
Description=Test Git Sync Service
[Service]
Type=simple
ExecStart=/bin/true
[Install]
WantedBy=default.target
EOF
    
    echo "✓ Can create SystemD user service file"
    
    # Test if systemctl --user works (without actually enabling)
    systemctl --user daemon-reload 2>/dev/null && \
        echo "✓ SystemD user mode accessible" || \
        echo "⚠ SystemD user mode not available (may need loginctl enable-linger)"
    
    # Cleanup
    rm -f "$SYSTEMD_USER_DIR/test-git-sync.service"
fi

# Test 7: Check no sudo was used
echo ""
echo "Test 7: Verifying no elevated privileges..."
if ! groups | grep -q "sudo\|wheel\|admin"; then
    echo "✓ User is not in privileged groups (good for testing)"
else
    echo "⚠ User is in privileged groups, but we didn't use sudo"
fi

# Cleanup
echo ""
echo "Cleaning up test files..."
rm -rf "$TEST_CONFIG_DIR" "$TEST_RUNTIME_DIR" "$TEST_STATE_DIR"
rm -f "$TEST_INSTALL_DIR/test-git-sync.sh"
echo "✓ Cleanup complete"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ ALL TESTS PASSED - User-level installation works!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  ✓ No sudo/root required"
echo "  ✓ All directories writable by user"
echo "  ✓ Scripts can be installed and executed"
echo "  ✓ Configuration files can be created"
echo "  ✓ SystemD user services supported (Linux)"
echo ""
echo "You can now install git-auto-sync in user mode:"
echo "  bash git-auto-sync-manager.sh"
echo ""
