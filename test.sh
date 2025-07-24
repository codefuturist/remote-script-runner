#!/bin/bash
# Simple test runner for remote-script-runner
# Tests basic functionality without adding complexity

set -euo pipefail

echo "=== Remote Script Runner Test Suite ==="
echo

# Test local execution
echo "1. Testing local execution..."
if ./system-health-check.sh -s uptime >/dev/null 2>&1; then
    echo "   ✓ Local execution works"
else
    echo "   ✗ Local execution failed"
    exit 1
fi

# Test help output
echo "2. Testing help output..."
if ./system-health-check.sh -h | grep -q "AVAILABLE CHECKS"; then
    echo "   ✓ Help output works"
else
    echo "   ✗ Help output failed"
    exit 1
fi

# Test dry-run mode
echo "3. Testing dry-run mode..."
if ./server-setup.sh -d -u testuser -p development nginx 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -q "DRY RUN MODE"; then
    echo "   ✓ Dry-run mode works"
else
    echo "   ✗ Dry-run mode failed"
    exit 1
fi

# Test verbose output
echo "4. Testing verbose output..."
if ./system-health-check.sh -v -s cpu 2>&1 | grep -E "\[INFO\]|INFO" >/dev/null; then
    echo "   ✓ Verbose output works"
else
    echo "   ✗ Verbose output failed"
    exit 1
fi

echo
echo "=== All tests passed! ==="
